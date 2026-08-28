"""A paleta oficial da marca esta no codigo, e com os valores certos.

POR QUE ESTE ARQUIVO EXISTE
===========================

A paleta do DataDrobe sao tres cores, definidas pelo JP e pela Bianca:

    #BBE5ED  ceu        fundo das telas do armario
    #374A67  azulMarca  azul de identidade
    #0A0B1A  noturno    fundo do territorio de mercado

Em 27/08/2026 fui conferir e achei o que este portao existe para impedir: as
duas primeiras estavam no codigo com o valor exato -- por acaso, porque
ninguem tinha comparado --, e a terceira **nunca tinha entrado**. Pior: o nome
`noite` ja estava ocupado por OUTRO quase-preto, `#0E1116`, que serve de tinta
sobre o ceu. Duas cores parecidas com nomes parecidos e propositos opostos e
exatamente como uma vira a outra num refactor distraido.

Cor nao quebra teste. Um `#0A0B1A` que vira `#0E1116` compila, roda, passa em
tudo e so aparece quando alguem poe as duas telas lado a lado -- ou quando o
desenho volta do Figma e nao bate. Por isso a conferencia vem para ca, onde o
CI a faz a cada push.

O QUE ELE CONFERE
=================

Que cada cor oficial aparece em `Tokens.swift` como triplo RGB decimal, no
token de nome certo. E que `noite` continua sendo `#0E1116` -- ou seja, que
ninguem "corrigiu" a tinta para a cor de fundo achando que eram a mesma coisa.
"""

import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
TOKENS = RAIZ / "app" / "Canario" / "Design" / "Tokens.swift"

# token -> (hex oficial, rgb esperado)
OFICIAIS = {
    "ceu": ("#BBE5ED", (187, 229, 237)),
    "azulMarca": ("#374A67", (55, 74, 103)),
    "noturno": ("#0A0B1A", (10, 11, 26)),
}

# A tinta sobre o ceu, que NAO e a cor de fundo e nao pode virar uma.
TINTA_SOBRE_CEU = ("noite", "#0E1116", (14, 17, 22))


def rgb_do_token(fonte, token):
    """Primeiro triplo de numeros que aparece na linha do token."""
    padrao = re.compile(
        r"static let {}\s*=.*?\((\d+),\s*(\d+),\s*(\d+)\)".format(re.escape(token)),
        re.DOTALL)
    achado = padrao.search(fonte)
    return tuple(int(g) for g in achado.groups()) if achado else None


def main():
    if not TOKENS.exists():
        print("FALHOU: Tokens.swift nao encontrado")
        return 1

    fonte = TOKENS.read_text(encoding="utf-8")
    falhas = []

    for token, (hexa, esperado) in OFICIAIS.items():
        obtido = rgb_do_token(fonte, token)
        if obtido is None:
            falhas.append("`{}` ({}) nao existe em Tokens.swift".format(token, hexa))
        elif obtido != esperado:
            falhas.append("`{}` deveria ser {} {} e esta {}".format(
                token, hexa, esperado, obtido))

    nome, hexa, esperado = TINTA_SOBRE_CEU
    obtido = rgb_do_token(fonte, nome)
    if obtido != esperado:
        falhas.append(
            "`{}` e a TINTA sobre o ceu ({} {}), nao um fundo. "
            "Esta {} -- alguem pode te-la confundido com `noturno`.".format(
                nome, hexa, esperado, obtido))

    if falhas:
        print("FALHOU: a paleta oficial nao bate com o codigo.")
        for f in falhas:
            print("  - " + f)
        return 1

    print("Paleta oficial: ceu, azulMarca e noturno conferem; "
          "noite continua sendo tinta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
