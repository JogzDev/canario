#!/usr/bin/env python3
"""Materializa um pacote factual privado a partir das etiquetas do catálogo.

O processo é determinístico e local. A composição bruta existe somente na
entrada transitória; o artefato preserva hashes, pequenos trechos-fonte e fatos
candidatos. Nada é promovido a conceito, evidência revisada ou leitura pública.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import unicodedata
from zoneinfo import ZoneInfo


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "coletor"))
from etiqueta_radar import VERSAO_PARSER, analisar_etiqueta  # noqa: E402
import supabase_rest  # noqa: E402


CONTRATO_ENTRADA = "datadrobe_label_source_rows_v1"
CONTRATO_SAIDA = "datadrobe_label_fact_pack_v2"
VERSAO_MATERIALIZADOR = "etiqueta-materializer-v2"
FONTE_ID = "datadrobe_curadoria_interna"
SEGMENTO = "feminino_casual_br"
FUSO_OPERACIONAL = ZoneInfo("America/Sao_Paulo")
FRESCOR_DIAS = 7
JANELA_SNAPSHOT_DIAS = 21
MAXIMO_LINHAS = 250_000
MAXIMO_BYTES_ENTRADA = 200 * 1024 * 1024
MAXIMO_CARACTERES_COMPOSICAO = 100_000
PAGINA_SUPABASE = 1_000

CAMPOS_LINHA = {
    "produto_id", "marca_id", "segmento", "ofertavel",
    "ultimo_avistamento_em", "snapshot_data", "composicao",
}

FAMILIAS = {
    "composicao": "fiber",
    "construcao": "fabric_construction",
    "acabamento": "surface_finish",
}


class ErroDeMaterializacao(RuntimeError):
    """Falha fechada sem ecoar a composição recebida."""


def _json_canonico(valor) -> bytes:
    return json.dumps(
        valor, ensure_ascii=False, sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _sha256(valor: bytes) -> str:
    return hashlib.sha256(valor).hexdigest()


def _repository_sha():
    valor = os.environ.get("GITHUB_SHA", "").strip().lower()
    return valor if re.fullmatch(r"[0-9a-f]{7,64}", valor) else None


def _data_iso(valor, campo, linha):
    if not isinstance(valor, str) or not re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}", valor):
        raise ErroDeMaterializacao(
            "linha {}: {} fora de AAAA-MM-DD".format(linha, campo))
    try:
        return dt.date.fromisoformat(valor)
    except ValueError as erro:
        raise ErroDeMaterializacao(
            "linha {}: {} inválida".format(linha, campo)) from erro


def _inteiro_positivo(valor, campo, linha):
    if isinstance(valor, bool) or not isinstance(valor, int) or valor <= 0:
        raise ErroDeMaterializacao(
            "linha {}: {} deve ser inteiro positivo".format(linha, campo))
    return valor


def validar_linhas(linhas, data_corte):
    if not isinstance(linhas, list):
        raise ErroDeMaterializacao("rows deve ser uma lista")
    if len(linhas) > MAXIMO_LINHAS:
        raise ErroDeMaterializacao("entrada excede o teto de linhas")

    validadas = []
    produtos = set()
    for numero, bruta in enumerate(linhas, start=1):
        if not isinstance(bruta, dict) or set(bruta) != CAMPOS_LINHA:
            raise ErroDeMaterializacao(
                "linha {}: campos fora do contrato".format(numero))
        produto_id = _inteiro_positivo(
            bruta["produto_id"], "produto_id", numero)
        if produto_id in produtos:
            raise ErroDeMaterializacao(
                "linha {}: produto_id repetido".format(numero))
        produtos.add(produto_id)
        marca_id = _inteiro_positivo(bruta["marca_id"], "marca_id", numero)
        if bruta["segmento"] != SEGMENTO:
            raise ErroDeMaterializacao(
                "linha {}: segmento fora do pacote".format(numero))
        if bruta["ofertavel"] is not True:
            raise ErroDeMaterializacao(
                "linha {}: produto não ofertável".format(numero))

        ultimo = _data_iso(
            bruta["ultimo_avistamento_em"],
            "ultimo_avistamento_em", numero)
        if not data_corte - dt.timedelta(days=FRESCOR_DIAS) <= ultimo <= data_corte:
            raise ErroDeMaterializacao(
                "linha {}: último avistamento fora da janela".format(numero))

        composicao = bruta["composicao"]
        snapshot = bruta["snapshot_data"]
        if composicao is None:
            if snapshot is not None:
                raise ErroDeMaterializacao(
                    "linha {}: snapshot sem composição".format(numero))
            snapshot_data = None
        else:
            if not isinstance(composicao, str):
                raise ErroDeMaterializacao(
                    "linha {}: composição fora do contrato".format(numero))
            if len(composicao) > MAXIMO_CARACTERES_COMPOSICAO:
                raise ErroDeMaterializacao(
                    "linha {}: composição excede o teto de entrada".format(
                        numero))
            composicao = unicodedata.normalize("NFC", composicao)
            snapshot_data = _data_iso(snapshot, "snapshot_data", numero)
            if not data_corte - dt.timedelta(
                    days=JANELA_SNAPSHOT_DIAS) <= snapshot_data <= data_corte:
                raise ErroDeMaterializacao(
                    "linha {}: snapshot fora da janela".format(numero))

        validadas.append({
            "produto_id": produto_id,
            "marca_id": marca_id,
            "segmento": SEGMENTO,
            "ofertavel": True,
            "ultimo_avistamento_em": ultimo.isoformat(),
            "snapshot_data": (
                snapshot_data.isoformat() if snapshot_data else None),
            "composicao": composicao,
        })
    return sorted(validadas, key=lambda item: item["produto_id"])


def carregar_entrada(caminho):
    caminho = Path(caminho)
    if caminho.stat().st_size > MAXIMO_BYTES_ENTRADA:
        raise ErroDeMaterializacao("arquivo de entrada excede o teto de bytes")
    with caminho.open(encoding="utf-8") as arquivo:
        entrada = json.load(arquivo)
    if not isinstance(entrada, dict) or set(entrada) != {
            "contract", "cutoff_date", "rows"}:
        raise ErroDeMaterializacao("envelope de entrada fora do contrato")
    if entrada["contract"] != CONTRATO_ENTRADA:
        raise ErroDeMaterializacao("contrato de entrada desconhecido")
    data_corte = _data_iso(entrada["cutoff_date"], "cutoff_date", 0)
    return validar_linhas(entrada["rows"], data_corte), data_corte


def carregar_do_supabase():
    if not supabase_rest.configurado():
        raise ErroDeMaterializacao(
            "SUPABASE_URL ou SUPABASE_SECRET_KEY ausente")
    # PostgREST normalmente limita respostas a mil linhas. Paginar pelo ID é
    # parte do contrato: aceitar só a primeira página transformaria cobertura
    # truncada em uma estatística aparentemente válida.
    data_corte = dt.datetime.now(FUSO_OPERACIONAL).date()
    linhas = []
    ultimo_id = 0
    while True:
        resposta = supabase_rest.rpc(
            "exportar_linhas_etiqueta_13", {
                "p_data_corte": data_corte.isoformat(),
                "p_after_id": ultimo_id,
                "p_limit": PAGINA_SUPABASE,
            }, tentativas=1)
        if not isinstance(resposta, list):
            raise ErroDeMaterializacao("RPC devolveu envelope fora do contrato")
        if len(resposta) > PAGINA_SUPABASE:
            raise ErroDeMaterializacao("RPC excedeu o tamanho de página")
        ids_da_pagina = []
        for numero, linha in enumerate(resposta, start=len(linhas) + 1):
            if not isinstance(linha, dict) or "data_corte" not in linha:
                raise ErroDeMaterializacao(
                    "linha {} da RPC fora do contrato".format(numero))
            if linha["data_corte"] != data_corte.isoformat():
                raise ErroDeMaterializacao(
                    "RPC devolveu data de corte divergente")
            copia = dict(linha)
            copia.pop("data_corte")
            produto_id = copia.get("produto_id")
            if (isinstance(produto_id, bool)
                    or not isinstance(produto_id, int)
                    or produto_id <= ultimo_id):
                raise ErroDeMaterializacao(
                    "RPC perdeu ordenação estrita por produto_id")
            ids_da_pagina.append(produto_id)
            ultimo_id = produto_id
            linhas.append(copia)
            if len(linhas) > MAXIMO_LINHAS:
                raise ErroDeMaterializacao("entrada excede o teto de linhas")
        if len(resposta) < PAGINA_SUPABASE:
            break
        if not ids_da_pagina:
            raise ErroDeMaterializacao("paginação da RPC não avançou")
    return validar_linhas(linhas, data_corte), data_corte


def carregar_contrato_da_fonte(caminho, data_corte):
    # Reutiliza o portão integral do Scout: qualquer linha inválida no registro
    # bloqueia também a materialização interna.
    sys.path.insert(0, str(RAIZ / "ferramentas"))
    from pesquisar_radar_luna import (  # noqa: E402
        CAMPOS_DO_REGISTRO, carregar_registro_fontes,
    )

    registro = carregar_registro_fontes(caminho, hoje=data_corte)
    validada = next((f for f in registro if f["id"] == FONTE_ID), None)
    if (validada is None or not validada["ativa"]
            or validada["status"] != "green"
            or validada["tier"] != "T0"
            or validada["metodo"] != "curadoria_interna"
            or validada["url_scope"] != "internal"
            or validada["display_rights"] != "own_content"):
        raise ErroDeMaterializacao("fonte interna não está autorizada")

    with open(caminho, encoding="utf-8", newline="") as arquivo:
        leitor = csv.DictReader(arquivo)
        if tuple(leitor.fieldnames or ()) != CAMPOS_DO_REGISTRO:
            raise ErroDeMaterializacao("registro de fontes fora do contrato")
        bruta = next((linha for linha in leitor
                      if linha.get("id") == FONTE_ID), None)
    if bruta is None or set(bruta) != set(CAMPOS_DO_REGISTRO):
        raise ErroDeMaterializacao("fonte interna ausente do registro")

    termos = Path(caminho).resolve().parent.parent / bruta["termos_url"]
    if not termos.is_file():
        raise ErroDeMaterializacao("contrato local da fonte não existe")
    autorizacao_sha = _sha256(termos.read_bytes())
    if autorizacao_sha != bruta["autorizacao_sha256"]:
        raise ErroDeMaterializacao("hash autorizador da fonte interna divergiu")

    return {
        "source_id": FONTE_ID,
        "source_contract_sha256": _sha256(_json_canonico(bruta)),
        "source_registry_sha256": _sha256(Path(caminho).read_bytes()),
        "authorization_sha256": autorizacao_sha,
        "terms_version": bruta["termos_versao"],
        "authorization_expires_on": bruta["autorizacao_expira_em"],
        "raw_retention_days": int(bruta["retencao_dias"]),
        "fact_retention_days": int(bruta["retencao_fatos_dias"]),
    }


def _identidade_do_item(linha):
    return "product:{}:composition:{}".format(
        linha["produto_id"], linha["snapshot_data"])


def _fato(item_id, familia, faceta, valor, trecho):
    trecho = unicodedata.normalize("NFC", trecho).strip()
    if (not 1 <= len(trecho) <= 500
            or any(unicodedata.category(c).startswith("C") for c in trecho)):
        raise ErroDeMaterializacao("trecho-fonte fora do contrato")
    candidato = "{}_{}".format(familia, faceta)
    nucleo = {
        "source_item_external_id": item_id,
        "family": familia,
        "facet_id": faceta,
        "candidate_concept_id": candidato,
        "value": valor,
        "source_excerpt": trecho,
        "transformation_version": VERSAO_PARSER,
    }
    return {
        "id": _sha256(_json_canonico(nucleo)),
        "status": "candidate_fact",
        "requires_human_review": True,
        "family": familia,
        "facet_id": faceta,
        "candidate_concept_id": candidato,
        "value": valor,
        "source_excerpt": trecho,
    }


def _fatos_do_resultado(item_id, resultado):
    fatos = []
    for item in resultado["composicao"]:
        fatos.append(_fato(
            item_id, FAMILIAS["composicao"], item["fibra_id"],
            {"percentage": item["percentual"], "part_id": item["parte_id"]},
            item["trecho_fonte"],
        ))
    for campo in ("construcao", "acabamento"):
        for item in resultado[campo]:
            fatos.append(_fato(
                item_id, FAMILIAS[campo], item["item_id"], {},
                item["trecho_fonte"],
            ))
    return sorted(fatos, key=lambda fato: (
        fato["family"], fato["facet_id"],
        _json_canonico(fato["value"]), fato["id"],
    ))


def _percentual(numerador, denominador):
    if not denominador:
        return None
    valor = Decimal(numerador) * Decimal(100) / Decimal(denominador)
    return float(valor.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def materializar(linhas, data_corte, contrato_fonte, gerado_em=None):
    linhas = validar_linhas(linhas, data_corte)
    gerado_em = gerado_em or dt.datetime.now(dt.timezone.utc)
    if gerado_em.tzinfo is None:
        raise TypeError("gerado_em deve ter fuso")

    entrada_sha = _sha256(_json_canonico(linhas))
    itens = []
    abstencoes = {}
    avisos = {}
    com_etiqueta = 0
    com_fato = 0
    abstidos_globalmente = 0
    observados_por_familia = {familia: set() for familia in FAMILIAS.values()}
    agregados = {}

    for linha in linhas:
        texto = linha["composicao"]
        if isinstance(texto, str) and texto.strip():
            com_etiqueta += 1
        resultado = analisar_etiqueta(texto)
        if resultado["abstencao"]:
            abstidos_globalmente += 1
        for motivo in resultado["motivos_abstencao"]:
            abstencoes[motivo] = abstencoes.get(motivo, 0) + 1
        for aviso in resultado["avisos"]:
            avisos[aviso] = avisos.get(aviso, 0) + 1

        if linha["snapshot_data"] is None:
            continue
        item_id = _identidade_do_item(linha)
        fatos = _fatos_do_resultado(item_id, resultado)
        if not fatos:
            continue
        com_fato += 1
        for fato in fatos:
            familia = fato["family"]
            observados_por_familia[familia].add(linha["produto_id"])
            chave = (familia, fato["facet_id"])
            agregado = agregados.setdefault(chave, {
                "produtos": set(), "marcas": set(), "fatos": set(),
            })
            agregado["produtos"].add(linha["produto_id"])
            agregado["marcas"].add(linha["marca_id"])
            agregado["fatos"].add(fato["id"])

        itens.append({
            "source_item_external_id": item_id,
            "product_id": linha["produto_id"],
            "brand_id": linha["marca_id"],
            "observed_on": linha["ultimo_avistamento_em"],
            "source_snapshot_on": linha["snapshot_data"],
            "content_sha256": _sha256(texto.encode("utf-8")),
            "parser_confidence": resultado["confianca"],
            "warnings": sorted(resultado["avisos"]),
            "abstained_fields": sorted(resultado["campos_abstidos"]),
            "facts": fatos,
        })

    agregados_publicos = []
    for (familia, faceta), agregado in sorted(agregados.items()):
        denominador = len(observados_por_familia[familia])
        agregados_publicos.append({
            "family": familia,
            "facet_id": faceta,
            "candidate_concept_id": "{}_{}".format(familia, faceta),
            "status": "descriptive_baseline_only",
            "product_count": len(agregado["produtos"]),
            "brand_count": len(agregado["marcas"]),
            "denominator_products": denominador,
            "share_among_dimension_observed_pct": _percentual(
                len(agregado["produtos"]), denominador),
            "supporting_fact_ids": sorted(agregado["fatos"]),
        })

    dimensoes = {}
    for familia in sorted(observados_por_familia):
        observados = len(observados_por_familia[familia])
        dimensoes[familia] = {
            "observed_products": observados,
            "abstained_products": len(linhas) - observados,
            "coverage_of_eligible_pct": _percentual(observados, len(linhas)),
            "denominator_definition": (
                "eligible products with at least one recognized fact in this "
                "family"
            ),
        }

    population = {
        "segment": SEGMENTO,
        "eligibility": (
            "currently offerable and observed no more than 7 days before "
            "the cutoff"
        ),
        "eligible_products": len(linhas),
        "products_with_source_label": com_etiqueta,
        "products_without_source_label": len(linhas) - com_etiqueta,
        "products_with_candidate_fact": com_fato,
        "products_globally_abstained": abstidos_globalmente,
        "abstention_reasons": dict(sorted(abstencoes.items())),
        "warning_counts": dict(sorted(avisos.items())),
        "dimensions": dimensoes,
    }
    payload = {
        "population": population,
        "items": sorted(itens, key=lambda item: item["product_id"]),
        "aggregates": agregados_publicos,
    }
    identidade = {
        "contract": CONTRATO_SAIDA,
        "materializer_version": VERSAO_MATERIALIZADOR,
        "parser_version": VERSAO_PARSER,
        "cutoff_date": data_corte.isoformat(),
        "input_sha256": entrada_sha,
        "payload_sha256": _sha256(_json_canonico(payload)),
        "source_contract_sha256": contrato_fonte[
            "source_contract_sha256"],
        "source_registry_sha256": contrato_fonte[
            "source_registry_sha256"],
    }
    pacote = {
        **identidade,
        "package_id": _sha256(_json_canonico(identidade)),
        "generated_at": gerado_em.astimezone(dt.timezone.utc).isoformat(),
        "repository_sha": _repository_sha(),
        "publication_status": "private_candidate_only",
        "requires_human_review": True,
        "raw_content_persisted": False,
        "source_id": contrato_fonte["source_id"],
        "authorization_sha256": contrato_fonte["authorization_sha256"],
        "authorization_expires_on": contrato_fonte[
            "authorization_expires_on"],
        "terms_version": contrato_fonte["terms_version"],
        "materializer_sha256": _sha256(Path(__file__).read_bytes()),
        "parser_sha256": _sha256(
            (RAIZ / "coletor" / "etiqueta_radar.py").read_bytes()),
        **payload,
    }
    return pacote


def escrever_json_atomico(caminho, valor):
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    descritor, temporario = tempfile.mkstemp(
        prefix=caminho.name + ".", suffix=".tmp", dir=str(caminho.parent))
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            json.dump(valor, arquivo, ensure_ascii=False, indent=2)
            arquivo.write("\n")
            arquivo.flush()
            os.fsync(arquivo.fileno())
        os.replace(temporario, caminho)
    except BaseException:
        try:
            os.unlink(temporario)
        except FileNotFoundError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    origem = parser.add_mutually_exclusive_group(required=True)
    origem.add_argument("--entrada", type=Path)
    origem.add_argument(
        "--supabase", action="store_true",
        help="lê a RPC privada e somente-leitura exportar_linhas_etiqueta_13")
    parser.add_argument(
        "--fontes", type=Path, default=RAIZ / "anexos" / "fontes_radar.csv")
    parser.add_argument(
        "--saida", type=Path, default=Path("radar-etiqueta-facts.json"))
    args = parser.parse_args()

    entradas = {Path(args.fontes).resolve()}
    if args.entrada:
        entradas.add(Path(args.entrada).resolve())
    if Path(args.saida).resolve() in entradas:
        raise SystemExit("a saída não pode sobrescrever a entrada ou o registro")

    try:
        if args.supabase:
            linhas, data_corte = carregar_do_supabase()
        else:
            linhas, data_corte = carregar_entrada(args.entrada)
        contrato = carregar_contrato_da_fonte(args.fontes, data_corte)
        pacote = materializar(linhas, data_corte, contrato)
        escrever_json_atomico(args.saida, pacote)
    except (ErroDeMaterializacao, ValueError, json.JSONDecodeError) as erro:
        raise SystemExit("materialização bloqueada: {}".format(erro)) from erro

    print(
        "Etiqueta privada: {} produtos elegíveis, {} com fatos; pacote {}".
        format(
            pacote["population"]["eligible_products"],
            pacote["population"]["products_with_candidate_fact"],
            pacote["package_id"],
        )
    )


if __name__ == "__main__":
    main()
