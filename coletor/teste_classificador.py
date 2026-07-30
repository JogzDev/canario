"""Testes do classificador de categorias (B5).

Existe por causa de um bug real: o casamento por substring excluia "casaco"
(contem "casa") e "botao" (contem "bota") -- justamente categorias centrais da
taxonomia. Os casos abaixo sao a cerca para isso nao voltar.

Rodar: python3 coletor/teste_classificador.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapa_categorias import (classificar, classificar_populacao,  # noqa: E402
                             loja_so_feminina)

CASOS = [
    # As armadilhas de substring que motivaram o teste.
    ("Casacos Com Desconto", "sim"),   # "casa" nao pode derrubar "casacos"
    ("Casaco e Jaqueta", "sim"),
    # "Bazar | Casacos" era `sim` ate 29/07: passou a `nao` quando "bazar"
    # entrou nas exclusoes junto de sale e outlet. Nao e regressao de
    # substring -- e balde de merchandising, e a exclusao vence.
    ("Bazar | Casacos Com Desconto", "nao"),
    ("BLUSAS DE BOTAO", "sim"),
    ("Casa e Decoracao", "nao"),
    ("Botas", "nao"),
    # Vestuario feminino: entra.
    ("Vestidos", "sim"),
    ("Saias", "sim"),
    ("Alfaiataria Feminina", "sim"),
    ("Blusas e Camisas", "sim"),
    # Outro publico.
    ("Moda Masculina", "nao"),
    ("Roupas Infantis", "nao"),
    ("Moda Infantil", "nao"),
    # Nao e vestuario.
    ("Bolsas e Acessorios", "nao"),
    ("Oculos de Sol", "nao"),
    # Outro segmento.
    ("Biquinis Tops", "nao"),
    ("Moda Praia", "nao"),
    # Nao e categoria de produto.
    ("Blusas em Sale", "nao"),
    ("Novidades da Semana", "nao"),
]


# Populacao x recorte comercial. Nasceu de um erro real: excluir "Bazar"
# derrubou o Dress To de 4540 para 326 produtos, porque 6852 dos 7178 itens
# dele vivem no Bazar. Vitrine e a mesma roupa noutro lugar; populacao e gente
# ou produto diferente.
CASOS_POPULACAO = [
    ("Bazar", "sim"),
    ("Sale", "sim"),
    ("Novidades da Semana", "sim"),
    ("Promocoes", "sim"),
    ("Calcados", "nao"),
    ("Moda Intima", "nao"),
    ("Moda Praia", "nao"),
    ("Moda Masculina", "nao"),
    ("Roupas Infantis", "nao"),
    ("Vestidos", "sim"),
]

CASOS_LOJA = [
    (["Vestidos", "Saias", "Bazar", "Blusas"], True),          # Cantao
    (["Moda Feminina", "Moda Masculina", "Moda Infantil"], False),  # C&A
    (["dress to", "Bazar"], True),                              # Dress To
]


def main():
    falhas = []
    for caminho, esperado in CASOS:
        obtido = classificar(caminho)[0]
        if obtido != esperado:
            falhas.append((caminho, obtido, esperado))

    for caminho, esperado in CASOS_POPULACAO:
        obtido = classificar_populacao(caminho)[0]
        if obtido != esperado:
            falhas.append(("populacao: " + caminho, obtido, esperado))

    for deps, esperado in CASOS_LOJA:
        obtido = loja_so_feminina(deps)
        if obtido != esperado:
            falhas.append(("loja_so_feminina " + str(deps), obtido, esperado))

    for caminho, obtido, esperado in falhas:
        print("FALHOU: {!r} -> {} (esperado {})".format(caminho, obtido, esperado))

    print("{} casos, {} falhas".format(
        len(CASOS) + len(CASOS_POPULACAO) + len(CASOS_LOJA), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
