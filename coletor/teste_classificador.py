"""Testes do classificador de categorias (B5).

Existe por causa de um bug real: o casamento por substring excluia "casaco"
(contem "casa") e "botao" (contem "bota") -- justamente categorias centrais da
taxonomia. Os casos abaixo sao a cerca para isso nao voltar.

Rodar: python3 coletor/teste_classificador.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapa_categorias import classificar  # noqa: E402

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


def main():
    falhas = []
    for caminho, esperado in CASOS:
        obtido = classificar(caminho)[0]
        if obtido != esperado:
            falhas.append((caminho, obtido, esperado))

    for caminho, obtido, esperado in falhas:
        print("FALHOU: {!r} -> {} (esperado {})".format(caminho, obtido, esperado))

    print("{} casos, {} falhas".format(len(CASOS), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
