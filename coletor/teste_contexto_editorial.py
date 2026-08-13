#!/usr/bin/env python3
"""Regressões de relevância editorial; não faz rede nem usa segredo."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coletor_editorial import filtrar_contexto_editorial  # noqa: E402


def main():
    categorias = {"camisa", "vestido", "blusa_top"}
    casos = [
        (
            "Vini Jr.: De São Gonçalo ao topo do mundo",
            "O camisa 7 do Real Madrid fala sobre sua carreira no futebol.",
            {"camisa"}, set(),
        ),
        (
            "6 looks com camisa branca para atualizar o clássico",
            "Ideias de moda e styling para vestir a peça.",
            {"camisa"}, {"camisa"},
        ),
        (
            "A camisa que muda a alfaiataria do verão",
            "A peça aparece com gola ampla e manga curta.",
            {"camisa"}, {"camisa"},
        ),
        (
            "Taylor Swift's wedding look",
            "A red rosette dress on the runway.",
            {"vestido"}, {"vestido"},
        ),
        (
            "Empresário veste a camisa da campanha",
            "A expressão marcou o discurso político.",
            {"camisa"}, set(),
        ),
        (
            "Como vestir a camisa da empresa",
            "A metáfora apareceu em uma palestra sobre liderança.",
            {"camisa"}, set(),
        ),
        (
            "Os vestidos escolhidos para o verão",
            "Modelos leves para dias quentes.",
            {"vestido"}, {"vestido"},
        ),
    ]
    falhas = []
    for titulo, resumo, achados, esperado in casos:
        obtido = filtrar_contexto_editorial(titulo, resumo, achados, categorias)
        if obtido != esperado:
            falhas.append("{!r}: {} != {}".format(titulo, obtido, esperado))
    for falha in falhas:
        print("FALHOU:", falha)
    print("{} casos de contexto editorial, {} falhas".format(len(casos), len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
