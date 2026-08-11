#!/usr/bin/env python3
"""Cria um HTML cego apenas com as amostras em que dois revisores divergiram."""

import argparse
import json
from pathlib import Path
import re

from consolidar_revisao_luna import (
    carregar_revisao,
    comparar_revisoes,
    ids_para_adjudicar,
)


PADRAO_AMOSTRAS = re.compile(r"const samples = (\[.*?\]);\n")


def preparar(revisoes, html_origem, saida):
    comparacao = comparar_revisoes(revisoes)
    divergentes = ids_para_adjudicar(comparacao)
    html = html_origem.read_text(encoding="utf-8")
    achado = PADRAO_AMOSTRAS.search(html)
    if not achado:
        raise ValueError("HTML de origem sem amostras embutidas.")
    amostras = json.loads(achado.group(1))
    selecionadas = [
        amostra for amostra in amostras
        if amostra.get("sample_id") in divergentes
    ]
    if {a.get("sample_id") for a in selecionadas} != divergentes:
        raise ValueError("HTML nao contem todas as amostras divergentes.")

    json_amostras = json.dumps(
        selecionadas, ensure_ascii=False, separators=(",", ":"))
    html = html[:achado.start(1)] + json_amostras + html[achado.end(1):]
    html = html.replace(
        "Canário — revisão cega Luna", "Canário — adjudicação cega Luna")
    html = html.replace(
        "Revisão cega — categoria e cor",
        "Adjudicação cega — categoria e cor")
    html = html.replace(
        "Não abra <code>predicoes-recuperadas.csv</code> antes de exportar seus rótulos. Clique na imagem para ampliar.",
        "Revise somente os itens em que Fadul e Bianca divergiram. As respostas deles, o catálogo e o Luna continuam ocultos. Clique na imagem para ampliar.")
    html = html.replace(
        "canario-luna-last-reviewer",
        "canario-luna-adjudicacao-last-reviewer")
    html = html.replace(
        "canario-luna:${rubricVersion}",
        "canario-luna-adjudicacao:${rubricVersion}")
    html = html.replace(
        "0 de 24 concluídas", "0 de {} concluídas".format(len(selecionadas)))
    saida.write_text(html, encoding="utf-8")
    return comparacao, selecionadas


def argumentos():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revisoes", nargs="+", type=Path, required=True)
    parser.add_argument("--html-origem", type=Path, required=True)
    parser.add_argument("--saida", type=Path, required=True)
    return parser.parse_args()


def main():
    args = argumentos()
    comparacao, selecionadas = preparar(
        [carregar_revisao(caminho) for caminho in args.revisoes],
        args.html_origem,
        args.saida,
    )
    print("Adjudicacao cega criada: {} de {} imagens; OpenAI: 0 chamadas.".format(
        len(selecionadas), comparacao["sample_size"]))


if __name__ == "__main__":
    main()
