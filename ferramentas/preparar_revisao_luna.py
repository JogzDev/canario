#!/usr/bin/env python3
"""Monta um pacote cego de revisao humana sem chamar a OpenAI.

As imagens saem do cache persistente do i7 e a amostra usa a mesma semente do
avaliador. O HTML nao contem categoria do catalogo nem resposta do modelo;
essas ficam em `predicoes-recuperadas.csv`, para serem abertas somente depois
que os revisores exportarem seus rotulos.
"""

import argparse
import base64
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from avaliar_luna import (
    SEMENTE_PADRAO,
    carregar_taxonomia,
    ids,
    selecionar_amostra_de_avaliacao,
)


PADRAO_LOG = re.compile(
    r"\[(?P<ordem>\d+)/(?P<total>\d+)\]\s+"
    r"catalogo=(?P<catalogo>\S+)\s+Luna=(?P<luna>\S+)\s+"
    r"(?P<estado>OK|DIVERGIU).*\|\s+(?P<imagem>[^\s|]+\.(?:jpg|jpeg|png|webp|heic))",
    re.IGNORECASE,
)
VERSAO_RUBRICA = "categoria-cor-v2"
CONTRATO_LOTE = "canario_luna_review_batch_v1"
MIME_POR_EXTENSAO = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
}


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
        "batch_id", "sample_id", "ordem_api", "total", "imagem_original",
        "categoria_catalogo", "categoria_luna", "concordou",
    ]
    with open(caminho, "w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(arquivo, fieldnames=campos)
        escritor.writeheader()
        escritor.writerows(linhas)


def _imagem_embutida(caminho):
    """Transforma a imagem em data URL para o HTML funcionar isoladamente."""
    extensao = caminho.suffix.lower()
    mime = MIME_POR_EXTENSAO.get(extensao)
    if mime is None:
        raise ValueError("Extensao de imagem sem MIME: {}".format(extensao))
    conteudo = base64.b64encode(caminho.read_bytes()).decode("ascii")
    return "data:{};base64,{}".format(mime, conteudo)


def _json_canonico(valor):
    return json.dumps(
        valor, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")


def _sha256(valor):
    return hashlib.sha256(valor).hexdigest()


def _json_para_script(valor):
    # JSON valido ainda pode fechar um elemento <script> no parser HTML.
    # Os nomes de imagem sao dados, nunca marcacao executavel.
    return (json.dumps(valor, ensure_ascii=False, separators=(",", ":"))
            .replace("&", "\\u0026").replace("<", "\\u003c")
            .replace(">", "\\u003e").replace("\u2028", "\\u2028")
            .replace("\u2029", "\\u2029"))


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
  o alvo visual por enquadramento, escala, centralidade e nível de detalhe.
- `ambiguous_target`: pixels insuficientes para determinar qual peça é o alvo.

Em `ambiguous_target`, use categoria, estrutura e cor primária `not_visible`.
Não escolha a peça que parece combinar melhor com o rótulo que você imagina.

## Estrutura visível; categoria derivada automaticamente

O revisor escolhe a estrutura e a ferramenta deriva a categoria pelo mapa
abaixo. Não existem duas decisões semânticas capazes de se contradizer.

| id | decisão operacional |
|---|---|
| `vestido` | peça única cobrindo tronco e parte inferior, sem pernas separadas |
| `macacao` | peça única cobrindo tronco e parte inferior, com pernas separadas |
| `saia` | peça inferior com painel contínuo, sem entrepernas visível |
| `short` | peça inferior até aprox. o joelho com evidência de duas pernas: entrepernas, costura central, separação ou duas aberturas |
| `calca` | peça inferior com duas pernas, prolongando-se abaixo do joelho |
| `camisa` | construção de camisaria: colarinho com abertura/placket frontal substancial e/ou punhos; camisa amarrada continua camisa |
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


def _instrucoes(run_id, quantidade):
    return """# Revisão cega da amostra Luna

1. Extraia o ZIP e abra `revisao.html`. O arquivo já contém as {quantidade} imagens e
   continua funcionando se for movido sozinho.
2. Leia `RUBRICA.md`.
3. Abra `revisao.html` em um navegador, informe um alias e rotule as {quantidade} peças.
4. Exporte JSON e CSV. Cada revisor trabalha sem conversar com o outro.
5. Somente depois dos dois exports, abra `predicoes-recuperadas.csv`.

O pacote foi reconstruído do cache do i7 e dos logs do GitHub Actions da
execução {run_id}. Nenhuma chamada à OpenAI foi feita para criá-lo. As imagens
são cópias temporárias de avaliação interna e o artefato expira automaticamente.
""".format(run_id=run_id, quantidade=quantidade)


def preparar(cache, taxonomia_path, logs, template, saida, quantidade, semente,
             run_id):
    if (not isinstance(run_id, str) or not run_id.strip()
            or len(run_id.strip()) > 160):
        raise ValueError("run_id ausente ou longo demais.")
    if isinstance(quantidade, bool) or not isinstance(quantidade, int) or quantidade <= 0:
        raise ValueError("Quantidade deve ser um inteiro positivo.")
    saida = Path(saida)
    if saida.exists():
        raise FileExistsError("A saida ja existe: {}".format(saida))

    taxonomia = carregar_taxonomia(taxonomia_path)
    categorias = ids(taxonomia, "categoria")
    amostra = selecionar_amostra_de_avaliacao(
        cache, categorias, quantidade, semente)
    predicoes = ler_predicoes(logs)

    template_html = template.read_text(encoding="utf-8")
    marcador_amostras = "__CANARIO_SAMPLES_JSON__"
    marcador_lote = "__CANARIO_BATCH_ID_JSON__"
    if marcador_amostras not in template_html or marcador_lote not in template_html:
        raise ValueError("Template sem os marcadores do lote e da amostra.")

    amostra_base = []
    recuperadas = []

    for indice, (catalogo, origem) in enumerate(amostra, 1):
        sample_id = "S{:02d}".format(indice)
        conteudo = origem.read_bytes()
        amostra_base.append({
            "sample_id": sample_id,
            "imagem": origem.name,
            "image_sha256": _sha256(conteudo),
            "extensao": origem.suffix.lower() or ".jpg",
            "origem": origem,
        })
        chave = (catalogo, origem.name)
        if chave not in predicoes:
            raise ValueError(
                "O log nao contem a amostra {} ({}/{}).".format(
                    sample_id, catalogo, origem.name))
        item = dict(predicoes[chave])
        item["sample_id"] = sample_id
        if item["ordem_api"] != indice or item["total"] != quantidade:
            raise ValueError(
                "Predicao fora da rodada em {}: ordem={}/{}, esperado={}/{}.".
                format(sample_id, item["ordem_api"], item["total"],
                       indice, quantidade))
        if item["concordou"] != (item["categoria_catalogo"] == item["categoria_luna"]):
            raise ValueError("Estado OK/DIVERGIU incoerente em {}.".format(sample_id))
        recuperadas.append(item)

    # `S100` vem antes de `S11` em ordenacao textual; o holdout de 300 precisa
    # preservar a ordem numerica da rodada para a identidade nao ligar uma
    # imagem a outra predicao.
    recuperadas.sort(key=lambda item: item["ordem_api"])
    identidade = {
        "contract": CONTRATO_LOTE,
        "rubric_version": VERSAO_RUBRICA,
        "run_id": run_id.strip(),
        "seed": semente,
        "quantity": quantidade,
        "samples": [
            {
                "sample_id": amostra_base[indice]["sample_id"],
                "imagem": amostra_base[indice]["imagem"],
                "image_sha256": amostra_base[indice]["image_sha256"],
                "prediction": {
                    campo: recuperadas[indice][campo]
                    for campo in (
                        "ordem_api", "total", "categoria_catalogo",
                        "categoria_luna", "concordou",
                    )
                },
            }
            for indice in range(len(amostra_base))
        ],
    }
    batch_id = _sha256(_json_canonico(identidade))
    for item in recuperadas:
        item["batch_id"] = batch_id

    saida.parent.mkdir(parents=True, exist_ok=True)
    temporaria = Path(tempfile.mkdtemp(
        prefix=saida.name + ".", suffix=".tmp", dir=str(saida.parent)))
    try:
        pasta_imagens = temporaria / "images"
        pasta_imagens.mkdir()
        amostra_cega = []
        amostra_html = []
        for item in amostra_base:
            destino = pasta_imagens / (item["sample_id"] + item["extensao"])
            shutil.copy2(item["origem"], destino)
            if _sha256(destino.read_bytes()) != item["image_sha256"]:
                raise ValueError("Imagem mudou durante o preparo: {}".format(
                    item["sample_id"]))
            identidade_publica = {
                "sample_id": item["sample_id"],
                "imagem": item["imagem"],
                "image_sha256": item["image_sha256"],
            }
            amostra_cega.append({
                **identidade_publica,
                "image": "images/" + destino.name,
            })
            amostra_html.append({
                **identidade_publica,
                "image": _imagem_embutida(destino),
            })

        html = template_html.replace(
            marcador_amostras,
            _json_para_script(amostra_html),
        ).replace(marcador_lote, _json_para_script(batch_id))
        (temporaria / "revisao.html").write_text(html, encoding="utf-8")
        (temporaria / "amostra-cega.json").write_text(
            json.dumps({
                "contract": CONTRATO_LOTE,
                "batch_id": batch_id,
                "rubric_version": VERSAO_RUBRICA,
                "run_id": run_id.strip(),
                "seed": semente,
                "quantity": quantidade,
                "samples": amostra_cega,
            }, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        _escrever_csv(temporaria / "predicoes-recuperadas.csv", recuperadas)
        (temporaria / "RUBRICA.md").write_text(_rubrica(), encoding="utf-8")
        (temporaria / "README.md").write_text(
            _instrucoes(run_id, quantidade), encoding="utf-8")
        if saida.exists():
            raise FileExistsError("A saida passou a existir durante o preparo")
        os.replace(str(temporaria), str(saida))
    except BaseException:
        shutil.rmtree(temporaria, ignore_errors=True)
        raise
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
