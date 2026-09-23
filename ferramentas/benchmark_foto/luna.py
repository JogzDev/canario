#!/usr/bin/env python3
"""Benchmark de foto: as Lunas da OpenAI no contrato exato do app.

POR QUE ESTE ARQUIVO EXISTE
===========================

A 2.0 decide quem lê a foto da peça: a Luna (OpenAI), o modelo da Apple no
aparelho ou o da nuvem privada da Apple. O benchmark antigo
(`ferramentas/avaliar_luna.py`) usava fotos de catálogo de loja, com fundo de
estúdio -- não é o que a pessoa fotografa no Estúdio. Este usa 100 fotos de
licença aberta (`manifesto.json`): 50 de peça solta, feitas por gente comum
em cabide, cama ou chão (clothing-dataset, CC0), e 50 de peça vestida, com
selfie no espelho e foto de rua (Openverse, CC0 e CC BY; autor e licença de
cada uma no manifesto).

O pedido é o MESMO da Edge Function `analisar-peca`: as instruções e o esquema
saem do `index.ts` na hora da execução, então o benchmark nunca mede um prompt
que o app não usa. Muda só o modelo. Condição base: foto inteira, sem dica de
alvo -- o caso mais difícil do app.

As imagens não moram no repositório: são baixadas da fonte a cada execução e
nada volta para o Git. A resposta crua de cada modelo sai num JSONL, que a
comparação com o gabarito humano consome.

Uso (a chave vem do ambiente; no GitHub, do segredo OPENAI_API_KEY):
    python3 ferramentas/benchmark_foto/luna.py --modelos gpt-6-luna,gpt-5.6-luna \
        --saida resultados.jsonl
"""

import argparse
import base64
import concurrent.futures
import io
import json
import os
from pathlib import Path
import re
import sys
import threading
import time
import urllib.error
import urllib.request

RAIZ = Path(__file__).resolve().parents[2]
EDGE = RAIZ / "supabase" / "functions" / "analisar-peca" / "index.ts"
MANIFESTO = Path(__file__).resolve().parent / "manifesto.json"
URL_RESPOSTAS = "https://api.openai.com/v1/responses"
UA = "CanarioBench/1.0 (projeto academico; contato: canarioch3@gmail.com)"
LADO_MAXIMO = 1600
PEDIDO = ("Determine whether one target garment is visually identifiable, "
          "then analyze it under the contract.")


def contrato_do_app(texto=None):
    """Instruções e esquema exatamente como a Edge Function os monta."""
    texto = texto if texto is not None else EDGE.read_text(encoding="utf-8")
    taxonomia = re.search(r"const TAXONOMY = `(.*?)`;", texto, re.S).group(1)
    instrucoes = re.search(r"const INSTRUCTIONS = `(.*?)`;", texto, re.S).group(1)
    instrucoes = instrucoes.replace("${TAXONOMY}", taxonomia)
    if "${" in instrucoes:
        raise ValueError("interpolacao desconhecida nas instrucoes da Edge Function")
    versao = re.search(r'const PROMPT_VERSION = "([^"]+)";', texto).group(1)

    estruturas = re.findall(r"^\s+(\w+): \"\w+\",$",
                            re.search(r"const CATEGORY_BY_STRUCTURE[^{]*\{(.*?)\};",
                                      texto, re.S).group(1), re.M)
    bloco_ids = re.search(r"const IDS = \{(.*?)\} as const;", texto, re.S).group(1)
    ids = {nome: re.findall(r'"([^"]+)"', lista)
           for nome, lista in re.findall(r"(\w+): \[([^\]]*)\]", bloco_ids)}

    def nao_visivel(itens):
        return ["not_visible", *itens]

    propriedades = {
        "target_clarity": {"type": "string", "enum": [
            "clear", "partially_occluded", "multiple_garments_target_clear",
            "ambiguous_target"]},
        "garment_structure": {"type": "string", "enum": estruturas},
        "decision_evidence": {"type": "array", "items": {"type": "string"},
                              "minItems": 1, "maxItems": 4},
        "pattern": {"type": "string", "enum": nao_visivel(ids["estampa"])},
        "fabrics": {"type": "array", "items": {"type": "string", "enum": ids["tecido"]},
                    "maxItems": 3},
        "length": {"type": "string", "enum": nao_visivel(ids["comprimento"])},
        "silhouette": {"type": "string", "enum": nao_visivel(ids["silhueta"])},
        "waist": {"type": "string", "enum": nao_visivel(ids["cintura"])},
        "aesthetics": {"type": "array", "items": {"type": "string", "enum": ids["estetica"]},
                       "maxItems": 3},
        "colors": {"type": "array", "items": {"type": "string", "enum": ids["cor"]},
                   "maxItems": 3},
        "additional_visual_attributes": {"type": "array", "items": {"type": "string"},
                                         "maxItems": 5},
    }
    esquema = {"type": "object", "properties": propriedades,
               "required": list(propriedades), "additionalProperties": False}
    return instrucoes, esquema, versao


