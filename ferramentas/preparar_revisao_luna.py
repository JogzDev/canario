#!/usr/bin/env python3
"""Monta um pacote cego de revisao humana sem chamar a OpenAI.

As imagens saem do cache persistente do i7 e a amostra usa a mesma semente do
avaliador. O HTML nao contem categoria do catalogo nem resposta do modelo;
essas ficam em `predicoes-recuperadas.csv`, para serem abertas somente depois
que os revisores exportarem seus rotulos.
"""

import argparse
import csv
import json
from pathlib import Path
import re
import shutil

from avaliar_luna import (
    SEMENTE_PADRAO,
    carregar_taxonomia,
    ids,
    selecionar_imagens,
)


PADRAO_LOG = re.compile(
    r"\[(?P<ordem>\d+)/(?P<total>\d+)\]\s+"
    r"catalogo=(?P<catalogo>\S+)\s+Luna=(?P<luna>\S+)\s+"
    r"(?P<estado>OK|DIVERGIU).*\|\s+(?P<imagem>[^\s|]+\.(?:jpg|jpeg|png|webp|heic))",
    re.IGNORECASE,
)
VERSAO_RUBRICA = "categoria-cor-v1"


def ler_predicoes(pasta_logs):
    """Recupera do log somente o que foi efetivamente impresso na rodada."""
    predicoes = {}
    for caminho in sorted(pasta_logs.rglob("*")):
        if not caminho.is_file():
            continue
        try:
            texto = caminho.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for linha in texto.splitlines():
            achado = PADRAO_LOG.search(linha)
            if not achado:
                continue
            dados = achado.groupdict()
            chave = (dados["catalogo"], dados["imagem"])
            predicoes[chave] = {
                "ordem_api": int(dados["ordem"]),
                "total": int(dados["total"]),
                "categoria_catalogo": dados["catalogo"],
                "categoria_luna": dados["luna"],
                "concordou": dados["estado"].upper() == "OK",
                "imagem_original": dados["imagem"],
            }
    if not predicoes:
        raise ValueError("Nenhuma predicao do Luna foi encontrada nos logs.")
    return predicoes


