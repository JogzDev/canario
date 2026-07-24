"""Testes do matcher compartilhado.

A regressao obrigatoria (item 4 das instrucoes de 24/07): `reta` e substring de
`preta`; nenhuma peca preta pode casar com a silhueta reta. Se este arquivo
passar, o bug de substring nao esta em nenhum dos tres matchers, porque os tres
usam este modulo.

Rodar: python3 coletor/teste_matcher.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import compilar, casa_algum, termos_que_casam  # noqa: E402


def um(padrao, texto):
    return casa_algum(texto, [compilar(padrao)])


# (padrao, texto, deve_casar)
CASOS = [
    # A REGRESSAO CRITICA: reta nao pode casar preta.
    ("reta", "vestido preta", False),
    ("reta", "vestido preto", False),
    ("reta", "saia reta", True),
    ("reta", "calca reta wide", True),
    ("preto", "vestido preto", True),
    ("preto", "vestido preta", False),   # preto casa preto, nao preta (rotulo distinto)
    # Substring dentro de palavra: nunca casa.
    ("casa", "casaco de linho", False),
    ("casa", "casa e decoracao", True),
    ("bota", "blusa de botao", False),
    ("bota", "botas de couro", False),   # botas != bota (exato)
    ("liso", "vestido liso", True),
    ("liso", "vestido alisado", False),
    ("midi", "vestido midi", True),
    ("mini", "minissaia", False),        # mini exato nao casa minissaia
    # Prefixo livre declarado com *.
    ("masculin*", "moda masculina", True),
    ("masculin*", "moda masculino", True),
    ("infant*", "roupa infantil", True),
    ("infant*", "roupa infantis", True),
    # Frases: sequencia de palavras com fronteira.
    ("wide leg", "calca wide leg preta", True),
    ("wide leg", "calca widescreen leg", False),
    ("animal print", "vestido animal print", True),
    ("manga bufante", "blusa de manga bufante", True),
    # Acentos e caixa: normalizados dos dois lados.
    ("floral", "Vestido FLORAL", True),
    ("trico", "TRICÔ artesanal", True),
]

# Matching titulo->termo com contagem unica (§11): varias palavras do mesmo
# termo contam uma vez so.
TERMOS = {
    "floral": [compilar("floral"), compilar("florido"), compilar("flores")],
    "preto": [compilar("preto"), compilar("preta")],
    "reta_wide": [compilar("reta"), compilar("wide leg"), compilar("oversized")],
}
CASOS_TERMO = [
    ("Vestido floral florido com flores", {"floral"}),          # 3 palavras, 1 termo
    ("Vestido preto wide leg", {"preto", "reta_wide"}),
    ("Vestido preto reto", {"preto"}),                          # "reto" != "reta"
    ("Blusa lisa branca", set()),
]


def main():
    falhas = []
    for padrao, texto, esperado in CASOS:
        if um(padrao, texto) != esperado:
            falhas.append("compilar({!r}) em {!r}: esperava {}".format(
                padrao, texto, esperado))

    for texto, esperado in CASOS_TERMO:
        obtido = termos_que_casam(texto, TERMOS)
        if obtido != esperado:
            falhas.append("termos_que_casam({!r}): {} != {}".format(
                texto, obtido, esperado))

    for f in falhas:
        print("FALHOU:", f)
    print("{} casos, {} falhas".format(len(CASOS) + len(CASOS_TERMO), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
