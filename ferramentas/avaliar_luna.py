#!/usr/bin/env python3
"""Avalia o gpt-5.6-luna nas imagens em cache do classificador.

Este e um experimento manual, nunca parte do pipeline diario. A amostra e
estratificada pelas oito pastas de categoria e usa semente fixa. O nome da
pasta vem do matcher do titulo do produto: serve como rotulo fraco para o
smoke test, nao como verdade humana para abrir o portao de 80% da A15.

Exemplo (no runner i7):
    OPENAI_API_KEY=... python3 ferramentas/avaliar_luna.py --quantidade 24
"""

import argparse
import base64
import csv
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


MODELO = "gpt-5.6-luna"
URL_RESPOSTAS = "https://api.openai.com/v1/responses"
SEMENTE_PADRAO = 20260810
DIMENSOES = (
    "categoria",
    "estampa",
    "tecido",
    "comprimento",
    "silhueta",
    "cintura",
    "estetica",
    "cor",
)
CAMPOS_POR_DIMENSAO = {
    "categoria": "category",
    "estampa": "pattern",
    "tecido": "fabrics",
    "comprimento": "length",
    "silhueta": "silhouette",
    "cintura": "waist",
    "estetica": "aesthetics",
    "cor": "colors",
}


class ErroDaOpenAI(RuntimeError):
    """Erro deliberadamente curto: nao imprime resposta nem dados da conta."""


def carregar_taxonomia(caminho):
    """Le os ids aprovados; o avaliador nao mantem uma segunda taxonomia."""
    por_dimensao = {dimensao: [] for dimensao in DIMENSOES}
    with open(caminho, encoding="utf-8", newline="") as arquivo:
        for linha in csv.DictReader(arquivo):
            dimensao = linha["dimensao"]
            if linha["status"] != "aprovado" or dimensao not in por_dimensao:
                continue
            por_dimensao[dimensao].append({
                "id": linha["id"],
                "rotulo": linha["rotulo"],
                "palavras_en": linha["palavras_en"],
                "exemplo": linha["exemplo"],
            })
    vazias = [d for d, linhas in por_dimensao.items() if not linhas]
    if vazias:
        raise ValueError("Dimensoes vazias na taxonomia: " + ", ".join(vazias))
    return por_dimensao


def ids(taxonomia, dimensao):
    return [linha["id"] for linha in taxonomia[dimensao]]


def montar_schema(taxonomia):
    """Schema estrito da Responses API; extras ficam fora dos ids medidos."""
    propriedades = {
        "category": {
            "type": "string",
            "enum": ["not_visible"] + ids(taxonomia, "categoria"),
            "description": "One primary garment category, or not_visible.",
        },
        "pattern": {
            "type": "string",
            "enum": ["not_visible"] + ids(taxonomia, "estampa"),
            "description": "The primary garment pattern, or not_visible.",
        },
        "fabrics": {
            "type": "array",
            "items": {"type": "string", "enum": ids(taxonomia, "tecido")},
            "description": "Only fabrics strongly supported by visible construction.",
        },
        "length": {
            "type": "string",
            "enum": ["not_visible"] + ids(taxonomia, "comprimento"),
        },
        "silhouette": {
            "type": "string",
            "enum": ["not_visible"] + ids(taxonomia, "silhueta"),
        },
        "waist": {
            "type": "string",
            "enum": ["not_visible"] + ids(taxonomia, "cintura"),
        },
        "aesthetics": {
            "type": "array",
            "items": {"type": "string", "enum": ids(taxonomia, "estetica")},
        },
        "colors": {
            "type": "array",
            "items": {"type": "string", "enum": ids(taxonomia, "cor")},
            "description": "One to three dominant colors of the garment itself.",
        },
        "additional_visual_attributes": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "Concrete visual attributes in English not represented by the "
                "taxonomy. These are never treated as measured market terms."
            ),
        },
    }
    return {
        "type": "object",
        "properties": propriedades,
        "required": list(propriedades),
        "additionalProperties": False,
    }


