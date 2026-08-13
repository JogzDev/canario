#!/usr/bin/env python3
"""Regressões de relevância editorial; não faz rede nem usa segredo."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coletor_editorial import filtrar_contexto_editorial  # noqa: E402


def main():
    categorias = {
        "camisa", "vestido", "blusa_top", "calca", "short", "saia",
        "casaco_jaqueta", "macacao",
    }
    # (título, resumo, achados no artigo, achados no título, esperado). São
    # exemplos reais ou mínimos derivados dos falsos positivos observados no
    # painel em 10/08; a regressão protege precisão sem usar rede.
    casos = [
        (
            "Vini Jr.: De São Gonçalo ao topo do mundo",
            "O camisa 7 do Real Madrid fala sobre sua carreira no futebol.",
            {"camisa"}, set(), set(),
        ),
        (
            "6 looks com camisa branca para atualizar o clássico",
            "Ideias de moda e styling para vestir a peça.",
            {"camisa"}, {"camisa"}, {"camisa"},
        ),
        (
            "A camisa que muda a alfaiataria do verão",
            "A peça aparece com gola ampla e manga curta.",
            {"camisa"}, {"camisa"}, {"camisa"},
        ),
        (
            "Taylor Swift's wedding look",
            "A red rosette dress on the runway.",
            {"vestido"}, set(), {"vestido"},
        ),
        (
            "Empresário veste a camisa da campanha",
            "A expressão marcou o discurso político.",
            {"camisa"}, {"camisa"}, set(),
        ),
        (
            "Como vestir a camisa da empresa",
            "A metáfora apareceu em uma palestra sobre liderança.",
            {"camisa"}, {"camisa"}, set(),
        ),
        (
            "Os vestidos escolhidos para o verão",
            "Modelos leves para dias quentes.",
            {"vestido"}, {"vestido"}, {"vestido"},
        ),
        (
            "Anne Hathaway exibe avanço da terceira gestação durante evento",
            "A atriz usou um longo vestido azul na chegada.",
            {"vestido", "longo", "azul"}, set(), set(),
        ),
        (
            "Verão lá fora: os destinos das tops em 2026",
            "Modelos viajaram com blusas e casacos.",
            {"blusa_top", "casaco_jaqueta"}, {"blusa_top"}, set(),
        ),
        (
            "Por dentro da coleção Florestania, da Animale",
            "A coleção combina calças, casacos e tons terrosos.",
            {"calca", "casaco_jaqueta", "terrosos"}, set(),
            {"calca", "casaco_jaqueta", "terrosos"},
        ),
        (
            "O casaco de tweed é uma alternativa ao blazer",
            "Cinco jeitos de usar a peça.",
            {"casaco_jaqueta", "alfaiataria"}, {"casaco_jaqueta"},
            {"casaco_jaqueta", "alfaiataria"},
        ),
        (
            "Dua Lipa curte passeio de bicicleta em Nova York",
            "A cantora usou camisa, short e jaqueta vermelha.",
            {"camisa", "short", "casaco_jaqueta", "vermelho_rosa"}, set(), set(),
        ),
        (
            "Mary-Kate and Ashley Are Backing This Shirt Trend for Fall",
            "The striped shirt is styled with trousers.",
            {"camisa", "listra", "calca"}, {"camisa"},
            {"camisa", "listra", "calca"},
        ),
        (
            "5 Copenhagen Fashion Week Outfits to Recreate Now",
            "Dresses, skirts and jackets lead the edit.",
            {"vestido", "saia", "casaco_jaqueta"}, set(),
            {"vestido", "saia", "casaco_jaqueta"},
        ),
        (
            "UFC Lost $30 Million From White House Event",
            "A fighter wore a jumpsuit before the event.",
            {"macacao"}, set(), set(),
        ),
    ]
    falhas = []
    for titulo, resumo, achados, achados_titulo, esperado in casos:
        obtido = filtrar_contexto_editorial(
            titulo, resumo, achados, categorias,
            achados_no_titulo=achados_titulo)
        if obtido != esperado:
            falhas.append("{!r}: {} != {}".format(titulo, obtido, esperado))
    for falha in falhas:
        print("FALHOU:", falha)
    print("{} casos de contexto editorial, {} falhas".format(len(casos), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
