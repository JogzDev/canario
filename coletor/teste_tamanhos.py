"""Teste do normalizador de tamanho (§24).

Todos os casos vieram do painel real, medidos em 01/08/2026. O teste existe
porque este modulo e a peca que decide se a curva de tamanhos compara coisas
comparaveis -- e porque um erro aqui nao aparece como erro, aparece como uma
curva plausivel e errada, que e o pior tipo de defeito que este projeto pode ter.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tamanhos import ESCADA_PADRAO, faixa, grade_normalizada, normalizar  # noqa: E402

falhas = []


def checa(descricao, obtido, esperado):
    if obtido != esperado:
        falhas.append("{}\n   esperado: {!r}\n   obtido:   {!r}".format(
            descricao, esperado, obtido))


# ---------------------------------------------------------------------------
# Letras e numeros, com o lixo que o catalogo tem de verdade
# ---------------------------------------------------------------------------

checa("minuscula e espaco", normalizar(" pp ")[:2], ("letra", "PP"))
checa("numero com zero a esquerda (Hering)", normalizar("040")[:2], ("br_numerico", "40"))
checa("numero simples", normalizar("38")[:2], ("br_numerico", "38"))

# PatBo escreve US e BR juntos. O lado BR e o que o painel entende.
checa("US/BR numerico (PatBo)", normalizar("4/36")[:2], ("br_numerico", "36"))
checa("US/BR em letra (PatBo)", normalizar("L/G")[:2], ("letra", "G"))
checa("US/BR em letra, extremo", normalizar("XS/PP")[:2], ("letra", "PP"))
checa("US/BR com letra repetida", normalizar("M/M")[:2], ("letra", "M"))

# ---------------------------------------------------------------------------
# O que NAO e tamanho de roupa, e por que cada um apareceu
# ---------------------------------------------------------------------------

# Bug do coletor Shopify: pegava `option1` as cegas e na Amaro a primeira opcao
# e cor. 335 produtos entraram com a grade cheia de nome de cor.
checa("cor nao e tamanho (bug da Amaro)", normalizar("PRETO")[0], None)
checa("cor composta", normalizar("Preto Colorido")[0], None)

# Numeracao de calcado da PatBo. Roupa e calcado nao dividem escada.
checa("calcado fica de fora", normalizar("34BR/36EU")[0], None)

# `000` existe no catalogo e `lstrip("0")` devolve string vazia.
checa("tamanho so de zeros", normalizar("000")[0], None)
checa("zero puro", normalizar("0")[0], None)

# A escada plus size da C&A (GG1..GG6, X1, XGGG) e propria e nao encaixa na
# ordem canonica. Fica de fora em vez de ser encaixada a forca.
checa("plus size da C&A", normalizar("GG1")[0], None)
checa("plus size, outra forma", normalizar("XGGG")[0], None)

checa("tamanho unico", normalizar("U")[0], None)
checa("tamanho unico por extenso", normalizar("UNICO")[0], None)
checa("vazio", normalizar("")[0], None)
checa("nulo", normalizar(None)[0], None)

# Fora da faixa de vestuario adulto.
checa("infantil fica de fora", normalizar("12")[0], None)
checa("numero alto demais", normalizar("70")[0], None)
checa("limite de baixo entra", normalizar("30")[0], "br_numerico")
checa("limite de cima entra", normalizar("69")[0], "br_numerico")

# ---------------------------------------------------------------------------
# A ORDEM, que e a unica coisa que a tabela de letras promete
# ---------------------------------------------------------------------------

ordem = lambda r: normalizar(r)[2]   # noqa: E731

for menor, maior in [("XPP", "XP"), ("XP", "PP"), ("PP", "P"), ("P", "M"),
                     ("M", "G"), ("G", "GG"), ("GG", "XG"), ("XG", "XGG")]:
    if not ordem(menor) < ordem(maior):
        falhas.append("ordem quebrada: {} deveria vir antes de {}".format(menor, maior))

# ---------------------------------------------------------------------------
# O caso que decidiu o metodo: o MESMO rotulo em duas escadas diferentes
# ---------------------------------------------------------------------------

# Hering nao tem PP nem GG: XP . P . M . G . XG
hering = dict((r, (p, f)) for r, s, p, f in grade_normalizada(["XP", "P", "M", "G", "XG"]))
checa("Hering: XP e o menor da grade dela", hering["XP"][0], 0.0)
checa("Hering: XG e o maior da grade dela", hering["XG"][0], 1.0)
checa("Hering: XP cai em menores", hering["XP"][1], "menores")
checa("Hering: XG cai em maiores", hering["XG"][1], "maiores")
checa("Hering: M cai no meio", hering["M"][1], "meio")

# Zinzane tem os dois, e XG fica ACIMA do GG: PP . P . M . G . GG . XG . XGG
zinzane = dict((r, (p, f)) for r, s, p, f in
               grade_normalizada(["PP", "P", "M", "G", "GG", "XG", "XGG"]))
checa("Zinzane: PP e o menor", zinzane["PP"][0], 0.0)
checa("Zinzane: XGG e o maior", zinzane["XGG"][0], 1.0)

# ESTA e a assercao que justifica o metodo inteiro. O mesmo rotulo `XG` ocupa
# posicoes diferentes nas duas marcas, e nenhuma tabela global acertaria as
# duas ao mesmo tempo.
if hering["XG"][0] == zinzane["XG"][0]:
    falhas.append(
        "o metodo perdeu o sentido: `XG` deveria ocupar posicoes DIFERENTES na "
        "Hering (onde e o maior) e na Zinzane (onde ha dois degraus acima). "
        "Hering={} Zinzane={}".format(hering["XG"][0], zinzane["XG"][0]))

# ---------------------------------------------------------------------------
# A grade de cinco degraus tem de recortar exatamente o que a §24 pede
# ---------------------------------------------------------------------------

padrao = dict((r, f) for r, s, p, f in grade_normalizada(list(ESCADA_PADRAO)))
checa("§24: PP em menores", padrao["PP"], "menores")
checa("§24: P em menores", padrao["P"], "menores")
checa("§24: M no meio", padrao["M"], "meio")
checa("§24: G em maiores", padrao["G"], "maiores")
checa("§24: GG em maiores", padrao["GG"], "maiores")

# ---------------------------------------------------------------------------
# Letra e numero na mesma peca sao DUAS escadas, nao uma
# ---------------------------------------------------------------------------

mista = grade_normalizada(["P", "M", "G", "38", "40", "42"])
sistemas = set(s for r, s, p, f in mista)
checa("duas escadas na mesma peca", sistemas, {"letra", "br_numerico"})
letras = [r for r, s, p, f in mista if s == "letra" and f == "menores"]
checa("a escada de letra nao herda os numeros", letras, ["P"])

# ---------------------------------------------------------------------------
# Faixas
# ---------------------------------------------------------------------------

checa("faixa: extremo de baixo", faixa(0.0), "menores")
checa("faixa: extremo de cima", faixa(1.0), "maiores")
checa("faixa: centro", faixa(0.5), "meio")
checa("faixa: sem posicao", faixa(None), None)

# Grade de um degrau so nao tem curva; posicao 0 e menores, e a condicao de
# 3+ degraus no SQL e que impede isso de virar leitura.
um_so = grade_normalizada(["U", "M"])
checa("grade de um degrau", [f for r, s, p, f in um_so], ["menores"])


if falhas:
    print("\n\n".join(falhas))
    print("\n{} falhas".format(len(falhas)))
    sys.exit(1)

print("Normalizador de tamanhos: todos os casos passaram.")
print("Escada padrao (unica em que a tela NOMEIA tamanho): {}".format(
    " . ".join(ESCADA_PADRAO)))
