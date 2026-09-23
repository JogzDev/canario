"""Contrato do coletor da Nuvemshop (Amaro desde 23/09/2026), sem rede.

A fixture e uma pagina real de produto da Amaro, enxugada: o conteiner
`#single-product` inteiro, os JSON-LD do documento e um produto relacionado
com o mesmo tipo de formulario de variacoes -- que nunca pode ser lido como o
principal.
"""

from datetime import date
import os
import re

import coletor_varejo as varejo


DOMINIO = "amaro.com"
HOSPEDAGEM = "https://amaro32.lojavirtualnuvem.com.br"
URL = "https://amaro.com/produtos/camisa-manga-curta-verde/"
PASTA = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(PASTA, "fixtures", "nuvemshop_produto.html")
ROBOTS = ("User-agent: *\nDisallow: /admin/\nDisallow: /checkout/\n"
          "Disallow: /*?*preview_theme_installation_id*\n"
          "Disallow: /*?view=\n")


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def sitemap(caminhos, raiz="urlset"):
    item = "sitemap" if raiz == "sitemapindex" else "url"
    return ('<?xml version="1.0"?><{0} xmlns="http://www.sitemaps.org/schemas/'
            'sitemap/0.9">{1}</{0}>').format(raiz, "".join(
                "<{0}><loc>{1}{2}</loc></{0}>".format(item, HOSPEDAGEM, c)
                for c in caminhos))


def com_rede_falsa(respostas, funcao, *args):
    original = varejo.buscar_varejo
    chamadas = []

    def buscar_falso(url, _dominio):
        chamadas.append(url)
        return respostas.get(url, (404, "", url, {}))

    varejo.buscar_varejo = buscar_falso
    try:
        return funcao(*args), chamadas
    finally:
        varejo.buscar_varejo = original