def instrucoes(taxonomia):
    linhas = []
    for dimensao in DIMENSOES:
        itens = []
        for termo in taxonomia[dimensao]:
            pistas = termo["palavras_en"] or termo["rotulo"]
            itens.append("{} ({})".format(termo["id"], pistas))
        linhas.append("- {}: {}".format(
            CAMPOS_POR_DIMENSAO[dimensao], "; ".join(itens)))

    return """You are the visual garment analyzer for a women's fashion app.
Analyze exactly one primary garment in the image. Ignore the model's body,
skin, hair, pose, background, props, footwear, bags, jewelry, and unrelated
layers. Use pixels only: the catalog title and its existing label are hidden.

Return the exact stable Portuguese ids defined below. Choose only attributes
supported by visible evidence. Category must describe the primary garment.
Use pattern=liso for a visibly plain garment and not_visible only when pattern
cannot be judged. Do not claim fiber composition merely from appearance;
fabrics may be empty. Length, silhouette and waist may be not_visible when
inapplicable, cropped or occluded. Colors must describe the garment, never
skin or background, with one to three ids. Aesthetics may contain at most
three ids. additional_visual_attributes may contain at most five short,
concrete English phrases not already covered by the taxonomy. Never repeat an
item and never put a free-form guess into a taxonomy field.

Taxonomy:
{}""".format("\n".join(linhas))


def montar_payload(imagem_em_data_url, taxonomia):
    return {
        "model": MODELO,
        "store": False,
        "reasoning": {"effort": "low"},
        "max_output_tokens": 1200,
        "instructions": instrucoes(taxonomia),
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": "Analyze the primary garment in this image.",
                },
                {
                    "type": "input_image",
                    "image_url": imagem_em_data_url,
                    "detail": "high",
                },
            ],
        }],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "canario_clothing_analysis",
                "strict": True,
                "schema": montar_schema(taxonomia),
            },
        },
    }


def selecionar_imagens(raiz, categorias, quantidade, semente=SEMENTE_PADRAO):
    """Distribui a diferenca de no maximo uma imagem entre categorias."""
    if quantidade < len(categorias):
        raise ValueError("A quantidade precisa cobrir todas as categorias.")
    base, resto = divmod(quantidade, len(categorias))
    gerador = random.Random(semente)
    selecionadas = []
    extensoes = {".jpg", ".jpeg", ".png", ".webp", ".heic"}

    for indice, categoria in enumerate(categorias):
        pasta = raiz / categoria
        arquivos = sorted(
            p for p in pasta.iterdir()
            if p.is_file() and p.suffix.lower() in extensoes
        ) if pasta.is_dir() else []
        n = base + (1 if indice < resto else 0)
        if len(arquivos) < n:
            raise ValueError(
                "Cache insuficiente em {}: {} imagens, precisa de {}.".format(
                    categoria, len(arquivos), n))
        for caminho in gerador.sample(arquivos, n):
            selecionadas.append((categoria, caminho))

    gerador.shuffle(selecionadas)
    return selecionadas


