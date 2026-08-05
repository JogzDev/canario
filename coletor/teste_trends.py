"""Regressoes do planejamento diario do Google Trends."""

import sys
from datetime import date, timedelta

from coletor_trends import combinar_saude_busca, planejar_grupos


def main():
    grupos = [[str(i)] for i in range(9)]
    inicio = date(2026, 8, 3)
    vistos = set()
    for deslocamento in range(3):
        lote = planejar_grupos(grupos, inicio + timedelta(days=deslocamento))
        if len(lote) != 3:
            print("FALHOU: planejador excedeu o orcamento diario")
            return 1
        vistos.update(g[0] for g in lote)
    if vistos != set(str(i) for i in range(9)):
        print("FALHOU: tres lotes nao cobriram os nove grupos")
        return 1
    if planejar_grupos(grupos, inicio) != planejar_grupos(grupos, inicio):
        print("FALHOU: planejador nao e deterministico")
        return 1

    vistos_no_dia = set()
    for tentativa in range(3):
        lote = planejar_grupos(grupos, inicio, tentativa=tentativa)
        vistos_no_dia.update(g[0] for g in lote)
    if vistos_no_dia != set(str(i) for i in range(9)):
        print("FALHOU: recuperacoes do dia repetiram os mesmos grupos")
        return 1

    legado = {
        "visitados": 3, "gravados": 1, "itens": 1044,
        "alertas": {"grupos_que_falharam": [{"grupo": 1}]},
    }
    atual = {
        "visitados": 3, "gravados": 2, "itens": 1566,
        "alertas": {"modo": "backfill", "grupos_que_falharam": [
            {"grupo": 3}]},
    }
    combinada = combinar_saude_busca(legado, 1, atual)
    if (combinada["visitados"], combinada["gravados"], combinada["itens"]) != (
            6, 3, 2610):
        print("FALHOU: consolidacao nao preservou a primeira tentativa")
        return 1
    repetida = combinar_saude_busca(combinada, 1, atual)
    if repetida != combinada:
        print("FALHOU: repetir tentativa duplicou os totais")
        return 1

    print("Trends: rotacao entre dias/tentativas e saude idempotente")
    return 0


if __name__ == "__main__":
    sys.exit(main())
