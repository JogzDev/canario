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
import hashlib
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
VERSAO_DO_PROMPT = "alvo-estrutura-v5"
URL_RESPOSTAS = "https://api.openai.com/v1/responses"
SEMENTE_PADRAO = 20260810
CLAREZAS_DO_ALVO = (
    "clear",
    "partially_occluded",
    "multiple_garments_target_clear",
    "ambiguous_target",
)
CATEGORIA_POR_ESTRUTURA = {
    "one_piece_no_separate_legs": "vestido",
    "one_piece_with_separate_legs": "macacao",
    "lower_continuous_panel": "saia",
    "lower_two_legs_short": "short",
    "lower_two_legs_long": "calca",
    "upper_shirt_construction": "camisa",
    "upper_outer_layer": "casaco_jaqueta",
    "upper_other": "blusa_top",
    "target_not_determinable": "not_visible",
}
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
    """Schema estrito; categoria e derivada, nao escolhida por sinonimo."""
    propriedades = {
        "target_clarity": {
            "type": "string",
            "enum": list(CLAREZAS_DO_ALVO),
            "description": "Whether one target garment is identifiable from pixels.",
        },
        "garment_structure": {
            "type": "string",
            "enum": list(CATEGORIA_POR_ESTRUTURA),
            "description": "Visible construction of the target garment.",
        },
        "decision_evidence": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "One to four short pixel-grounded cues that justify the target, "
                "structure, and primary color. Never cite title, brand, or filename."
            ),
            "minItems": 1,
            "maxItems": 4,
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
            "maxItems": 3,
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
            "maxItems": 3,
        },
        "colors": {
            "type": "array",
            "items": {"type": "string", "enum": ids(taxonomia, "cor")},
            "description": (
                "One primary color first, then at most two substantial secondary "
                "colors of the target garment. Empty only for an ambiguous target."
            ),
            "maxItems": 3,
        },
        "additional_visual_attributes": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "Concrete visual attributes in English not represented by the "
                "taxonomy. These are never treated as measured market terms."
            ),
            "maxItems": 5,
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
        if dimensao == "categoria":
            continue
        itens = []
        for termo in taxonomia[dimensao]:
            pistas = termo["palavras_en"] or termo["rotulo"]
            itens.append("{} ({})".format(termo["id"], pistas))
        linhas.append("- {}: {}".format(
            CAMPOS_POR_DIMENSAO[dimensao], "; ".join(itens)))

    return """Outcome
Create a conservative, auditable prefill for one women's garment. A human will
confirm it. Use only visible pixels: no catalog title, filename, brand, likely
sale item, or hidden construction. Accuracy is more important than coverage.

1. Identify the target before classifying it
- A single isolated product garment is clear. A white or transparent-looking
  studio background is still a background and never part of the garment.
- In a worn look with several garments, use
  multiple_garments_target_clear only when one garment is unambiguously the
  visual subject. Evaluate target evidence in this order: completeness versus
  cropping; visible garment surface and vertical extent; centering and product
  detail; then distinctive styling or color contrast. Require at least two
  independent composition cues. A garment shown completely and occupying
  clearly more garment surface or vertical extent can be the target even when
  another garment is also visible. Distinctive color alone is never enough,
  but color together with centered construction details such as a waistband,
  belt, pockets, or closures can break a real compositional tie.
- A coordinated matching set is still multiple garments. If the image presents
  the top and bottom as peers and no single target dominates, use
  ambiguous_target rather than inventing one target or calling the set a
  jumpsuit. Matching color or material does not by itself make the target
  ambiguous: when one piece occupies roughly twice the visible garment surface
  or the other is materially cropped, select the dominant piece.
- If two or more garments are plausible targets, use ambiguous_target. Never
  guess which item the catalog or user intended.
- Ignore body, skin, hair, pose, background, props, footwear, bags, jewelry,
  and all non-target layers.

2. Classify visible construction, not a fashion synonym
- one_piece_no_separate_legs: one garment joins torso to a lower continuous
  panel (dress). Establish this torso-to-lower-panel continuity before using
  upper-body details: a sleeveless collared, button-front, or tie-front dress
  remains a dress when it continues into one lower panel.
- one_piece_with_separate_legs: one garment joins torso to two legs (jumpsuit
  or romper). A visible gap, separate waistband, overlapping hem, or other
  separation between top and bottom means two garments, never a jumpsuit.
- lower_continuous_panel: lower garment with a continuous exterior and no
  visible crotch or separate leg openings (skirt).
- lower_two_legs_short: lower garment ending around the knee or above, with
  visible evidence of two legs such as a crotch, inseam, central separation,
  or two leg openings (shorts or bermuda).
- lower_two_legs_long: lower garment with two legs extending below the knee
  (pants or trousers).
- upper_shirt_construction: upper garment with recognizable shirt construction.
  Strong evidence is a shirt collar together with a substantial front opening
  or placket and/or shirt cuffs. A tie-front shirt remains a shirt. Decorative
  buttons alone are insufficient. A tank, camisole, bustier, strap top, tee, or
  round-neck sleeveless top without a shirt placket is upper_other, even if a
  person informally calls every upper garment a shirt. A collar or buttons do
  not make a continuous one-piece dress a shirt.
- upper_outer_layer: jacket, coat, blazer, cardigan, or another garment visibly
  constructed as an outer layer. Blazer lapels, tailored shoulders, structured
  fronts, welt or flap pockets, and double-breasted construction are strong
  evidence. A cropped length or deep neckline does not turn a blazer into a
  blouse or top.
- upper_other: residual upper garment only after ruling out shirt construction
  and outerwear; includes blouse, top, tee, tank, cropped top, and bodysuit.
- A long shirt is not a dress unless pixels establish that the same garment
  continues below the pelvis as a lower panel meant to cover the lower body.
  A shirt collar plus a substantial placket and free tie-front tails remains
  shirt construction even at tunic length. Tie tails, side tails, or a short
  extension below a waist knot are not a dress panel. A dress needs a visibly
  continuous lower-body panel with its own width and hem below the pelvis.
- Sleeve length is never evidence for shorts. Use lower_two_legs_short only
  with visible crotch, inseam, or two independent leg openings/tubes. A center
  slit, wrap overlap, pleat, or two moving skirt panels is not enough. For a
  skort, label only the exterior construction actually visible.
- A visible midriff gap, top hem, separate waistband, or overlap at the waist
  proves separate upper and lower garments. A sharp color or texture change by
  itself does not prove separation in a color-blocked one-piece garment. A
  waist seam also does not prove separation. With no skin gap, separate top
  hem, waistband, or overlap, prefer one-piece construction when the lateral
  outline continues from a fitted bodice into one lower panel.

The application derives its eight category ids deterministically from
garment_structure. Do not perform a second semantic category guess.

3. Apply the closed taxonomy
Return only the stable ids below. Use pattern=liso when visibly plain and
not_visible only when pattern cannot be judged. Do not infer fiber composition
from appearance; fabrics may be empty. Length, silhouette, and waist may be
not_visible when inapplicable, cropped, or occluded. Colors are ordered: the
primary color first, followed by at most two secondary colors. A secondary
color must cover about 10 percent of the target or recur materially in its
print. Rank colors by visible surface area on the target garment only, never by
surface area of the whole image or by saturation. Ignore colors from another
garment, tiny trim, buttons, crystals, shadows, skin, and background. Map a
genuinely metallic gold, silver, bronze, or copper surface to outras_cores; do
not force it into amarelo_laranja, branco_cru, or cinza merely because of its
highlights. Metallic means the garment surface itself visibly behaves like
metal, foil, or mirror. Mustard, ochre, or golden-yellow velvet and fabric stay
amarelo_laranja even when they have reflective highlights, gold-colored trim,
sequins, or rhinestones.
Aesthetics has at most three ids. additional_visual_attributes has at most five
short, concrete English phrases not already represented below. Never repeat an
item or place a free-form guess in a taxonomy field. decision_evidence must
name only visible cues and must not reveal or assume catalog metadata.

4. Abstention contract
For ambiguous_target, return garment_structure=target_not_determinable;
pattern, length, silhouette, and waist=not_visible; and fabrics, aesthetics,
colors, and additional_visual_attributes=[] . For every other target_clarity,
choose a determinate structure and at least one color. decision_evidence is
still required for an ambiguous target and should state why no garment wins.

Taxonomy:
{}""".format("\n".join(linhas))


