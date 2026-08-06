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

from coletor_trends import semanas_iso, ultima_semana_fechada  # noqa: E402
from coletor_editorial import semana_de  # noqa: E402

falhas = []


def checar(condicao, descricao):
    print("  {} {}".format("ok  " if condicao else "FALHOU", descricao))
    if not condicao:
        falhas.append(descricao)


def dias(inicio, quantos, valor=10.0):
    return [(inicio + timedelta(days=i), valor) for i in range(quantos)]


def main():
    print("A semana da busca e a semana do editorial\n")

    # 1. O bug de 05/08, direto. O Trends marcava esta semana como domingo
    #    26/07; a versao antiga gravava 20/07. O periodo medido comeca em
    #    27/07 (segunda) e a semana ISO dele e 27/07.
    semana_27 = semanas_iso(dias(date(2026, 7, 27), 7))
    checar(len(semana_27) == 1 and semana_27[0][0] == date(2026, 7, 27),
           "semana de 27/07 a 02/08 e rotulada 27/07 (e nao 20/07)")

    # 2. O teste que importa: as duas pernas, o mesmo dia, a mesma semana.
    #    Compara com a funcao REAL do coletor editorial, nao com uma copia --
    #    se um dos dois lados mudar de convencao, isto acusa.
    desacordos = []
    for n in range(400):
        dia = date(2025, 6, 1) + timedelta(days=n)
        semana_da_busca = semanas_iso(dias(dia - timedelta(days=dia.weekday()), 7))
        if not semana_da_busca:
            desacordos.append(dia)
            continue
        if semana_da_busca[0][0] != semana_de(dia):
            desacordos.append(dia)
    checar(not desacordos,
           "em 400 dias seguidos, busca e editorial caem na mesma semana"
           + ("" if not desacordos else " (falhou em {})".format(desacordos[:3])))

    # 3. Toda semana devolvida e segunda-feira. Domingo entrando aqui foi
    #    exatamente o que passou despercebido antes.
    muitas = semanas_iso(dias(date(2026, 1, 5), 210))
    checar(all(s.weekday() == 0 for s, _ in muitas),
           "toda semana devolvida cai numa segunda-feira")

    # 4. Semana pela metade nao entra: a media de 3 dias nao e comparavel com a
    #    media de 7 e entraria na janela do z como se fosse.
    checar(semanas_iso(dias(date(2026, 7, 27), 3)) == [],
           "semana com 3 dias nao vira ponto")
    checar(len(semanas_iso(dias(date(2026, 7, 27), 10))) == 1,
           "10 dias dao UMA semana fechada, e nao duas")

    # 5. A media e a media dos sete dias.
    ponto = semanas_iso([(date(2026, 7, 27) + timedelta(days=i), float(i))
                         for i in range(7)])
    checar(ponto and abs(ponto[0][1] - 3.0) < 1e-9,
           "o valor da semana e a media dos sete dias")

    # 6. Ordem crescente: o calculo do z le a serie na ordem em que ela vem.
    fora_de_ordem = dias(date(2026, 3, 2), 7) + dias(date(2026, 2, 23), 7)
    resultado = semanas_iso(fora_de_ordem)
    checar([s for s, _ in resultado] == sorted(s for s, _ in resultado),
           "a serie sai ordenada mesmo com a entrada embaralhada")

    # 7. A regua de "em dia" aponta para a ultima semana JA FECHADA.
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
