"""Teste da fila da perna de busca (§19).

Este arquivo existe porque o MESMO defeito congelou a perna de busca DUAS
vezes, com dezenove e com dezesseis dias de silencio:

  13/07  So existia o modo `backfill`, que pula termo que ja tem serie. Como o
         filtro era permanente, quem ja estava coberto nunca mais era
         consultado.

  20/07  A correcao criou o modo `semanal`, mas condicionado a `backfill` ter
         terminado -- e ele nunca termina. Medido em 05/08: 36 dos 40 termos
         tinham 261 pontos cada (cinco anos), e QUATRO termos sem serie
         (`reta_wide`, `romantico`, `saia`, `short`) prendiam o modo. Sobrava
         um grupo, esse grupo apanhava de 429, e os outros 36 ficavam parados.

A licao das duas vezes e a mesma, e e o que este teste tranca: **"tem serie"
nao e a pergunta certa; a pergunta e "ha quanto tempo"**.

Rodar: python3 coletor/teste_fila_de_busca.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coletor_trends import (corte_de_frescura, fila_por_defasagem,
                            planejar_grupos)  # noqa: E402

from datetime import date  # noqa: E402

falhas = []


checadas = []


def checar(condicao, descricao):
    checadas.append(descricao)
    if condicao:
        print("  ok   {}".format(descricao))
    else:
        print("  FALHOU  {}".format(descricao))
        falhas.append(descricao)


def termos(*ids):
    return [{"id": i, "termo_busca": i} for i in ids]


def main():
    print("Fila da perna de busca (§19)\n")

    # --- O caso de 05/08, reproduzido com os nomes reais -------------------
    # 36 termos com serie parada em 20/07, 4 sem serie nenhuma.
    cobertos = ["preto", "azul", "floral", "midi"]          # tem serie, PARADA
    sem_nada = ["reta_wide", "romantico", "saia", "short"]  # nunca coletaram
    aprovados = termos(*(cobertos + sem_nada))
    # Ninguem em dia: a serie de todos parou ha mais de duas semanas.
    fila, modo = fila_por_defasagem(aprovados, em_dia=set(), nunca=set(sem_nada))
    ids = [t["id"] for t in fila]

    checar(modo == "defasagem", "modo vira `defasagem` quando ha atraso")
    checar(len(fila) == 8,
           "OS 4 TERMOS SEM SERIE NAO BLOQUEIAM OS OUTROS 4 "
           "(o defeito de 13/07 e de 20/07)")
    checar(ids[:4] == sorted(sem_nada),
           "termo sem serie nenhuma entra na frente")
    checar(set(ids[4:]) == set(cobertos),
           "termo com serie parada entra logo atras, e nao fica de fora")

    # --- Termo em dia sai da fila ------------------------------------------
    fila, modo = fila_por_defasagem(
        aprovados, em_dia={"preto", "azul"}, nunca=set(sem_nada))
    ids = [t["id"] for t in fila]
    checar("preto" not in ids and "azul" not in ids,
           "termo com serie recente nao gasta orcamento")
    checar("floral" in ids and "midi" in ids,
           "termo com serie parada continua na fila")

    # --- Todo mundo em dia: não consulta uma fonte semanal todo dia ---------
    fila, modo = fila_por_defasagem(
        aprovados, em_dia={t["id"] for t in aprovados}, nunca=set())
    checar(modo == "em_dia" and not fila,
           "com todos em dia, nenhuma consulta e desperdicada")

    # Na quinta, a semana encerrada no domingo já teve três dias para sair.
    checar(corte_de_frescura(date(2026, 8, 13)) == date(2026, 8, 3),
           "quinta cobra a ultima semana ISO fechada")
    # Na segunda, a publicação ainda pode estar atrasada sem ser defeito.
    checar(corte_de_frescura(date(2026, 8, 10)) == date(2026, 7, 27),
           "inicio da semana tolera o atraso de publicacao do Google")

    # --- Determinismo -------------------------------------------------------
    a, _ = fila_por_defasagem(aprovados, set(), set(sem_nada))
    b, _ = fila_por_defasagem(aprovados, set(), set(sem_nada))
    checar([t["id"] for t in a] == [t["id"] for t in b],
           "a fila e deterministica: mesmo estado, mesma ordem")

    # --- Rotacao cobre a taxonomia inteira ---------------------------------
    # O orcamento diario e menor que o numero de grupos. Se a rotacao nao
    # cobrisse tudo, um pedaco da taxonomia ficaria permanentemente parado --
    # que e o mesmo sintoma por outra causa.
    grupos = [["g{}".format(i)] for i in range(10)]
    vistos = set()
    for d in range(4):
        for g in planejar_grupos(grupos, date(2026, 8, 5 + d), limite=3):
            vistos.add(g[0])
    checar(len(vistos) == len(grupos),
           "a rotacao diaria cobre os {} grupos em 4 execucoes".format(len(grupos)))

    print("\n{} verificacoes, {} falha(s).".format(len(checadas), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
