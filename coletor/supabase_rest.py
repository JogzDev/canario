"""Cliente REST minimo do Supabase (PostgREST), stdlib apenas.

O coletor escreve com a chave secreta (SUPABASE_SECRET_KEY), que mapeia para o
role service_role e ignora RLS. O app nunca usa isto: le com a chave publishable
e so enxerga series_semanais (ver migracao 0001).

Sem dependencia de terceiros (regra da §26: dependencias minimas e justificadas).
"""

import json
import os
import time
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TIMEOUT = 30


class SupabaseErro(Exception):
    pass


def configurado():
    return bool(URL and KEY)


def _requisicao(metodo, caminho, corpo=None, prefer=None, params="", tentativas=3):
    if not configurado():
        raise SupabaseErro("SUPABASE_URL ou SUPABASE_SECRET_KEY ausentes no ambiente")

    endereco = "{}/rest/v1/{}{}".format(URL, caminho, params)
    cabecalhos = {
        "apikey": KEY,
        "Authorization": "Bearer " + KEY,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if prefer:
        cabecalhos["Prefer"] = prefer
    dados = json.dumps(corpo).encode("utf-8") if corpo is not None else None

    ultimo_erro = None
    for tentativa in range(tentativas):
        req = urllib.request.Request(endereco, data=dados, headers=cabecalhos, method=metodo)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                bruto = resp.read()
                texto = bruto.decode("utf-8", "replace") if bruto else ""
                return resp.status, (json.loads(texto) if texto else None)
        except urllib.error.HTTPError as e:
            detalhe = e.read().decode("utf-8", "replace") if e.fp else ""
            # 4xx nao melhora com retry (erro de schema/permissao): falha logo.
            if 400 <= e.code < 500:
                raise SupabaseErro("{} {} -> HTTP {}: {}".format(
                    metodo, caminho, e.code, detalhe[:300]))
            ultimo_erro = "HTTP {}: {}".format(e.code, detalhe[:200])
        except Exception as e:
            ultimo_erro = "{}: {}".format(type(e).__name__, e)
        if tentativa < tentativas - 1:
            time.sleep(2 ** tentativa)
    raise SupabaseErro("{} {} falhou apos {} tentativas: {}".format(
        metodo, caminho, tentativas, ultimo_erro))


def selecionar(tabela, params=""):
    _, dados = _requisicao("GET", tabela, params=params)
    return dados or []


def upsert(tabela, linhas, on_conflict, retornar=False):
    """Insere ou atualiza em lote, resolvendo por on_conflict."""
    if not linhas:
        return []
    prefer = "resolution=merge-duplicates," + ("return=representation" if retornar else "return=minimal")
    params = "?on_conflict={}".format(on_conflict)
    _, dados = _requisicao("POST", tabela, corpo=linhas, prefer=prefer, params=params)
    return dados or []


def atualizar(tabela, filtro, campos):
    """UPDATE de campos parciais numa linha que JA existe.

    Existe porque `upsert` com campos parciais nao serve para atualizar: o
    PostgREST trata POST+merge-duplicates como insercao quando nao casa, e uma
    linha parcial estoura os NOT NULL da tabela ("null value in column rotulo").
    Aconteceu ao gravar o veredito de volume dos termos.

    `filtro` e a query PostgREST sem o `?` (ex.: "id=eq.floral").
    """
    _requisicao("PATCH", tabela, corpo=campos, params="?" + filtro,
                prefer="return=minimal")


def inserir(tabela, linhas, retornar=False):
    if not linhas:
        return []
    prefer = "return=representation" if retornar else "return=minimal"
    _, dados = _requisicao("POST", tabela, corpo=linhas, prefer=prefer)
    return dados or []


def contar(tabela):
    """Contagem exata via header Content-Range (barata)."""
    endereco = "{}/rest/v1/{}?select=*".format(URL, tabela)
    cabecalhos = {"apikey": KEY, "Authorization": "Bearer " + KEY,
                  "Prefer": "count=exact", "Range": "0-0"}
    req = urllib.request.Request(endereco, headers=cabecalhos, method="GET")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        faixa = resp.headers.get("Content-Range", "")  # ex: 0-0/123
    return int(faixa.split("/")[-1]) if "/" in faixa else None