def _escrever_csv(caminho, linhas):
    campos = [
        "sample_id", "ordem_api", "total", "imagem_original",
        "categoria_catalogo", "categoria_luna", "concordou",
    ]
    with open(caminho, "w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(arquivo, fieldnames=campos)
        escritor.writeheader()
        escritor.writerows(linhas)


def _rubrica():
    return """# Rubrica humana — categoria e cor

## Regra de independência

Cada revisor abre apenas `revisao.html`, trabalha sozinho e exporta seu JSON e
CSV antes de abrir `predicoes-recuperadas.csv`. O rótulo do catálogo e a saída
do Luna ficam escondidos para não ancorar o julgamento.

## Alvo visual

- `clear`: uma única peça-alvo é identificável apenas pelos pixels.
- `partially_occluded`: a peça-alvo é identificável, mas parte relevante está
  cortada ou coberta.
- `multiple_garments_target_clear`: existem várias peças, mas uma é claramente
  o alvo visual.
- `ambiguous_target`: pixels insuficientes para determinar qual peça é o alvo.

Em `ambiguous_target`, use categoria, estrutura e cor primária `not_visible`.
Não escolha a peça que parece combinar melhor com o rótulo que você imagina.

## Categoria pela estrutura visível

| id | decisão operacional |
|---|---|
| `vestido` | peça única cobrindo tronco e parte inferior, sem pernas separadas |
| `macacao` | peça única cobrindo tronco e parte inferior, com pernas separadas |
| `saia` | peça inferior com painel contínuo, sem entrepernas visível |
| `short` | peça inferior com entrepernas/duas aberturas, até aprox. o joelho |
| `calca` | peça inferior com duas pernas, prolongando-se abaixo do joelho |
| `camisa` | construção de camisaria: abertura frontal longa e estrutura de camisa; colarinho/punhos são evidência forte |
| `casaco_jaqueta` | camada externa concebida para ser usada sobre outra peça |
| `blusa_top` | peça superior restante: camiseta, regata, cropped, top, body ou blusa; somente após excluir camisa e camada externa |

Botões decorativos isolados não bastam para `camisa`. Manga curta nunca é
evidência de `short`. Se um short-saia mostra duas aberturas de perna, rotule
`short`; se a construção interna não é visível, rotule o exterior observado.

## Cor

Rotule somente a peça-alvo. Ignore pele, cabelo, cenário, acessórios, sombras,
logos, botões e acabamentos pequenos. Escolha uma cor primária e no máximo duas
secundárias. Uma secundária deve ocupar aproximadamente 10% da superfície
visível ou reaparecer de forma importante na estampa.

Famílias: `preto`, `branco_cru`, `cinza`, `azul`, `verde`, `lilas_roxo`,
`vermelho_rosa`, `amarelo_laranja`, `terrosos`, `outras_cores`.
`outras_cores` é residual real, não sinônimo de incerteza.
"""


def _instrucoes(run_id):
    return """# Revisão cega da amostra Luna

1. Extraia o ZIP inteiro mantendo a pasta `images` ao lado de `revisao.html`.
2. Leia `RUBRICA.md`.
3. Abra `revisao.html` em um navegador, informe seu nome e rotule as 24 peças.
4. Exporte JSON e CSV. Cada revisor trabalha sem conversar com o outro.
5. Somente depois dos dois exports, abra `predicoes-recuperadas.csv`.

O pacote foi reconstruído do cache do i7 e dos logs do GitHub Actions da
execução {run_id}. Nenhuma chamada à OpenAI foi feita para criá-lo. As imagens
são cópias temporárias de avaliação interna e o artefato expira automaticamente.
""".format(run_id=run_id)


def preparar(cache, taxonomia_path, logs, template, saida, quantidade, semente,
             run_id):
    taxonomia = carregar_taxonomia(taxonomia_path)
    categorias = ids(taxonomia, "categoria")
    amostra = selecionar_imagens(cache, categorias, quantidade, semente)
    predicoes = ler_predicoes(logs)

    saida.mkdir(parents=True, exist_ok=False)
    pasta_imagens = saida / "images"
    pasta_imagens.mkdir()
    amostra_cega = []
    recuperadas = []

    for indice, (catalogo, origem) in enumerate(amostra, 1):
        sample_id = "S{:02d}".format(indice)
        extensao = origem.suffix.lower() or ".jpg"
        destino = pasta_imagens / (sample_id + extensao)
        shutil.copy2(origem, destino)
        amostra_cega.append({
            "sample_id": sample_id,
            "image": "images/" + destino.name,
        })
        chave = (catalogo, origem.name)
        if chave not in predicoes:
            raise ValueError(
                "O log nao contem a amostra {} ({}/{}).".format(
                    sample_id, catalogo, origem.name))
        item = dict(predicoes[chave])
        item["sample_id"] = sample_id
        recuperadas.append(item)

    recuperadas.sort(key=lambda item: item["sample_id"])
    html = template.read_text(encoding="utf-8")
    marcador = "__CANARIO_SAMPLES_JSON__"
    if marcador not in html:
        raise ValueError("Template sem o marcador da amostra.")
    html = html.replace(
        marcador,
        json.dumps(amostra_cega, ensure_ascii=False, separators=(",", ":")),
    )
    (saida / "revisao.html").write_text(html, encoding="utf-8")
    (saida / "amostra-cega.json").write_text(
        json.dumps({
            "rubric_version": VERSAO_RUBRICA,
            "seed": semente,
            "quantity": quantidade,
            "samples": amostra_cega,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    _escrever_csv(saida / "predicoes-recuperadas.csv", recuperadas)
    (saida / "RUBRICA.md").write_text(_rubrica(), encoding="utf-8")
    (saida / "README.md").write_text(_instrucoes(run_id), encoding="utf-8")
    return amostra_cega, recuperadas


def argumentos():
    raiz = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--saida", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--quantidade", type=int, default=24)
    parser.add_argument("--semente", type=int, default=SEMENTE_PADRAO)
    parser.add_argument(
        "--taxonomia", type=Path, default=raiz / "anexos" / "taxonomia.csv")
    parser.add_argument(
        "--template", type=Path,
        default=raiz / "ferramentas" / "revisao_luna.html")
    return parser.parse_args()


def main():
    args = argumentos()
    amostra, predicoes = preparar(
        args.cache, args.taxonomia, args.logs, args.template, args.saida,
        args.quantidade, args.semente, args.run_id)
    divergencias = sum(not item["concordou"] for item in predicoes)
    print("Pacote cego criado: {} imagens.".format(len(amostra)))
    print("Predicoes recuperadas do log: {} ({} divergencias).".format(
        len(predicoes), divergencias))
    print("Chamadas a OpenAI: 0")


if __name__ == "__main__":
    main()
