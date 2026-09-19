"""Contrato do fallback publico da Animale, integralmente sem rede."""

from datetime import date
import copy
import json
import os
import sys

import coletor_varejo as varejo


DOMINIO = "www.animale.com.br"
URL_PRODUTO = "https://www.animale.com.br/vestido-de-linho/p"
URL_UNICODE = ("https://www.animale.com.br/"
               "short-prega-frente-marrom\u00a0rum-marrom-rum-25-05-4329-09032/p")
URL_ASCII = ("https://www.animale.com.br/"
             "short-prega-frente-marrom%C2%A0rum-marrom-rum-25-05-4329-09032/p")
PASTA = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(PASTA, "fixtures", "animale_next_data.json")


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def html_do(dados):
    return ('<html><script type="application/ld+json">{}</script>'
            '<script id="__NEXT_DATA__" type="application/json">{}</script>'
            '</html>').format(
                json.dumps({"nao": "usar"}),
                json.dumps(dados, ensure_ascii=False))


def xml(tipo, urls):
    raiz = "sitemapindex" if tipo == "indice" else "urlset"
    item = "sitemap" if tipo == "indice" else "url"
    return ('<?xml version="1.0"?><{0} xmlns="http://www.sitemaps.org/'
            'schemas/sitemap/0.9">{1}</{0}>').format(
                raiz, "".join("<{0}><loc>{1}</loc></{0}>".format(item, u)
                              for u in urls))


def main():
    dados = json.load(open(FIXTURE, encoding="utf-8"))
    produto = varejo.animale_extrair_pagina(html_do(dados), URL_PRODUTO)
    if produto["id_externo"] != "53085":
        return falhar("productGroupID nao preservou o antigo productId VTEX")
    if (produto["titulo"] != "Vestido de linho"
            or produto["categoria_site"] != "LAST CHANCE"):
        return falhar("titulo ou recorte comercial mudou na conversao")
    if (produto["preco_atual"] != 399 or produto["preco_original"] != 599
            or produto["grade_por_tamanho"] != {"P": True, "M": False}
            or produto["ofertavel"] is not True):
        return falhar("preco, grade ou oferta nao vieram das variantes publicas")
    if (produto["composicao"] != "100% Linho"
            or not produto["imagem_url"].endswith("/vestido.jpg")):
        return falhar("composicao ou imagem publica se perdeu")

    fora = copy.deepcopy(dados)
    trilha = fora["props"]["pageProps"]["data"]["product"]["breadcrumbList"]
    trilha["itemListElement"] = [{"item": "/novidades/", "name": "Novidades"}]
    if varejo.animale_extrair_pagina(html_do(fora), URL_PRODUTO) is not None:
        return falhar("pagina fora de LAST CHANCE entrou no painel")

    sem_id = copy.deepcopy(dados)
    sem_id["props"]["pageProps"]["data"]["product"]["isVariantOf"].pop(
        "productGroupID")
    try:
        varejo.animale_extrair_pagina(html_do(sem_id), URL_PRODUTO)
    except ValueError:
        pass
    else:
        return falhar("produto sem chave compativel foi aceito")

    # Um robots e dois XML bastam para autorizar e listar as paginas; nenhum
    # endpoint /api ou /_next/data pode aparecer sequer nas chamadas falsas.
    original_buscar = varejo.buscar_varejo
    chamadas = []
    mapa = "https://{}/sitemap/product-0.xml".format(DOMINIO)
    respostas = {
        "https://{}/robots.txt".format(DOMINIO): (
            200, "User-agent: *\nDisallow: /cart\nDisallow: /api/\n"
            "Disallow: /_next/data/\nAllow: /\n",
            "https://{}/robots.txt".format(DOMINIO), {}),
        "https://{}/sitemap.xml".format(DOMINIO): (
            200, xml("indice", [
                "https://{}/sitemap/category-0.xml".format(DOMINIO), mapa]),
            "https://{}/sitemap.xml".format(DOMINIO), {}),
        mapa: (200, xml("produtos", [
            URL_PRODUTO, URL_PRODUTO, URL_UNICODE, URL_ASCII,
            "https://{}/carteira-de-couro/p".format(DOMINIO)]), mapa, {}),
    }

    def buscar_falso(url, _dominio):
        chamadas.append(url)
        return respostas[url]

    varejo.buscar_varejo = buscar_falso
    try:
        estado = {"erro": None}
        urls = varejo.animale_urls_publicas(DOMINIO, estado)
    finally:
        varejo.buscar_varejo = original_buscar
    if (urls != [URL_PRODUTO, URL_ASCII]
            or estado.get("urls_no_sitemap") != 2
            or estado.get("urls_bloqueadas_robots") != 1):
        return falhar("sitemaps nao normalizaram/deduplicaram a URL Unicode")
    try:
        URL_ASCII.encode("ascii")
    except UnicodeEncodeError:
        return falhar("URL normalizada ainda contem caractere fora de ASCII")
    if any("/api/" in u or "/_next/data/" in u for u in chamadas):
        return falhar("fallback tentou uma rota proibida")

    # URL de outro host no XML falha fechada antes de qualquer GET nela.
    respostas[mapa] = (200, xml("produtos", [
        "https://animale.vtexcommercestable.com.br/produto/p"]), mapa, {})
    varejo.buscar_varejo = buscar_falso
    try:
        estado = {"erro": None}
        urls = varejo.animale_urls_publicas(DOMINIO, estado)
    finally:
        varejo.buscar_varejo = original_buscar
    if urls or "autorizado" not in (estado.get("erro") or ""):
        return falhar("host administrativo nao foi recusado")

    # A excecao e estritamente allowlisted por nome + dominio. Outra VTEX que
    # proiba a API preserva o comportamento anterior e nao tenta sitemap.
    original_robots = varejo.robots_permite
    original_animale = varejo.animale_sitemap_todos
    original_gravar = varejo.gravar_lote
    acessos = []
    varejo.robots_permite = lambda *_args: (False, "robots.txt lido")
    varejo.animale_sitemap_todos = lambda _d, estado: (
        estado.update({"urls_no_sitemap": 1, "paginas_lidas": 1,
                       "fora_do_recorte": 0}) or iter([produto]))
    varejo.gravar_lote = lambda _m, lote, _h: (acessos.append(list(lote)) or
                                                (0, len(lote)))
    try:
        metrica = varejo.coletar_marca(
            {"id": 18, "nome": "Animale", "dominio": DOMINIO,
             "plataforma": "vtex"}, date(2026, 9, 20), {})
        outra = varejo.coletar_marca(
            {"id": 99, "nome": "Outra", "dominio": "loja.test",
             "plataforma": "vtex"}, date(2026, 9, 20), {})
    finally:
        varejo.robots_permite = original_robots
        varejo.animale_sitemap_todos = original_animale
        varejo.gravar_lote = original_gravar
    if (metrica["visitados"] != 1 or metrica["declarado"] != 1
            or metrica["alertas"]["origem"] != "sitemap + paginas publicas"
            or len(acessos) != 1):
        return falhar("Animale nao percorreu o fallback allowlisted")
    if outra["visitados"] != 0 or outra["alertas"] != {"erro": "robots proibe a busca"}:
        return falhar("fallback vazou para outra marca VTEX")

    print("Animale: fallback publico preserva universo, identidade e robots")
    return 0


if __name__ == "__main__":
    sys.exit(main())
