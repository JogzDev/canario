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
