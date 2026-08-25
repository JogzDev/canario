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


def _requisicao(metodo, caminho, corpo=None, prefer=None, params="",
                tentativas=3, timeout=None):
    """Uma chamada ao PostgREST, com retry para erro transitorio.

    `timeout` sobrescreve o padrao de 30s. Existe para o motor: uma funcao de
    lote como `computar_curva_tamanhos()` leva mais de um minuto, e o cliente
    desistia antes do servidor terminar -- com o agravante de que o retry
    mandava o Postgres refazer o trabalho inteiro a cada tentativa.
    """
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

    espera = timeout or TIMEOUT
    ultimo_erro = None
    for tentativa in range(tentativas):
        req = urllib.request.Request(endereco, data=dados, headers=cabecalhos, method=metodo)
        try:
            with urllib.request.urlopen(req, timeout=espera) as resp:
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


def rpc(nome, parametros=None, tentativas=3, timeout=None):
    """Chama uma função PostgREST e devolve o JSON já decodificado."""
    _, dados = _requisicao("POST", "rpc/" + nome,
                           corpo=parametros or {}, tentativas=tentativas,
                           timeout=timeout)
    return dados


def upsert(tabela, linhas, on_conflict, retornar=False):
    """Insere ou atualiza em lote, resolvendo por on_conflict."""
    if not linhas:
        return []
    prefer = "resolution=merge-duplicates," + ("return=representation" if retornar else "return=minimal")
    params = "?on_conflict={}".format(on_conflict)
    _, dados = _requisicao("POST", tabela, corpo=linhas, prefer=prefer, params=params)
    return dados or []


def inserir_ignorando_existentes(tabela, linhas, on_conflict):
    """Insere so o que ainda nao existe. Linha ja gravada nao e reescrita.

    Diferente de `upsert`, que resolve conflito com `merge-duplicates` e por
    isso REESCREVE a linha inteira mesmo quando nada mudou. O Postgres nao tem
    update de graca: toda reescrita descarta a versao antiga e grava uma nova,
    e a antiga so volta a ser espaco util depois do vacuum.

    Existe por causa de `artigos`. Medido em 19/08/2026: 120.753 linhas,
    194.052 updates, 3,3% deles HOT, e a tabela sem passar por vacuum desde
    01/08. A coleta editorial re-upsertava por `url` todo dia os mesmos artigos
    que os feeds continuam publicando, gravando titulo, veiculo e data_pub
    identicos aos que ja estavam la.

    E preciso dizer o que isto NAO e: `artigos` nao esta inchada. Medida no mesmo
    dia, ela aproveita 95,2% do heap -- 25 MB uteis em 26 MB. O autovacuum da
    conta. Entao nao ha MB para recuperar aqui, e quem vier atras nao deve tentar
    `fillfactor` como no P8: em `produtos` ele paga porque a coleta reescreve 53
    mil linhas por dia; aqui deixaria a tabela 1,43x maior de forma permanente
    para baratear um trabalho que simplesmente nao precisa acontecer.

    O ganho e o que se deixa de gastar: WAL, CPU e tupla morta que o autovacuum
    tem de limpar depois. Artigo e fato imutavel -- veiculo, url, titulo e data
    de publicacao nao mudam depois de publicados, e a §18 proibe guardar o texto
    -- entao a escrita certa e nao escrever.

    Correcao pontual de linha ja gravada continua possivel por SQL. O que deixa
    de existir e a reescrita automatica e diaria do que nao mudou.
    """
    if not linhas:
        return []
    _requisicao("POST", tabela, corpo=linhas,
                prefer="resolution=ignore-duplicates,return=minimal",
                params="?on_conflict={}".format(on_conflict))
    return []


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


def apagar(tabela, filtro):
    """DELETE com filtro PostgREST (ex.: "origem=eq.titulo").

    Existe para o motor poder RECOMPUTAR de verdade: upsert so acrescenta, e
    ligacao criada por versao antiga do matcher ficaria no banco para sempre.
    """
    _requisicao("DELETE", tabela, params="?" + filtro, prefer="return=minimal")


def inserir(tabela, linhas, retornar=False):
    if not linhas:
        return []
    prefer = "return=representation" if retornar else "return=minimal"
    _, dados = _requisicao("POST", tabela, corpo=linhas, prefer=prefer)
    return dados or []


def contar(tabela, params=""):
    """Contagem exata via Content-Range, opcionalmente com filtros REST."""
    separador = "&" if params else ""
    endereco = "{}/rest/v1/{}?select=*{}{}".format(
        URL, tabela, separador, params.lstrip("?"))
    cabecalhos = {"apikey": KEY, "Authorization": "Bearer " + KEY,
                  "Prefer": "count=exact", "Range": "0-0"}
    req = urllib.request.Request(endereco, headers=cabecalhos, method="GET")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        faixa = resp.headers.get("Content-Range", "")  # ex: 0-0/123
    return int(faixa.split("/")[-1]) if "/" in faixa else None