def preparar_imagem(origem, destino):
    """Normaliza a imagem para JPEG de ate 1024 px e custo previsivel."""
    comando = [
        "/usr/bin/sips", "-Z", "1024",
        "--setProperty", "format", "jpeg",
        "--setProperty", "formatOptions", "82",
        str(origem), "--out", str(destino),
    ]
    processo = subprocess.run(
        comando, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if processo.returncode != 0 or not destino.is_file():
        raise RuntimeError("sips nao conseguiu normalizar {}".format(origem.name))
    return "data:image/jpeg;base64," + base64.b64encode(
        destino.read_bytes()).decode("ascii")


def _erro_curto(corpo):
    try:
        erro = json.loads(corpo.decode("utf-8")).get("error", {})
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "erro_sem_codigo"
    return str(erro.get("code") or erro.get("type") or "erro_sem_codigo")[:80]


def chamar_openai(payload, chave, tentativas=3):
    dados = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    requisicao = urllib.request.Request(
        URL_RESPOSTAS,
        data=dados,
        headers={
            "Authorization": "Bearer " + chave,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    for tentativa in range(tentativas):
        try:
            with urllib.request.urlopen(requisicao, timeout=180) as resposta:
                return json.load(resposta)
        except urllib.error.HTTPError as erro:
            corpo = erro.read()
            transitorio = erro.code == 429 or 500 <= erro.code < 600
            if transitorio and tentativa + 1 < tentativas:
                espera = min(20, 2 ** tentativa)
                time.sleep(espera)
                continue
            raise ErroDaOpenAI(
                "OpenAI HTTP {} ({})".format(erro.code, _erro_curto(corpo)))
        except urllib.error.URLError as erro:
            if tentativa + 1 < tentativas:
                time.sleep(min(20, 2 ** tentativa))
                continue
            raise ErroDaOpenAI("Falha de rede ao chamar a OpenAI") from erro
    raise ErroDaOpenAI("A OpenAI nao respondeu")


def extrair_texto(resposta):
    if resposta.get("status") == "incomplete":
        motivo = (resposta.get("incomplete_details") or {}).get(
            "reason", "desconhecido")
        raise ErroDaOpenAI("Resposta incompleta ({})".format(motivo))
    for item in resposta.get("output", []):
        if item.get("type") != "message":
            continue
        for conteudo in item.get("content", []):
            if conteudo.get("type") == "refusal":
                raise ErroDaOpenAI("O modelo recusou a imagem")
            if conteudo.get("type") == "output_text":
                return conteudo.get("text", "")
    raise ErroDaOpenAI("Resposta sem output_text")


def custo_estimado(uso):
    """Preco publicado do Luna em 10/08/2026, em dolares."""
    entrada = int(uso.get("input_tokens", 0))
    detalhes = uso.get("input_tokens_details") or {}
    cache = int(detalhes.get("cached_tokens", 0))
    saida = int(uso.get("output_tokens", 0))
    return ((entrada - cache) * 0.20 + cache * 0.02 + saida * 1.20) / 1_000_000


def percentile_95(valores):
    if not valores:
        return 0.0
    ordenados = sorted(valores)
    indice = min(len(ordenados) - 1, int((len(ordenados) - 1) * 0.95 + 0.5))
    return ordenados[indice]


def escrever_resumo(caminho, resultados, custo, duracao_total):
    acertos = sum(r["acertou_categoria"] for r in resultados)
    total = len(resultados)
    latencias = [r["latencia_s"] for r in resultados]
    uso_total = {
        chave: sum(int((r["usage"] or {}).get(chave, 0)) for r in resultados)
        for chave in ("input_tokens", "output_tokens", "total_tokens")
    }
    categorias = sorted({r["categoria_catalogo"] for r in resultados})
    linhas = [
        "## Luna — avaliacao estratificada",
        "",
        "- Modelo: `{}` (`store=false`, reasoning low, image detail high)".format(MODELO),
        "- Imagens: **{}**".format(total),
        "- Concordancia de categoria com o rotulo fraco do catalogo: "
        "**{}/{} ({:.1%})**".format(acertos, total, acertos / total),
        "- Tokens: {} entrada, {} saida, {} total".format(
            uso_total["input_tokens"], uso_total["output_tokens"],
            uso_total["total_tokens"]),
        "- Custo estimado: **US$ {:.6f}**".format(custo),
        "- Duracao: {:.1f}s; latencia mediana {:.1f}s; p95 {:.1f}s".format(
            duracao_total, statistics.median(latencias), percentile_95(latencias)),
        "",
        "> O nome da pasta foi derivado do titulo do produto. Esta concordancia "
        "e diagnostica e nao abre o portao de 80%, que exige revisao humana de "
        "categoria e cor.",
        "",
        "### Por categoria",
        "",
        "| catalogo | acertos | total | concordancia |",
        "|---|---:|---:|---:|",
    ]
    for categoria in categorias:
        grupo = [r for r in resultados if r["categoria_catalogo"] == categoria]
        certos = sum(r["acertou_categoria"] for r in grupo)
        linhas.append("| {} | {} | {} | {:.1%} |".format(
            categoria, certos, len(grupo), certos / len(grupo)))

    linhas += [
        "",
        "### Predicoes",
        "",
        "| imagem | catalogo | Luna | estampa | cores | tempo |",
        "|---|---|---|---|---|---:|",
    ]
    for r in resultados:
        analise = r["analysis"]
        linhas.append("| {} | {} | {} | {} | {} | {:.1f}s |".format(
            r["imagem"], r["categoria_catalogo"], analise["category"],
            analise["pattern"], ", ".join(analise["colors"]), r["latencia_s"]))
    caminho.write_text("\n".join(linhas) + "\n", encoding="utf-8")


def argumentos():
    raiz = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--quantidade", type=int, default=24)
    parser.add_argument("--semente", type=int, default=SEMENTE_PADRAO)
    parser.add_argument(
        "--cache",
        type=Path,
        default=Path.home() / "canario-imagens-treino",
    )
    parser.add_argument(
        "--taxonomia",
        type=Path,
        default=raiz / "anexos" / "taxonomia.csv",
    )
    parser.add_argument("--saida", type=Path)
    parser.add_argument("--resumo", type=Path)
    return parser.parse_args()


def main():
    args = argumentos()
    chave = os.environ.get("OPENAI_API_KEY", "")
    if not chave:
        raise SystemExit("OPENAI_API_KEY ausente")
    if args.quantidade < 8 or args.quantidade > 300:
        raise SystemExit("--quantidade precisa estar entre 8 e 300")

    taxonomia = carregar_taxonomia(args.taxonomia)
    categorias = ids(taxonomia, "categoria")
    amostra = selecionar_imagens(
        args.cache, categorias, args.quantidade, args.semente)
    resultados = []
    custo = 0.0
    inicio_total = time.monotonic()

    with tempfile.TemporaryDirectory(prefix="canario-luna-") as temporaria:
        pasta_temporaria = Path(temporaria)
        for indice, (esperada, imagem) in enumerate(amostra, 1):
            normalizada = pasta_temporaria / "{:03d}.jpg".format(indice)
            data_url = preparar_imagem(imagem, normalizada)
            inicio = time.monotonic()
            resposta = chamar_openai(
                montar_payload(data_url, taxonomia), chave)
            latencia = time.monotonic() - inicio
            try:
                analise = json.loads(extrair_texto(resposta))
            except json.JSONDecodeError as erro:
                raise ErroDaOpenAI("output_text nao e JSON valido") from erro

            uso = resposta.get("usage") or {}
            custo += custo_estimado(uso)
            resultado = {
                "imagem": imagem.name,
                "categoria_catalogo": esperada,
                "analysis": analise,
                "acertou_categoria": analise.get("category") == esperada,
                "latencia_s": round(latencia, 3),
                "usage": uso,
                "response_id": resposta.get("id"),
            }
            resultados.append(resultado)
            print(
                "[{}/{}] catalogo={} Luna={} {} | {:.1f}s | in={} out={} | {}".format(
                    indice, len(amostra), esperada, analise.get("category"),
                    "OK" if resultado["acertou_categoria"] else "DIVERGIU",
                    latencia, uso.get("input_tokens", 0),
                    uso.get("output_tokens", 0), imagem.name),
                flush=True,
            )

    duracao_total = time.monotonic() - inicio_total
    if args.saida:
        with open(args.saida, "w", encoding="utf-8") as arquivo:
            for resultado in resultados:
                arquivo.write(json.dumps(resultado, ensure_ascii=False) + "\n")
    if args.resumo:
        escrever_resumo(args.resumo, resultados, custo, duracao_total)

    acertos = sum(r["acertou_categoria"] for r in resultados)
    print("\nConcordancia de categoria: {}/{} ({:.1%})".format(
        acertos, len(resultados), acertos / len(resultados)))
    print("Custo estimado: US$ {:.6f}".format(custo))
    print("Duracao total: {:.1f}s".format(duracao_total))


if __name__ == "__main__":
    main()
