"""Regressoes do planejamento diario do Google Trends."""

import sys
from datetime import date, timedelta

from coletor_trends import planejar_grupos


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

    print("Trends: tres grupos por execucao, cobertura rotativa em tres dias")
    return 0


if __name__ == "__main__":
    sys.exit(main())
