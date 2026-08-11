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

    print("VTEX: 150/150 ids unicos, com reparo ASC/DESC")
    return 0


if __name__ == "__main__":
    sys.exit(main())
