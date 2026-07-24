"""Teste dos 30 segundos (CANARIO.md secao 17, passo 1).

Para cada marca candidata do painel, descobre o dominio real e detecta se a
loja expoe catalogo publico por VTEX ou Shopify. Quem falhar fica fora da
coleta v1: sem headless browser e sem burlar protecao (regra inviolavel 7).

Etiqueta de coleta (regra 7): no maximo 1 requisicao por segundo por dominio,
User-Agent identificavel, robots.txt respeitado, so pagina publica.
"""

import csv
import json
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone
from urllib.robotparser import RobotFileParser

UA = "CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)"
TIMEOUT = 20
INTERVALO_POR_DOMINIO = 1.0  # regra 7: 1 req/s por dominio

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAINEL = os.path.join(RAIZ, "anexos", "painel_marcas.csv")

# Caminhos testados. O termo "vestido" e o da secao 17.
CAMINHO_VTEX = "/api/catalog_system/pub/products/search/vestido"
CAMINHO_SHOPIFY = "/products.json?limit=5"

# Candidatos de dominio por marca. O Anexo B nao traz dominio; esta lista e a
# proposta do agente e vira a coluna `dominio` depois de confirmada pelo teste.
CANDIDATOS = {
    "Cantao": ["www.cantao.com.br", "cantao.com.br"],
    "Shoulder": ["www.shoulder.com.br", "shoulder.com.br"],
    "Dress To": ["www.dressto.com.br", "dressto.com.br"],
    "Lanca Perfume": ["www.lancaperfume.com.br", "lancaperfume.com.br"],
    "Morena Rosa": ["www.morenarosa.com.br", "morenarosa.com.br"],
    "Zinzane": ["www.zinzane.com.br", "zinzane.com.br"],
    "Amaro": ["amaro.com", "www.amaro.com"],
    "Mixed": ["www.mixed.com.br", "mixed.com.br"],
    "Le Lis Blanc": ["www.lelis.com.br", "www.lelisblanc.com.br", "lelis.com.br"],
    "Bo.Bo": ["www.bobo.com.br", "bobo.com.br"],
    "Colcci": ["www.colcci.com.br", "colcci.com.br"],
    "PatBo": ["www.patbo.com.br", "patbo.com", "www.patbo.com"],
    "Renner": ["www.lojasrenner.com.br", "lojasrenner.com.br"],
    "C&A": ["www.cea.com.br", "cea.com.br"],
    "Youcom": ["www.youcom.com.br", "youcom.com.br"],
    "Hering": ["www.hering.com.br", "hering.com.br"],
    "Farm": ["www.farmrio.com.br", "farmrio.com.br"],
    "Animale": ["www.animale.com.br", "animale.com.br"],
    "Maria Filo": ["www.mariafilo.com.br", "mariafilo.com.br"],
    "Fabula": ["www.fabula.com.br", "fabula.com.br"],
    "NV": ["www.nv.com.br", "www.usenv.com.br", "nvbrand.com.br"],
    "Foxton": ["www.foxton.com.br", "foxton.com.br"],
    "Dafiti": ["www.dafiti.com.br", "dafiti.com.br"],
    "Iguatemi 365": ["www.iguatemi365.com.br", "iguatemi365.com.br"],
    "Shop2gether": ["www.shop2gether.com.br", "shop2gether.com.br"],
    "Centauro": ["www.centauro.com.br", "centauro.com.br"],
}

_travas = {}
_trava_global = threading.Lock()
_ultimo_acesso = {}


def _respeitar_ritmo(dominio):
    """Garante no minimo 1 segundo entre requisicoes ao mesmo dominio."""
    with _trava_global:
        trava = _travas.setdefault(dominio, threading.Lock())
    with trava:
        anterior = _ultimo_acesso.get(dominio)
        if anterior is not None:
            espera = INTERVALO_POR_DOMINIO - (time.monotonic() - anterior)
            if espera > 0:
                time.sleep(espera)
        _ultimo_acesso[dominio] = time.monotonic()


def buscar(url, dominio):
    """Retorna (codigo_http, corpo_texto, url_final) sem levantar excecao."""
    _respeitar_ritmo(dominio)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "pt-BR,pt;q=0.9",
    })
    contexto = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=contexto) as resp:
            # Sem corte: a busca da VTEX devolve o produto inteiro e 10 itens
            # passam de 600 KB com folga. Truncar aqui quebra o JSON e faz a
            # marca parecer reprovada.
            bruto = resp.read(25_000_000)
            return (resp.status, bruto.decode("utf-8", "replace"), resp.geturl(),
                    dict(resp.headers))
    except urllib.error.HTTPError as e:
        return e.code, "", url, dict(getattr(e, "headers", {}) or {})
    except Exception as e:  # DNS, TLS, timeout, conexao recusada
        return None, "erro:{}".format(type(e).__name__), url, {}