def main():
    pagina = open(FIXTURE, encoding="utf-8").read()
    produto = varejo.nuvemshop_extrair_pagina(pagina, URL)

    # O principal, nunca o relacionado que vem depois com outro product_id.
    if produto["id_externo"] != "359097141":
        return falhar("leu o produto relacionado: {}".format(produto["id_externo"]))
    if (produto["titulo"] != "CAMISA MANGA CURTA - VERDE"
            or produto["categoria_site"] != "/MODA/ROUPAS/BLUSAS & CAMISAS/"):
        return falhar("titulo ou trilha mudou: {} | {}".format(
            produto["titulo"], produto["categoria_site"]))
    # Tamanho e a SEGUNDA opcao (a primeira e COR). Pegar a primeira as cegas
    # gravaria "VERDE" como tamanho, o defeito que a Shopify ja teve.
    if produto["grade_por_tamanho"] != {"36": False, "38": False, "40": False,
                                        "42": True, "44": False, "46": False}:
        return falhar("grade errada: {}".format(produto["grade_por_tamanho"]))
    if (produto["preco_atual"] != 129.9 or produto["preco_original"] != 179.9
            or produto["ofertavel"] is not True):
        return falhar("preco de/por ou oferta nao vieram das variacoes")
    if produto["composicao"] != "NEW PLISSE SUBLIMADO 100% POLIESTER / FORRO MALHA HELANCA":
        return falhar("composicao da descricao se perdeu: {}".format(produto["composicao"]))
    if not (produto["imagem_url"] or "").startswith("https://dcdn-us.mitiendanube.com/"):
        return falhar("imagem publica se perdeu")

    # Esgotado continua sendo lido: sem ele nao existe reposicao.
    esgotada = re.sub(r"(&quot;available&quot;:\s*)true", r"\1false", pagina)
    if esgotada == pagina:
        return falhar("fixture perdeu as variacoes disponiveis")
    lido = varejo.nuvemshop_extrair_pagina(esgotada, URL)
    if lido["ofertavel"] is not False or any(lido["grade_por_tamanho"].values()):
        return falhar("peca esgotada nao ficou indisponivel")
    if lido["preco_atual"] != 129.9:
        return falhar("peca esgotada perdeu o preco de contexto")

    # A composicao no paragrafo seguinte, em outro negrito, tambem vale; um
    # bloco novo encerra a espera, para "Troca & Devolucao" nunca virar tecido.
    outra = pagina.replace(
        "<strong>Composição</strong><br>NEW PLISSE SUBLIMADO 100% POLIESTER / FORRO MALHA HELANCA",
        "<p><strong> COMPOSIÇÃO</strong></p><p> <strong> 100% Poliéster</strong></p>")
    if outra == pagina:
        return falhar("fixture perdeu o trecho da composicao")
    if varejo.nuvemshop_extrair_pagina(outra, URL)["composicao"] != "100% Poliéster":
        return falhar("composicao em paragrafo seguinte nao foi lida")
    sem_valor = pagina.replace(
        "<strong>Composição</strong><br>NEW PLISSE SUBLIMADO 100% POLIESTER / FORRO MALHA HELANCA",
        "<strong>Composição</strong></div><div><strong>Troca & Devolução Fácil*</strong>")
    if varejo.nuvemshop_extrair_pagina(sem_valor, URL)["composicao"] is not None:
        return falhar("texto de outro bloco virou composicao")

    # Pagina sem o conteiner principal, ou com dois, falha alto.
    for quebrada in (pagina.replace('id="single-product"', 'id="outro"'),
                     pagina + pagina):
        try:
            varejo.nuvemshop_extrair_pagina(quebrada, URL)
        except ValueError:
            continue
        return falhar("pagina sem um unico #single-product foi aceita")
    divergente = re.sub(r"(LS\.product\s*=\s*\{\s*id\s*:\s*)\d+", r"\g<1>1", pagina)
    try:
        varejo.nuvemshop_extrair_pagina(divergente, URL)
    except ValueError:
        pass
    else:
        return falhar("LS.product divergente das variacoes foi aceito")

    # Sitemap: reescreve a hospedagem para o dominio, ignora categorias e a
    # propria vitrine, deduplica e respeita o robots.
    respostas = {
        "https://amaro.com/robots.txt": (200, ROBOTS, "https://amaro.com/robots.txt", {}),
        "https://amaro.com/sitemap.xml": (200, sitemap([
            "/", "/produtos/", "/produtos/camisa-manga-curta-verde/",
            "/produtos/camisa-manga-curta-verde/", "/produtos/trench-coat-curto-marrom/",
            "/moda1/roupas3/"]), "https://amaro.com/sitemap.xml", {}),
    }
    estado = {"erro": None, "truncou": False}
    urls, chamadas = com_rede_falsa(respostas, varejo.nuvemshop_urls, DOMINIO, estado)
    if urls != [URL, "https://amaro.com/produtos/trench-coat-curto-marrom/"]:
        return falhar("sitemap mal lido: {}".format(urls))
    if estado["erro"] or estado["truncou"] or estado["urls_no_sitemap"] != 2:
        return falhar("estado do sitemap errado: {}".format(estado))
    if any("lojavirtualnuvem" in c for c in chamadas):
        return falhar("coleta foi a hospedagem em vez do dominio da loja")

    # Produto em host estranho falha fechada; indice de sitemaps tambem.
    for corpo, esperado in (
            (sitemap(["/"]).replace(HOSPEDAGEM, "https://evil.test") .replace(
                "<loc>https://evil.test/</loc>",
                "<loc>https://evil.test/produtos/x/</loc>"), "autorizado"),
            (sitemap(["/sitemap_2.xml"], raiz="sitemapindex"), "indice")):
        respostas["https://amaro.com/sitemap.xml"] = (
            200, corpo, "https://amaro.com/sitemap.xml", {})
        estado = {"erro": None}
        urls, _ = com_rede_falsa(respostas, varejo.nuvemshop_urls, DOMINIO, estado)
        if urls or esperado not in (estado.get("erro") or ""):
            return falhar("sitemap perigoso aceito: {}".format(estado))

    # Com 500 enderecos e produto no fim, o sitemap pode ter cortado: o
    # portao trata como truncado em vez de publicar catalogo parcial.
    caminhos = ["/pagina-{}/".format(i) for i in range(140)]
    caminhos += ["/produtos/p-{}/".format(i) for i in range(360)]
    respostas["https://amaro.com/sitemap.xml"] = (
        200, sitemap(caminhos), "https://amaro.com/sitemap.xml", {})
    estado = {"erro": None, "truncou": False}
    com_rede_falsa(respostas, varejo.nuvemshop_urls, DOMINIO, estado)
    if not estado["truncou"]:
        return falhar("sitemap no teto com produto no fim nao foi marcado")
    caminhos.append("/categoria/")
    respostas["https://amaro.com/sitemap.xml"] = (
        200, sitemap(caminhos), "https://amaro.com/sitemap.xml", {})
    estado = {"erro": None, "truncou": False}
    com_rede_falsa(respostas, varejo.nuvemshop_urls, DOMINIO, estado)
    if estado["truncou"]:
        return falhar("sitemap com categoria no fim foi marcado como truncado")

    # Coleta ponta a ponta pela marca: 404 de produto que saiu da loja conta
    # como ausente, nao como falha; o sitemap e o total declarado.
    respostas["https://amaro.com/sitemap.xml"] = (200, sitemap([
        "/produtos/camisa-manga-curta-verde/", "/produtos/saiu-da-loja/"]),
        "https://amaro.com/sitemap.xml", {})
    respostas[URL] = (200, pagina, URL, {})
    original_gravar = varejo.gravar_lote
    lotes = []
    varejo.gravar_lote = lambda _m, lote, _h: (lotes.append(list(lote)) or
                                                (len(lote), len(lote)))
    try:
        metrica, _ = com_rede_falsa(
            respostas, varejo.coletar_marca,
            {"id": 7, "nome": "Amaro", "dominio": DOMINIO,
             "plataforma": "nuvemshop"}, date(2026, 9, 23), {})
    finally:
        varejo.gravar_lote = original_gravar
    alertas = metrica["alertas"] or {}
    if (metrica["visitados"] != 1 or metrica["declarado"] != 2
            or alertas.get("paginas_ausentes") != 1 or alertas.get("erro")):
        return falhar("metrica da coleta errada: {}".format(metrica))
    if [d["id_externo"] for lote in lotes for d in lote] != ["359097141"]:
        return falhar("lote gravado errado")

    print("OK: Nuvemshop le o produto principal, o esgotado, a composicao e o "
          "sitemap autorizado; falha fechada fora do caminho")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