def imagem_jpeg(url, cache):
    """Baixa da fonte uma vez e reduz ao lado maximo, como faz a miniatura."""
    destino = cache / (re.sub(r"[^A-Za-z0-9]", "_", url)[-120:] + ".jpg")
    if not destino.exists():
        pedido = urllib.request.Request(url, headers={"User-Agent": UA})
        bruto = urllib.request.urlopen(pedido, timeout=60).read()
        from PIL import Image
        imagem = Image.open(io.BytesIO(bruto)).convert("RGB")
        imagem.thumbnail((LADO_MAXIMO, LADO_MAXIMO))
        saida = io.BytesIO()
        imagem.save(saida, format="JPEG", quality=88)
        destino.write_bytes(saida.getvalue())
    return destino.read_bytes()


def ler(modelo, jpeg, instrucoes, esquema, chave):
    corpo = {
        "model": modelo,
        "store": False,
        "reasoning": {"effort": "medium"},
        "max_output_tokens": 2500,
        "instructions": instrucoes,
        "input": [{"role": "user", "content": [
            {"type": "input_text", "text": PEDIDO},
            {"type": "input_image", "detail": "high",
             "image_url": "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()},
        ]}],
        "text": {"format": {"type": "json_schema", "name": "canario_clothing_analysis",
                            "strict": True, "schema": esquema}},
    }
    pedido = urllib.request.Request(
        URL_RESPOSTAS, data=json.dumps(corpo).encode(), method="POST",
        headers={"Authorization": "Bearer " + chave, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(pedido, timeout=180) as r:
            dados = json.load(r)
    except urllib.error.HTTPError as erro:
        detalhe = erro.read().decode("utf-8", "replace")[:300]
        return None, "http {}: {}".format(erro.code, detalhe), None
    texto = next((c.get("text") for item in dados.get("output") or []
                  if item.get("type") == "message"
                  for c in item.get("content") or [] if c.get("type") == "output_text"),
                 None)
    if not texto:
        return None, "sem texto ({})".format(dados.get("status")), dados.get("usage")
    try:
        return json.loads(texto), None, dados.get("usage")
    except ValueError:
        return None, "json invalido", dados.get("usage")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modelos")
    parser.add_argument("--saida")
    parser.add_argument("--cache", default=os.environ.get("RUNNER_TEMP", "/tmp") + "/fotos-benchmark")
    parser.add_argument("--limite", type=int, default=0, help="so as N primeiras fotos (fumaca)")
    parser.add_argument("--paralelo", type=int, default=4)
    parser.add_argument("--so-instrucoes", help="grava as instrucoes do app e sai (para o apple.swift)")
    args = parser.parse_args()
    if args.so_instrucoes:
        Path(args.so_instrucoes).write_text(contrato_do_app()[0], encoding="utf-8")
        return 0

    chave = os.environ.get("OPENAI_API_KEY", "").strip()
    if not chave:
        print("ERRO: OPENAI_API_KEY ausente", file=sys.stderr)
        return 1
    instrucoes, esquema, versao = contrato_do_app()
    fotos = json.loads(MANIFESTO.read_text(encoding="utf-8"))
    if args.limite:
        fotos = fotos[:args.limite]
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    trava = threading.Lock()
    saida = open(args.saida, "w", encoding="utf-8")

    def uma(modelo, foto):
        inicio = time.monotonic()
        try:
            jpeg = imagem_jpeg(foto["url"], cache)
        except Exception as erro:  # noqa: BLE001 - fonte fora do ar vira linha
            resposta, falha, uso = None, "download: {}".format(erro), None
        else:
            try:
                resposta, falha, uso = ler(modelo, jpeg, instrucoes, esquema, chave)
            except Exception as erro:  # noqa: BLE001 - tempo esgotado vira linha
                resposta, falha, uso = None, "rede: {}".format(erro), None
        linha = {"id": foto["id"], "modelo": modelo, "prompt_version": versao,
                 "segundos": round(time.monotonic() - inicio, 2),
                 "resposta": resposta, "erro": falha, "uso": uso}
        with trava:
            saida.write(json.dumps(linha, ensure_ascii=False) + "\n")
            saida.flush()
            print("{:14} {:12} {}".format(modelo, foto["id"], falha or "ok"), flush=True)

    for modelo in [m.strip() for m in args.modelos.split(",") if m.strip()]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.paralelo) as fila:
            list(fila.map(lambda f: uma(modelo, f), fotos))
    saida.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