def robots_permite(dominio, caminho):
    """Le robots.txt com o nosso UA. Na duvida, permite (padrao da RFC)."""
    codigo, corpo, _, _ = buscar("https://{}/robots.txt".format(dominio), dominio)
    if codigo != 200 or not corpo:
        return True, "sem robots.txt"
    parser = RobotFileParser()
    parser.parse(corpo.splitlines())
    permitido = parser.can_fetch(UA, "https://{}{}".format(dominio, caminho))
    return permitido, "robots.txt lido"


def testar_vtex(dominio):
    permitido, _ = robots_permite(dominio, CAMINHO_VTEX)
    if not permitido:
        return None, "robots proibe o caminho vtex"
    codigo, corpo, _, cabecalhos = buscar(
        "https://{}{}".format(dominio, CAMINHO_VTEX), dominio)
    # A VTEX responde 206 (Partial Content) neste endpoint por padrao: a
    # paginacao usa REST Range e sem header de range ela devolve o primeiro
    # bloco. 206 e sucesso, nao falha.
    if codigo not in (200, 206):
        return None, "vtex http {}".format(codigo)
    try:
        dados = json.loads(corpo)
    except ValueError:
        return None, "vtex resposta nao-json"
    if isinstance(dados, list) and dados and isinstance(dados[0], dict) and "items" in dados[0]:
        # O header `resources` vem como "0-9/847": o total apos a barra e o
        # tamanho do catalogo para a consulta, util para dimensionar a coleta.
        total = ""
        recurso = cabecalhos.get("resources") or cabecalhos.get("Resources") or ""
        if "/" in recurso:
            total = " de {} no catalogo para 'vestido'".format(recurso.split("/")[-1])
        return "vtex", "{} produtos na sonda{}".format(len(dados), total)
    return None, "vtex json sem produtos"


def testar_shopify(dominio):
    permitido, _ = robots_permite(dominio, CAMINHO_SHOPIFY)
    if not permitido:
        return None, "robots proibe products.json"
    codigo, corpo, _, _ = buscar("https://{}{}".format(dominio, CAMINHO_SHOPIFY), dominio)
    if codigo != 200:
        return None, "shopify http {}".format(codigo)
    try:
        dados = json.loads(corpo)
    except ValueError:
        return None, "shopify resposta nao-json"
    if isinstance(dados, dict) and isinstance(dados.get("products"), list):
        return "shopify", "{} produtos na sonda".format(len(dados["products"]))
    return None, "shopify json sem products"


def testar_marca(marca):
    """Tenta cada dominio candidato; para no primeiro que responder."""
    candidatos = CANDIDATOS.get(marca)
    if not candidatos:
        return {"marca": marca, "dominio": "", "status_teste": "falhou",
                "detalhe_teste": "sem dominio candidato"}

    tentativas = []
    for dominio in candidatos:
        codigo, _, url_final, _ = buscar("https://{}/".format(dominio), dominio)
        if codigo is None:
            # DNS/TLS/conexao falhou: dominio nao existe, tentar o proximo.
            tentativas.append("{}: home inacessivel".format(dominio))
            continue

        # A home respondeu. Mesmo um 403 na home (anti-bot no HTML) nao impede
        # que a API de catalogo esteja aberta, entao seguimos sondando.
        host_final = urllib.parse.urlparse(url_final).hostname or dominio

        for sonda in (testar_vtex, testar_shopify):
            plataforma, detalhe = sonda(host_final)
            if plataforma:
                return {"marca": marca, "dominio": host_final,
                        "status_teste": plataforma, "detalhe_teste": detalhe}
            tentativas.append("{}: {}".format(host_final, detalhe))

    return {"marca": marca, "dominio": candidatos[0], "status_teste": "falhou",
            "detalhe_teste": " | ".join(tentativas[:3])}


def main():
    with open(PAINEL, newline="", encoding="utf-8") as f:
        linhas = list(csv.DictReader(f))

    pendentes = [l for l in linhas if l.get("status_teste") == "pendente"]
    print("Marcas a testar: {} (as de papel `direcao` sao `nao_se_aplica` e ficam fora)".format(
        len(pendentes)), file=sys.stderr)

    with ThreadPoolExecutor(max_workers=8) as pool:
        resultados = list(pool.map(lambda l: testar_marca(l["marca"]), pendentes))

    por_marca = {r["marca"]: r for r in resultados}
    hoje = date.today().isoformat()

    for linha in linhas:
        r = por_marca.get(linha["marca"])
        if r:
            linha["dominio"] = r["dominio"]
            linha["status_teste"] = r["status_teste"]
            linha["data_teste"] = hoje
            linha["detalhe_teste"] = r["detalhe_teste"]
        else:
            linha.setdefault("dominio", "")
            linha.setdefault("data_teste", "")
            linha.setdefault("detalhe_teste", "")

    campos = ["marca", "dominio", "segmento", "papel", "justificativa",
              "status_teste", "data_teste", "detalhe_teste"]
    with open(PAINEL, "w", newline="", encoding="utf-8") as f:
        escritor = csv.DictWriter(f, fieldnames=campos, extrasaction="ignore")
        escritor.writeheader()
        escritor.writerows(linhas)

    saida = {
        "executado_em": datetime.now(timezone.utc).isoformat(),
        "resultados": resultados,
    }
    print(json.dumps(saida, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
