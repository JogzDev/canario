"""Normalizacao de rotulo de tamanho (§24).

Espelha `ordem_do_tamanho()` do Postgres. Existe em Python para ser TESTAVEL:
a funcao SQL e a peca que decide se a curva de tamanhos compara coisas
comparaveis, e ela nao tem como rodar no CI sem banco.

===========================================================================
O PROBLEMA QUE DECIDIU O METODO
===========================================================================

Cada marca escreve tamanho na sua propria escada, e o MESMO ROTULO significa
degraus diferentes. Medido no painel em 01/08/2026:

    Hering : XP . P . M . G . XG . XXG      (nao existe PP nem GG)
    Zinzane: PP . P . M . G . GG . XG . XGG (XG fica ACIMA do GG)

Em Hering, `XG` e o maior tamanho corrente, o equivalente do GG das outras.
Em Zinzane, `XG` e um degrau ALEM do GG. Uma tabela global rotulo -> tamanho
seria demonstravelmente errada.

Entao nada aqui equivale tamanho entre marcas. A `ordem` serve APENAS para
ordenar os rotulos DENTRO da grade de um mesmo produto; quem transforma isso em
faixa (menores/meio/maiores) e a posicao relativa naquela grade.
"""

import re

# A ordem canonica. So precisa estar certa como ORDEM. Que XG (8) venha depois
# de GG (7) e verdade na Zinzane e inofensivo na Hering, que nao tem GG.
LETRAS = {
    "XPP": 1, "XP": 2, "PP": 3, "P": 4, "M": 5,
    "G": 6, "GG": 7, "XG": 8, "XGG": 9, "XXG": 10, "EXG": 11,
}

# A escada que quase toda marca brasileira usa igual. So nela e possivel NOMEAR
# o tamanho na tela sem misturar significado entre marcas.
ESCADA_PADRAO = ("PP", "P", "M", "G", "GG")

# Faixa numerica brasileira de vestuario. Abaixo de 30 e infantil; acima de 69
# nao e tamanho de roupa (aparecem codigos de outra coisa).
BR_MIN, BR_MAX = 30, 69

_SO_DIGITOS = re.compile(r"^0*\d+$")
_COMBINADO = re.compile(r"^[A-Z0-9]+/[A-Z0-9]+$")


def normalizar(bruto):
    """Devolve (sistema, rotulo, ordem), ou (None, rotulo, None) se nao for tamanho.

    Casos reais que este codigo tem de acertar, todos vistos no painel:

    >>> normalizar("pp")[:2]
    ('letra', 'PP')
    >>> normalizar("040")[:2]
    ('br_numerico', '40')
    >>> normalizar("4/36")[:2]          # PatBo escreve US/BR junto
    ('br_numerico', '36')
    >>> normalizar("L/G")[:2]           # idem, em letra
    ('letra', 'G')
    >>> normalizar("34BR/36EU")[0]      # calcado, nao e roupa
    >>> normalizar("PRETO")[0]          # bug do coletor Shopify na Amaro
    >>> normalizar("000")[0]            # existe no catalogo e quebrava o cast
    >>> normalizar("GG1")[0]            # escada plus size da C&A, propria
    """
    t = (bruto or "").strip().upper()
    if not t:
        return (None, "", None)

    # "XS/PP" e "4/36" trazem US e BR juntos; o lado BR e o segundo. "34BR/36EU"
    # e numeracao de calcado e fica de fora inteira.
    if _COMBINADO.match(t) and "BR" not in t and "EU" not in t:
        t = t.split("/")[1]

    if t in LETRAS:
        return ("letra", t, LETRAS[t])

    if _SO_DIGITOS.match(t):
        # `ltrim("000", "0")` devolve string vazia, que estoura no cast. E um
        # tamanho sem digito nenhum nao e tamanho.
        digitos = t.lstrip("0")
        if not digitos:
            return (None, t, None)
        n = int(digitos)
        if BR_MIN <= n <= BR_MAX:
            return ("br_numerico", digitos, n)
        return (None, digitos, None)

    return (None, t, None)


def faixa(posicao):
    """Posicao relativa na grade (0 = menor oferecido, 1 = maior) -> faixa.

    Numa grade de cinco degraus isto recorta exatamente o que a §24 pede:
    menores = PP/P, meio = M, maiores = G/GG. E funciona igual numa grade de
    outra escada, sem afirmar que XP "e" PP.
    """
    if posicao is None:
        return None
    if posicao <= 1.0 / 3:
        return "menores"
    if posicao >= 2.0 / 3:
        return "maiores"
    return "meio"


def grade_normalizada(rotulos):
    """Ordena uma grade e devolve [(rotulo, sistema, posicao, faixa)].

    Produto que mistura letra e numero entra com uma escada por sistema: sao
    duas grades diferentes na mesma peca, e misturar as duas inventaria degraus.
    """
    por_sistema = {}
    for bruto in rotulos:
        sistema, rotulo, ordem = normalizar(bruto)
        if sistema is None or ordem is None:
            continue
        por_sistema.setdefault(sistema, {})[rotulo] = ordem

    saida = []
    for sistema, mapa in por_sistema.items():
        ordenados = sorted(mapa.items(), key=lambda kv: kv[1])
        degraus = len(ordenados)
        for i, (rotulo, _) in enumerate(ordenados):
            posicao = (i / float(degraus - 1)) if degraus > 1 else 0.0
            saida.append((rotulo, sistema, posicao, faixa(posicao)))
    return saida
