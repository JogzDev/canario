"""Regressao da paginacao VTEX: empate de preco nao pode sumir com produtos."""

import json
import sys
import urllib.parse

import coletor_varejo as varejo


def main():
    original = varejo.buscar_varejo
    chamadas = []

    def buscar_falso(url, _dominio):
        chamadas.append(url)
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        ordem = query["O"][0]
        inicio = int(query["_from"][0])
        fim = int(query["_to"][0]) + 1
        # ASC simula uma ordenacao com empate: a terceira pagina repete a
        # segunda. DESC oferece o trecho que faltou, como a passagem de reparo.
        if ordem == "OrderByNameASC" and inicio >= 100:
            inicio, fim = 50, 100
        elif ordem == "OrderByNameDESC":
            inicio, fim = 100, 150
        produtos = [{"productId": str(i)} for i in range(inicio, fim)]
        return 206, json.dumps(produtos), url, {"resources": "0-149/150"}

    varejo.buscar_varejo = buscar_falso
    try:
        produtos = list(varejo._paginar("loja.test", "1", 150))
    finally:
        varejo.buscar_varejo = original

    ids = {produto["productId"] for produto in produtos}
    if len(produtos) != 150 or len(ids) != 150:
        print("FALHOU: passagem inversa nao recuperou os 150 ids unicos")
        return 1
    if not any("O=OrderByNameDESC" in url for url in chamadas):
        print("FALHOU: paginacao incompleta nao acionou a passagem inversa")
        return 1
    if any("OrderByPrice" in url for url in chamadas):
        print("FALHOU: ordenacao por preco voltou a paginacao")
        return 1

    # Uma contagem HTTP que falha não pode virar simplesmente zero. Foi assim
    # que a Bo.Bo chegou ao portão como ``visit=0`` e ``alertas=None``: o
    # coletor engoliu o status e a saúde só conseguiu dizer "sem motivo".
    def buscar_503(url, _dominio):
        return 503, "", url, {}

    varejo.buscar_varejo = buscar_503
    try:
        estado = {"erro": None}
        total = varejo._contar("loja.test", "2", estado=estado)
    finally:
        varejo.buscar_varejo = original
    if total is not None or "http 503" not in (estado.get("erro") or ""):
        print("FALHOU: contagem VTEX perdeu o motivo HTTP")
        return 1

    # Sucesso sem o header que contém o total também é contrato quebrado, não
    # catálogo vazio. O diagnóstico precisa permanecer explícito e crítico.
    def buscar_sem_total(url, _dominio):
        return 206, "[]", url, {}

    varejo.buscar_varejo = buscar_sem_total
    try:
        estado = {"erro": None}
        total = varejo._contar("loja.test", "2", estado=estado)
    finally:
        varejo.buscar_varejo = original
    if total is not None or "sem header Resources" not in (estado.get("erro") or ""):
        print("FALHOU: contagem VTEX sem total foi tratada como catálogo vazio")
        return 1

    # A contagem pode funcionar e uma pagina posterior sofrer rate-limit. Era
    # exatamente o caso da Farm: 2.946 declarados, 200 visitados e workflow
    # verde porque `_paginar` engolia o 429. A saude precisa preservar a causa.
    def buscar_pagina_429(url, _dominio):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        inicio = int(query["_from"][0])
        if inicio >= 50:
            return 429, "", url, {}
        produtos = [{"productId": str(i)} for i in range(50)]
        return 206, json.dumps(produtos), url, {"resources": "0-49/150"}

    varejo.buscar_varejo = buscar_pagina_429
    try:
        estado = {"erro": None}
        produtos = list(varejo._paginar(
            "loja.test", "3", 150, estado=estado))
    finally:
        varejo.buscar_varejo = original
    if len(produtos) != 50 or "http 429 ao paginar" not in (
            estado.get("erro") or ""):
        print("FALHOU: paginacao VTEX perdeu o motivo HTTP")
        return 1

    # Na C&A o índice Legacy põe indisponíveis antigos em P:[0 TO 1]. A faixa
    # tem mais de 40 mil registros, mas o filtro oficial de disponibilidade
    # deixa cerca de mil ofertas reais. O coletor precisa paginar essas ofertas
    # por inteiro, não escolher 2.500 indisponíveis por ordem alfabética.
    contar_original = varejo._contar
    paginar_original = varejo._paginar
    chamadas_disponiveis = []

    def contar_faixa(_dominio, _cat, _pmin=None, _pmax=None, estado=None,
                     somente_ofertaveis=False):
        return 1016 if somente_ofertaveis else 41013

    def paginar_faixa(_dominio, _cat, limite, _pmin=None, _pmax=None,
                      estado=None, somente_ofertaveis=False):
        chamadas_disponiveis.append(somente_ofertaveis)
        for i in range(limite):
            yield {"productId": str(i)}

    varejo._contar = contar_faixa
    varejo._paginar = paginar_faixa
    try:
        estado = {"erro": None, "declarado": 0, "truncou": False}
        recuperados = list(varejo._faixa_indivisivel(
            "loja.test", "1/2/3", estado, 0, 1, 41013))
    finally:
        varejo._contar = contar_original
        varejo._paginar = paginar_original
    if len(recuperados) != 1016 or estado["truncou"]:
        print("FALHOU: faixa zero da C&A ainda truncou ofertas reais")
        return 1
    if chamadas_disponiveis != [True]:
        print("FALHOU: fallback da faixa zero não filtrou disponibilidade")
        return 1
    if estado.get("indisponiveis_fora_do_universo") != 39997:
        print("FALHOU: descarte de indisponíveis não ficou observável")
        return 1

    # Departamentos de topo podem ser vitrines sobrepostas. A NV declara 415
    # em Roupas, 563 em New In e 351 em Linhas, mas a união tem 563 IDs. Quando
    # todas as páginas terminam, o denominador correto é a união observada.
    departamentos_original = varejo.vtex_departamentos_femininos
    coletar_original = varejo.vtex_departamento
    extrair_original = varejo.vtex_extrair
    gravar_original = varejo.gravar_lote
    robots_original = varejo.robots_permite
    conjuntos = {
        2: range(0, 415),
        29: range(0, 563),
        131: range(100, 451),
    }

    def departamentos_falsos(*_args):
        return [(2, "Roupas"), (29, "New In"), (131, "Linhas")], ""

    def coletar_falso(_dominio, cat_id, estado):
        ids = conjuntos[cat_id]
        estado["declarado"] += len(ids)
        for i in ids:
            yield {"productId": str(i)}

    def extrair_falso(p, _dominio):
        return {"id_externo": p["productId"], "titulo": "Peça",
                "url": None, "categoria_site": "Roupas",
                "imagem_url": None, "preco_original": 1,
                "preco_atual": 1, "composicao": None,
                "grade_por_tamanho": {"U": True}, "ofertavel": True}

    varejo.vtex_departamentos_femininos = departamentos_falsos
    varejo.vtex_departamento = coletar_falso
    varejo.vtex_extrair = extrair_falso
    varejo.gravar_lote = lambda _m, lote, _h: (0, len(lote))
    varejo.robots_permite = lambda *_args: (True, "")
    try:
        metrica = varejo.coletar_marca(
            {"id": 1, "nome": "NV", "dominio": "loja.test",
             "plataforma": "vtex"}, varejo.date(2026, 8, 21), {})
    finally:
        varejo.vtex_departamentos_femininos = departamentos_original
        varejo.vtex_departamento = coletar_original
        varejo.vtex_extrair = extrair_original
        varejo.gravar_lote = gravar_original
        varejo.robots_permite = robots_original
    if metrica["visitados"] != 563 or metrica["declarado"] != 563:
        print("FALHOU: vitrines sobrepostas inflaram o declarado da NV")
        return 1
    if metrica["alertas"]:
        print("FALHOU: sobreposição completa virou alerta de perda")
        return 1

    # Uma árvore antiga pode continuar cadastrada mesmo vazia ao lado da
    # vitrine atual. Dress To ainda declara Lovedress (28, zero) e dress to
    # (58, vivo). O ramo aposentado não pode contaminar uma coleta completa;
    # se TODOS os ramos vierem zerados, porém, o alerta continua obrigatório.
    def departamentos_com_ramo_vazio(*_args):
        return [(28, "Lovedress"), (58, "dress to")], ""

    def coletar_com_ramo_vazio(_dominio, cat_id, estado):
        if cat_id == 28:
            estado.setdefault("categorias_vazias", []).append(str(cat_id))
            return
        estado["declarado"] += 2
        yield {"productId": "vivo-1"}
        yield {"productId": "vivo-2"}

    varejo.vtex_departamentos_femininos = departamentos_com_ramo_vazio
    varejo.vtex_departamento = coletar_com_ramo_vazio
    varejo.vtex_extrair = extrair_falso
    varejo.gravar_lote = lambda _m, lote, _h: (0, len(lote))
    varejo.robots_permite = lambda *_args: (True, "")
    try:
        metrica = varejo.coletar_marca(
            {"id": 2, "nome": "Dress To", "dominio": "loja.test",
             "plataforma": "vtex"}, varejo.date(2026, 8, 21), {})
    finally:
        varejo.vtex_departamentos_femininos = departamentos_original
        varejo.vtex_departamento = coletar_original
        varejo.vtex_extrair = extrair_original
        varejo.gravar_lote = gravar_original
        varejo.robots_permite = robots_original
    if metrica["visitados"] != 2 or metrica["alertas"]:
        print("FALHOU: ramo VTEX aposentado contaminou catálogo vivo")
        return 1

    def departamentos_todos_vazios(*_args):
        return [(28, "Lovedress"), (99, "Legado")], ""

    def coletar_tudo_vazio(_dominio, cat_id, estado):
        estado.setdefault("categorias_vazias", []).append(str(cat_id))
        return
        yield  # pragma: no cover -- preserva a interface de gerador

    varejo.vtex_departamentos_femininos = departamentos_todos_vazios
    varejo.vtex_departamento = coletar_tudo_vazio
    varejo.gravar_lote = lambda _m, lote, _h: (0, len(lote))
    varejo.robots_permite = lambda *_args: (True, "")
    try:
        metrica = varejo.coletar_marca(
            {"id": 3, "nome": "Loja vazia", "dominio": "loja.test",
             "plataforma": "vtex"}, varejo.date(2026, 8, 21), {})
    finally:
        varejo.vtex_departamentos_femininos = departamentos_original
        varejo.vtex_departamento = coletar_original
        varejo.gravar_lote = gravar_original
        varejo.robots_permite = robots_original
    if "zero em todas as categorias 28, 99" not in (
            (metrica.get("alertas") or {}).get("erro") or ""):
        print("FALHOU: catálogo inteiro zerado deixou de ser crítico")
        return 1

    # O host administrativo da Maria Filó aceita a rota, mas redireciona o
    # usuário para /admin/login. O coletor precisa persistir a mesma rota no
    # domínio público, mantendo todos os links antigos e novos clicáveis.
    produto_maria_filo = {
        "productId": "123",
        "linkText": "camisa-listrada-linho-listrado-15-27910-0015",
        "link": "https://mariafilo.vtexcommercestable.com.br/camisa-listrada-linho-listrado-15-27910-0015/p",
        "productName": "Camisa Listrada Linho",
    }
    extraido = varejo.vtex_extrair(
        produto_maria_filo, "mariafilo.vtexcommercestable.com.br")
    if extraido["url"] != (
            "https://www.mariafilo.com.br/"
            "camisa-listrada-linho-listrado-15-27910-0015/p"):
        print("FALHOU: link administrativo da Maria Filó não virou link público")
        return 1

    print("VTEX: paginacao completa e falhas de contagem diagnosticadas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
