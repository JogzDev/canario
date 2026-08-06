"""A semana da busca tem que ser a MESMA semana do editorial.

POR QUE ESTE ARQUIVO EXISTE
===========================

Em 05/08 medi que a perna de busca estava 16 dias atras do editorial e conclui
que o Google tinha um atraso estrutural. Estava errado: seis daqueles dias eram
nossos.

O Trends marca cada semana pelo DOMINGO em que ela comeca. O coletor fazia
`quando - timedelta(days=quando.weekday())` para "normalizar para segunda ISO",
e `weekday()` de domingo e 6 -- entao a linha subtraia seis dias e jogava o
ponto para a segunda ANTERIOR, fora do periodo medido. A semana de 26/07 a
01/08 virava "semana de 20/07".

O atraso aparente era o menor dos problemas. O grave: o editorial usa
`date_trunc('week')` do Postgres, que da segunda ISO de verdade. Entao o rotulo
"semana de 20/07" significava 20-26/07 numa perna e 26/07-01/08 na outra. Mesmo
nome, seis dias de deslocamento, UM dia em comum. A §22 so afirma direcao
quando as duas pernas concordam na mesma semana -- e vinha comparando semanas
quase disjuntas, em silencio, em toda leitura do app.

Esse bug nao levanta excecao, nao aparece em log e nao quebra teste nenhum: o
numero existe e parece razoavel, so mede outra coisa. Por isso o teste central
aqui nao confere um valor, e sim que AS DUAS PERNAS CONCORDAM -- comparando com
a funcao que o coletor editorial realmente usa, e nao com uma copia dela.

Rodar: python3 coletor/teste_semana_da_busca.py
"""

import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from coletor_trends import semana_iso, ultima_semana_fechada  # noqa: E402
from coletor_editorial import semana_de  # noqa: E402

falhas = []


def checar(condicao, descricao):
    print("  {} {}".format("ok  " if condicao else "FALHOU", descricao))
    if not condicao:
        falhas.append(descricao)


def main():
    print("A semana da busca e a semana do editorial\n")

    # 1. O bug, direto. O Trends marca esta semana com o domingo 26/07; a
    #    versao antiga gravava 20/07 -- seis dias ANTES do periodo medido.
    checar(semana_iso(date(2026, 7, 26)) == date(2026, 7, 27),
           "domingo 26/07 vira semana de 27/07 (e nao 20/07)")
    checar(semana_iso(date(2026, 7, 26)) > date(2026, 7, 26),
           "o ponto anda para FRENTE, nunca para tras")

    # 2. O teste que importa: as duas pernas, o mesmo periodo, a mesma semana.
    #    Compara com a funcao REAL do coletor editorial, e nao com uma copia --
    #    se um dos dois lados mudar de convencao, isto acusa.
    #
    #    A semana do Google vai de domingo S a sabado S+6. Os seis dias dela
    #    que caem de segunda em diante tem que pousar na semana ISO que a busca
    #    declara. Sobra o proprio domingo, que e a imprecisao inerente.
    desacordos = []
    for n in range(400):
        domingo = date(2025, 6, 1) + timedelta(days=n)
        if domingo.weekday() != 6:
            continue
        rotulo = semana_iso(domingo)
        for d in range(1, 7):
            if semana_de(domingo + timedelta(days=d)) != rotulo:
                desacordos.append((domingo, d))
    checar(not desacordos,
           "os seis dias uteis de cada semana do Google caem na semana ISO "
           "que a busca declara"
           + ("" if not desacordos else " (falhou em {})".format(desacordos[:3])))

    # 3. Todo rotulo e segunda-feira. Domingo entrando aqui foi exatamente o
    #    que passou despercebido antes.
    checar(all(semana_iso(date(2026, 1, 4) + timedelta(days=7 * k)).weekday() == 0
               for k in range(60)),
           "todo rotulo cai numa segunda-feira")

    # 4. Ponto que ja venha numa segunda nao pode ser empurrado uma semana.
    checar(semana_iso(date(2026, 7, 27)) == date(2026, 7, 27),
           "ponto que ja e segunda fica onde esta")

    # 5. O ajuste e de no maximo um dia. Se algum dia passar disso, alguem
    #    trocou o sentido do arredondamento de novo.
    checar(all((semana_iso(date(2026, 3, 1) + timedelta(days=n))
                - (date(2026, 3, 1) + timedelta(days=n))).days <= 1
               for n in range(0, 364, 7)),
           "o ajuste nunca passa de um dia")

    # 6. A regua de "em dia" aponta para a ultima semana JA FECHADA.
    #    Quarta 05/08: a semana corrente (03/08) ainda corre; a ultima fechada
    #    e 27/07.
    checar(ultima_semana_fechada(date(2026, 8, 5)) == date(2026, 7, 27),
           "numa quarta, a ultima semana fechada e a de sete dias atras")
    checar(ultima_semana_fechada(date(2026, 8, 3)) == date(2026, 7, 27),
           "na propria segunda, a semana que comeca hoje ainda nao fechou")
    checar(ultima_semana_fechada(date(2026, 8, 9)) == date(2026, 7, 27),
           "no domingo, a semana corrente ainda nao fechou")
    checar(ultima_semana_fechada(date(2026, 8, 10)) == date(2026, 8, 3),
           "na segunda seguinte, a semana anterior ja conta")
    checar(all(ultima_semana_fechada(date(2026, 8, 3) + timedelta(days=i)
                                     ).weekday() == 0 for i in range(30)),
           "a regua sempre cai numa segunda-feira")

    print()
    if falhas:
        print("{} falha(s).".format(len(falhas)))
        return 1
    print("Busca e editorial usam o mesmo calendario; a §22 compara semanas "
          "iguais.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