def hash_do_prompt(taxonomia):
    return hashlib.sha256(
        instrucoes(taxonomia).encode("utf-8")).hexdigest()


def montar_payload(imagem_em_data_url, taxonomia):
    return {
        "model": MODELO,
        "store": False,
        "reasoning": {"effort": "medium"},
        "max_output_tokens": 1200,
        "instructions": instrucoes(taxonomia),
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": (
                        "Determine whether one target garment is visually "
                        "identifiable, then analyze it under the contract."
                    ),
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


def selecionar_imagens(
        raiz, categorias, quantidade, semente=SEMENTE_PADRAO, excluir=None):
    """Distribui a diferenca de no maximo uma imagem entre categorias."""
    if quantidade < len(categorias):
        raise ValueError("A quantidade precisa cobrir todas as categorias.")
    base, resto = divmod(quantidade, len(categorias))
    gerador = random.Random(semente)
    selecionadas = []
    excluidas = {Path(caminho) for caminho in (excluir or ())}
    extensoes = {".jpg", ".jpeg", ".png", ".webp", ".heic"}

    for indice, categoria in enumerate(categorias):
        pasta = raiz / categoria
        arquivos = sorted(
            p for p in pasta.iterdir()
            if p.is_file() and p.suffix.lower() in extensoes and p not in excluidas
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


def selecionar_amostra_de_avaliacao(raiz, categorias, quantidade, semente):
    """As 300 sao holdout: nenhuma das 24 de calibracao pode reaparecer."""
    if quantidade <= 24:
        return selecionar_imagens(raiz, categorias, quantidade, semente)
    calibracao = selecionar_imagens(raiz, categorias, 24, semente)
    excluir = {caminho for _, caminho in calibracao}
    return selecionar_imagens(
        raiz, categorias, quantidade, semente, excluir=excluir)


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


def _validar_lista(nome, valor, permitidos=None, maximo=None):
    if not isinstance(valor, list) or any(not isinstance(item, str) for item in valor):
        raise ErroDaOpenAI("Campo {} nao e lista de strings".format(nome))
    if len(set(valor)) != len(valor):
        raise ErroDaOpenAI("Campo {} repete item".format(nome))
    if maximo is not None and len(valor) > maximo:
        raise ErroDaOpenAI("Campo {} excede {} itens".format(nome, maximo))
    if permitidos is not None and any(item not in permitidos for item in valor):
        raise ErroDaOpenAI("Campo {} contem id fora da taxonomia".format(nome))


def normalizar_analise(analise, taxonomia):
    """Valida invariantes que o JSON Schema nao consegue expressar sozinho."""
    if not isinstance(analise, dict):
        raise ErroDaOpenAI("Analise nao e objeto JSON")
    esperados = set(montar_schema(taxonomia)["properties"])
    if set(analise) != esperados:
        raise ErroDaOpenAI("Campos da analise nao correspondem ao contrato")

    clareza = analise["target_clarity"]
    estrutura = analise["garment_structure"]
    if clareza not in CLAREZAS_DO_ALVO:
        raise ErroDaOpenAI("target_clarity fora do contrato")
    if estrutura not in CATEGORIA_POR_ESTRUTURA:
        raise ErroDaOpenAI("garment_structure fora do contrato")

    escalares = {
        "pattern": ["not_visible"] + ids(taxonomia, "estampa"),
        "length": ["not_visible"] + ids(taxonomia, "comprimento"),
        "silhouette": ["not_visible"] + ids(taxonomia, "silhueta"),
        "waist": ["not_visible"] + ids(taxonomia, "cintura"),
    }
    for campo, permitidos in escalares.items():
        if analise[campo] not in permitidos:
            raise ErroDaOpenAI("Campo {} fora da taxonomia".format(campo))

    _validar_lista("fabrics", analise["fabrics"], ids(taxonomia, "tecido"), 3)
    _validar_lista(
        "aesthetics", analise["aesthetics"], ids(taxonomia, "estetica"), 3)
    _validar_lista("colors", analise["colors"], ids(taxonomia, "cor"), 3)
    _validar_lista(
        "decision_evidence",
        analise["decision_evidence"],
        maximo=4,
    )
    if not analise["decision_evidence"] or any(
            not item.strip()
            for item in analise["decision_evidence"]):
        raise ErroDaOpenAI("Evidencia de decisao vazia")
    _validar_lista(
        "additional_visual_attributes",
        analise["additional_visual_attributes"],
        maximo=5,
    )
    if any(not item.strip()
           for item in analise["additional_visual_attributes"]):
        raise ErroDaOpenAI("Atributo visual livre vazio")

    if clareza == "ambiguous_target":
        if estrutura != "target_not_determinable":
            raise ErroDaOpenAI("Alvo ambiguo precisa abster na estrutura")
        if any(analise[campo] != "not_visible" for campo in escalares):
            raise ErroDaOpenAI("Alvo ambiguo precisa abster nos escalares")
        if any(analise[campo] for campo in (
                "fabrics", "aesthetics", "colors",
                "additional_visual_attributes")):
            raise ErroDaOpenAI("Alvo ambiguo precisa devolver listas vazias")
    else:
        if estrutura == "target_not_determinable":
            raise ErroDaOpenAI("Alvo determinado precisa ter estrutura")
        if not analise["colors"]:
            raise ErroDaOpenAI("Alvo determinado precisa ter cor primaria")

    categorias = set(ids(taxonomia, "categoria"))
    categoria = CATEGORIA_POR_ESTRUTURA[estrutura]
    if categoria != "not_visible" and categoria not in categorias:
        raise ValueError("Estrutura aponta para categoria ausente da taxonomia")
    normalizada = dict(analise)
    normalizada["category"] = categoria
    return normalizada


def custo_estimado(uso):
    """Preco oficial do Luna consultado em 13/08/2026, em dolares."""
    entrada = int(uso.get("input_tokens", 0))
    detalhes = uso.get("input_tokens_details") or {}
    cache = int(detalhes.get("cached_tokens", 0))
    escrita_cache = int(detalhes.get("cache_write_tokens", 0))
    saida = int(uso.get("output_tokens", 0))
    entrada_normal = max(0, entrada - cache - escrita_cache)
    return (
        entrada_normal * 0.20
        + cache * 0.02
        + escrita_cache * 0.25
        + saida * 1.20
    ) / 1_000_000


def iniciar_jsonl(caminho):
    """Cria o artefato antes da primeira chamada e descarta rodada anterior."""
    if caminho is None:
        return
    caminho.parent.mkdir(parents=True, exist_ok=True)
    caminho.write_text("", encoding="utf-8")


def anexar_jsonl(caminho, resultado):
    """Persiste cada resposta paga imediatamente para permitir auditoria parcial."""
    if caminho is None:
        return
    with caminho.open("a", encoding="utf-8") as arquivo:
        arquivo.write(json.dumps(resultado, ensure_ascii=False) + "\n")
        arquivo.flush()
        os.fsync(arquivo.fileno())


def validar_portao_24(caminho, prompt_sha256=None):
    """Impede o benchmark pago antes do piso humano nas mesmas 24 imagens."""
    if not caminho.is_file():
        raise ValueError(
            "Benchmark de 300 bloqueado: portao humano das 24 ausente.")
    try:
        portao = json.loads(caminho.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as erro:
        raise ValueError("Portao humano das 24 invalido.") from erro
    if portao.get("prompt_version") != VERSAO_DO_PROMPT:
        raise ValueError("Portao humano pertence a outra versao do prompt.")
    if prompt_sha256 and portao.get("prompt_sha256") != prompt_sha256:
        raise ValueError("Portao humano pertence a outro conteudo de prompt.")
    if portao.get("sample_size") != 24:
        raise ValueError("Portao humano precisa cobrir exatamente 24 imagens.")
    categoria = float(portao.get("category_accuracy", 0))
    cor = float(portao.get("primary_color_accuracy", 0))
    if not portao.get("passed") or categoria < 0.80 or cor < 0.80:
        raise ValueError(
            "Benchmark de 300 bloqueado: categoria e cor precisam de 80%.")
    return portao


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
    hashes = {r.get("prompt_sha256") for r in resultados}
    hash_exibido = next(iter(hashes)) if len(hashes) == 1 else "inconsistente"
    linhas = [
        "## Luna — avaliacao estratificada",
        "",
        "- Modelo: `{}` (`store=false`, reasoning medium, image detail high)".format(MODELO),
        "- Prompt: `{}` (alvo -> estrutura -> categoria derivada)".format(
            VERSAO_DO_PROMPT),
        "- SHA-256 do prompt: `{}`".format(hash_exibido),
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
    parser.add_argument(
        "--portao-24",
        type=Path,
        default=raiz / "anexos" / "portao_luna_24.json",
    )
    return parser.parse_args()


def main():
    args = argumentos()
    chave = os.environ.get("OPENAI_API_KEY", "")
    if not chave:
        raise SystemExit("OPENAI_API_KEY ausente")
    if args.quantidade < 8 or args.quantidade > 300:
        raise SystemExit("--quantidade precisa estar entre 8 e 300")

    taxonomia = carregar_taxonomia(args.taxonomia)
    prompt_sha256 = hash_do_prompt(taxonomia)
    categorias = ids(taxonomia, "categoria")
    if args.quantidade > 24:
        validar_portao_24(args.portao_24, prompt_sha256)
    amostra = selecionar_amostra_de_avaliacao(
        args.cache, categorias, args.quantidade, args.semente)
    resultados = []
    custo = 0.0
    inicio_total = time.monotonic()
    iniciar_jsonl(args.saida)

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
                analise_bruta = json.loads(extrair_texto(resposta))
            except json.JSONDecodeError as erro:
                raise ErroDaOpenAI("output_text nao e JSON valido") from erro
            uso = resposta.get("usage") or {}
            custo += custo_estimado(uso)
            erro_de_validacao = None
            try:
                analise = normalizar_analise(analise_bruta, taxonomia)
            except ErroDaOpenAI as erro:
                # A chamada ja aconteceu e deve permanecer auditavel. Uma saida
                # fora do contrato conta como erro no portao, sem nova inferencia.
                analise = None
                erro_de_validacao = str(erro)
            resultado = {
                "sample_id": "S{:02d}".format(indice),
                "imagem": imagem.name,
                "categoria_catalogo": esperada,
                "prompt_version": VERSAO_DO_PROMPT,
                "prompt_sha256": prompt_sha256,
                "analysis": analise,
                "acertou_categoria": (
                    analise is not None and analise.get("category") == esperada
                ),
                "latencia_s": round(latencia, 3),
                "usage": uso,
                "response_id": resposta.get("id"),
                "model_resolved": resposta.get("model"),
            }
            if erro_de_validacao:
                resultado["validation_error"] = erro_de_validacao
                resultado["raw_analysis"] = analise_bruta
            resultados.append(resultado)
            anexar_jsonl(args.saida, resultado)
            categoria_luna = (
                analise.get("category") if analise is not None else "INVALIDA"
            )
            print(
                "[{}/{}] catalogo={} Luna={} {} | {:.1f}s | in={} out={} | {}".format(
                    indice, len(amostra), esperada, categoria_luna,
                    "OK" if resultado["acertou_categoria"] else "DIVERGIU",
                    latencia, uso.get("input_tokens", 0),
                    uso.get("output_tokens", 0), imagem.name),
                flush=True,
            )

    duracao_total = time.monotonic() - inicio_total
    if args.resumo:
        escrever_resumo(args.resumo, resultados, custo, duracao_total)

    acertos = sum(r["acertou_categoria"] for r in resultados)
    print("\nConcordancia de categoria: {}/{} ({:.1%})".format(
        acertos, len(resultados), acertos / len(resultados)))
    print("Custo estimado: US$ {:.6f}".format(custo))
    print("Duracao total: {:.1f}s".format(duracao_total))


if __name__ == "__main__":
    main()
