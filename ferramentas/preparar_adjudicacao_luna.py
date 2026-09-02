#!/usr/bin/env python3
"""Cria um HTML cego apenas com as amostras em que dois revisores divergiram."""

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

from consolidar_revisao_luna import (
    carregar_revisao,
    comparar_revisoes,
    ids_para_adjudicar,
)
from preparar_revisao_luna import _json_para_script


PADRAO_AMOSTRAS = re.compile(r"const samples = (\[.*?\]);\n")
PADRAO_BATCH = re.compile(r"const batchId = (\"[0-9a-f]{64}\");\n")


def _escrever_atomico(caminho, texto):
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    descritor, temporario = tempfile.mkstemp(
        prefix=caminho.name + ".", suffix=".tmp", dir=str(caminho.parent))
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            arquivo.write(texto)
            arquivo.flush()
            os.fsync(arquivo.fileno())
        os.replace(temporario, caminho)
    except BaseException:
        try:
            os.unlink(temporario)
        except FileNotFoundError:
            pass
        raise


def preparar(revisoes, html_origem, saida):
    html_origem = Path(html_origem)
    saida = Path(saida)
    if saida.resolve() == html_origem.resolve():
        raise ValueError("A adjudicacao nao pode sobrescrever o HTML de origem.")
    if saida.exists():
        raise FileExistsError("A saida de adjudicacao ja existe: {}".format(saida))
    comparacao = comparar_revisoes(revisoes)
    divergentes = ids_para_adjudicar(comparacao)
    if not divergentes:
        return comparacao, []
    html = html_origem.read_text(encoding="utf-8")
    achado = PADRAO_AMOSTRAS.search(html)
    if not achado:
        raise ValueError("HTML de origem sem amostras embutidas.")
    lote = PADRAO_BATCH.search(html)
    if not lote or json.loads(lote.group(1)) != comparacao["batch_id"]:
        raise ValueError("HTML de origem pertence a outro batch_id.")
    amostras = json.loads(achado.group(1))
    if not isinstance(amostras, list) or any(
            not isinstance(amostra, dict) for amostra in amostras):
        raise ValueError("HTML de origem contem amostras invalidas.")
    selecionadas = [
        amostra for amostra in amostras
        if amostra.get("sample_id") in divergentes
    ]
    if (len(selecionadas) != len(divergentes)
            or {a.get("sample_id") for a in selecionadas} != divergentes):
        raise ValueError("HTML nao contem todas as amostras divergentes.")
    for amostra in selecionadas:
        resposta = revisoes[0]["answers"][amostra["sample_id"]]
        if (amostra.get("imagem"), amostra.get("image_sha256")) != (
                resposta["imagem"], resposta["image_sha256"]):
            raise ValueError("HTML trouxe outra identidade de imagem.")
        imagem = amostra.get("image")
        if not isinstance(imagem, str) or not re.fullmatch(
                r"data:image/(?:jpeg|png|webp|heic);base64,[A-Za-z0-9+/]*={0,2}",
                imagem):
            raise ValueError("HTML exige imagem embutida em base64.")
        try:
            conteudo = base64.b64decode(imagem.split(",", 1)[1], validate=True)
        except binascii.Error as erro:
            raise ValueError("Imagem embutida invalida.") from erro
        if hashlib.sha256(conteudo).hexdigest() != resposta["image_sha256"]:
            raise ValueError("Imagem embutida diverge do hash revisado.")

    json_amostras = _json_para_script(selecionadas)
    html = html[:achado.start(1)] + json_amostras + html[achado.end(1):]
    html = html.replace(
        "Canário — revisão cega Luna", "Canário — adjudicação cega Luna")
    html = html.replace(
        "Revisão cega — categoria e cor",
        "Adjudicação cega — categoria e cor")
    html = html.replace(
        "Não abra <code>predicoes-recuperadas.csv</code> antes de exportar seus rótulos. Clique na imagem para ampliar.",
        "Revise somente os itens em que os revisores divergiram. As respostas deles, o catálogo e o Luna continuam ocultos. Clique na imagem para ampliar.")
    html = html.replace(
        'const reviewMode = "review";',
        'const reviewMode = "adjudication";')
    html = html.replace(
        "0 de 24 concluídas", "0 de {} concluídas".format(len(selecionadas)))
    _escrever_atomico(saida, html)
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
    if selecionadas:
        print("Adjudicacao cega criada: {} de {} imagens; OpenAI: 0 chamadas.".format(
            len(selecionadas), comparacao["sample_size"]))
    else:
        print("Nenhuma divergencia: adjudicacao nao necessaria; HTML nao criado.")


if __name__ == "__main__":
    main()
