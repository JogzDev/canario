#!/usr/bin/env python3
"""Prepara uma revisão cega e autocontida dos fatos da Etiqueta.

O HTML contém somente o mínimo necessário para julgar cada extração: família,
faceta, valor candidato e um trecho curto da fonte. Identidade de produto,
marca, agregados, confiança do parser e conclusões editoriais ficam de fora.
O lote é determinístico e vinculado por hash ao pacote e à rubrica.
"""

from __future__ import annotations

import argparse
import datetime as dt
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import unicodedata


RAIZ = Path(__file__).resolve().parents[1]
CONTRATO_ENTRADA = "datadrobe_label_fact_pack_v2"
CONTRATO_FILA = "datadrobe_fact_review_batch_v1"
CONTRATO_SUBMISSAO = "datadrobe_fact_review_submission_v1"
VERSAO_MATERIALIZADOR = "etiqueta-materializer-v2"
VERSAO_RUBRICA = "label-fact-correctness-v1"
MAXIMO_BYTES_ENTRADA = 200 * 1024 * 1024
MAXIMO_FATOS = 1_000_000
MAXIMO_SUJEITOS_POR_LOTE = 250
MARCADOR_HTML = "__DATADROBE_LABEL_REVIEW_BATCH_JSON__"

FAMILIAS = {"fiber", "fabric_construction", "surface_finish"}
CAMPOS_FATO = {
    "id", "status", "requires_human_review", "family", "facet_id",
    "candidate_concept_id", "value", "source_excerpt",
}
CAMPOS_ITEM = {
    "source_item_external_id", "product_id", "brand_id", "observed_on",
    "source_snapshot_on", "content_sha256", "parser_confidence", "warnings",
    "abstained_fields", "facts",
}
CAMPOS_AGREGADO = {
    "family", "facet_id", "candidate_concept_id", "status",
    "product_count", "brand_count", "denominator_products",
    "share_among_dimension_observed_pct", "supporting_fact_ids",
}
CAMPOS_PACOTE = {
    "contract", "materializer_version", "parser_version", "cutoff_date",
    "input_sha256", "payload_sha256", "source_contract_sha256",
    "source_registry_sha256",
    "package_id", "generated_at", "repository_sha", "publication_status",
    "requires_human_review", "raw_content_persisted", "source_id",
    "authorization_sha256", "authorization_expires_on", "terms_version",
    "materializer_sha256", "parser_sha256", "population", "items",
    "aggregates",
}

RUBRICA = {
    "version": VERSAO_RUBRICA,
    "question": (
        "O trecho sustenta exatamente a família, a faceta e o valor do fato "
        "candidato, sem depender de contexto não exibido?"
    ),
    "decisions": {
        "supported_candidate": (
            "O trecho sustenta exatamente o fato candidato."
        ),
        "rejected_candidate": (
            "O trecho contradiz o fato ou não sustenta a família, faceta ou "
            "valor propostos."
        ),
        "insufficient_context": (
            "O trecho é insuficiente ou ambíguo para decidir com segurança."
        ),
    },
    "rules": [
        "Julgue somente o trecho exibido.",
        "Não infira marca, produto, tendência, participação ou intenção.",
        "Não corrija o fato neste formulário; uma correção cria um novo fato.",
        "Trabalhe sem consultar outro revisor até exportar sua submissão.",
    ],
}


class ErroDePreparacao(RuntimeError):
    """Falha fechada sem ecoar conteúdo da fonte."""


def _json_canonico(valor):
    try:
        return json.dumps(
            valor, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as erro:
        raise ErroDePreparacao("valor não é JSON canônico") from erro


def _sha256(valor):
    return hashlib.sha256(valor).hexdigest()


def _hash(valor, campo):
    if not isinstance(valor, str) or not re.fullmatch(r"[0-9a-f]{64}", valor):
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    return valor


def _texto(valor, campo, minimo=1, maximo=500):
    if not isinstance(valor, str) or not minimo <= len(valor) <= maximo:
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    if any(unicodedata.category(c).startswith("C") for c in valor):
        raise ErroDePreparacao("{} contém controle Unicode".format(campo))
    normalizado = unicodedata.normalize("NFC", valor)
    if normalizado != valor:
        raise ErroDePreparacao("{} não está em NFC".format(campo))
    return valor


def _data(valor, campo):
    if not isinstance(valor, str):
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    try:
        return dt.date.fromisoformat(valor).isoformat()
    except ValueError as erro:
        raise ErroDePreparacao("{} inválida".format(campo)) from erro


def _instante(valor, campo):
    if not isinstance(valor, str):
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    try:
        instante = dt.datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError as erro:
        raise ErroDePreparacao("{} inválido".format(campo)) from erro
    if instante.tzinfo is None:
        raise ErroDePreparacao("{} deve conter fuso".format(campo))
    return instante.astimezone(dt.timezone.utc).isoformat()


def _inteiro(valor, campo, minimo=0):
    if isinstance(valor, bool) or not isinstance(valor, int) or valor < minimo:
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    return valor


def _percentual(numerador, denominador):
    if not denominador:
        return None
    valor = Decimal(numerador) * Decimal(100) / Decimal(denominador)
    return float(valor.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def _id_fato(item_id, fato, parser_version):
    nucleo = {
        "source_item_external_id": item_id,
        "family": fato["family"],
        "facet_id": fato["facet_id"],
        "candidate_concept_id": fato["candidate_concept_id"],
        "value": fato["value"],
        "source_excerpt": fato["source_excerpt"],
        "transformation_version": parser_version,
    }
    return _sha256(_json_canonico(nucleo))


def _sujeito_do_fato(fato, parser_version):
    # Fatos idênticos em produtos diferentes compartilham uma única decisão
    # humana. A assinatura contém tudo o que o revisor vê e a versão da
    # transformação; nenhuma conclusão é transferida entre trechos distintos.
    nucleo = {
        "family": fato["family"],
        "facet_id": fato["facet_id"],
        "candidate_concept_id": fato["candidate_concept_id"],
        "value": fato["value"],
        "source_excerpt": fato["source_excerpt"],
        "transformation_version": parser_version,
    }
    return {
        "subject_id": _sha256(_json_canonico(nucleo)),
        "family": fato["family"],
        "facet_id": fato["facet_id"],
        "candidate_concept_id": fato["candidate_concept_id"],
        "value": fato["value"],
        "source_excerpt": fato["source_excerpt"],
    }


def _validar_lista_textos(valor, campo, maximo=200):
    if not isinstance(valor, list):
        raise ErroDePreparacao("{} fora do contrato".format(campo))
    textos = [_texto(item, campo, maximo=maximo) for item in valor]
    if textos != sorted(set(textos)):
        raise ErroDePreparacao("{} deve estar ordenado e sem repetição".format(
            campo))
    return textos


def _validar_populacao(populacao, itens, observados_por_familia):
    if not isinstance(populacao, dict):
        raise ErroDePreparacao("population fora do contrato")
    campos = {
        "segment", "eligibility", "eligible_products",
        "products_with_source_label", "products_without_source_label",
        "products_with_candidate_fact", "products_globally_abstained",
        "abstention_reasons", "warning_counts", "dimensions",
    }
    if set(populacao) != campos:
        raise ErroDePreparacao("population contém campos inesperados")
    if populacao["segment"] != "feminino_casual_br":
        raise ErroDePreparacao("population.segment fora do contrato")
    _texto(populacao["eligibility"], "population.eligibility", maximo=300)
    elegiveis = _inteiro(
        populacao["eligible_products"], "eligible_products", minimo=0)
    com_fonte = _inteiro(
        populacao["products_with_source_label"],
        "products_with_source_label", minimo=0)
    sem_fonte = _inteiro(
        populacao["products_without_source_label"],
        "products_without_source_label", minimo=0)
    com_fato = _inteiro(
        populacao["products_with_candidate_fact"],
        "products_with_candidate_fact", minimo=0)
    abstidos = _inteiro(
        populacao["products_globally_abstained"],
        "products_globally_abstained", minimo=0)
    if (com_fonte + sem_fonte != elegiveis or com_fato != len(itens)
            or com_fato > com_fonte or abstidos > elegiveis):
        raise ErroDePreparacao("contagens da população são incoerentes")
    for nome in ("abstention_reasons", "warning_counts"):
        mapa = populacao[nome]
        if (not isinstance(mapa, dict)
                or any(not isinstance(chave, str) or not chave
                       or isinstance(valor, bool) or not isinstance(valor, int)
                       or valor <= 0 for chave, valor in mapa.items())):
            raise ErroDePreparacao("{} fora do contrato".format(nome))
    dimensoes = populacao["dimensions"]
    if not isinstance(dimensoes, dict) or set(dimensoes) != FAMILIAS:
        raise ErroDePreparacao("population.dimensions fora do contrato")
    for familia in sorted(FAMILIAS):
        observados = len(observados_por_familia[familia])
        esperado = {
            "observed_products": observados,
            "abstained_products": elegiveis - observados,
            "coverage_of_eligible_pct": _percentual(observados, elegiveis),
            "denominator_definition": (
                "eligible products with at least one recognized fact in this "
                "family"
            ),
        }
        if dimensoes[familia] != esperado:
            raise ErroDePreparacao(
                "dimensão {} não corresponde aos fatos".format(familia))


def _validar_agregados(agregados, calculados, observados_por_familia):
    if not isinstance(agregados, list):
        raise ErroDePreparacao("aggregates deve ser lista")
    esperados = []
    for (familia, faceta), dados in sorted(calculados.items()):
        esperados.append({
            "family": familia,
            "facet_id": faceta,
            "candidate_concept_id": "{}_{}".format(familia, faceta),
            "status": "descriptive_baseline_only",
            "product_count": len(dados["products"]),
            "brand_count": len(dados["brands"]),
            "denominator_products": len(observados_por_familia[familia]),
            "share_among_dimension_observed_pct": _percentual(
                len(dados["products"]),
                len(observados_por_familia[familia])),
            "supporting_fact_ids": sorted(dados["facts"]),
        })
    for agregado in agregados:
        if not isinstance(agregado, dict) or set(agregado) != CAMPOS_AGREGADO:
            raise ErroDePreparacao("aggregate fora do contrato")
    if _json_canonico(agregados) != _json_canonico(esperados):
        raise ErroDePreparacao("aggregates não correspondem aos fatos")


def validar_pacote(pacote):
    if not isinstance(pacote, dict):
        raise ErroDePreparacao("pacote deve ser objeto")
    if set(pacote) != CAMPOS_PACOTE:
        raise ErroDePreparacao("pacote contém campos inesperados")
    if pacote.get("contract") != CONTRATO_ENTRADA:
        raise ErroDePreparacao("contrato de entrada desconhecido")
    if pacote.get("materializer_version") != VERSAO_MATERIALIZADOR:
        raise ErroDePreparacao("versão do materializador desconhecida")
    if pacote.get("publication_status") != "private_candidate_only":
        raise ErroDePreparacao("pacote não é candidato privado")
    if pacote.get("requires_human_review") is not True:
        raise ErroDePreparacao("pacote não exige revisão humana")
    if pacote.get("raw_content_persisted") is not False:
        raise ErroDePreparacao("pacote declara conteúdo bruto persistido")

    package_id = _hash(pacote.get("package_id"), "package_id")
    input_sha = _hash(pacote.get("input_sha256"), "input_sha256")
    payload_sha = _hash(pacote.get("payload_sha256"), "payload_sha256")
    payload = {
        "population": pacote.get("population"),
        "items": pacote.get("items"),
        "aggregates": pacote.get("aggregates"),
    }
    if _sha256(_json_canonico(payload)) != payload_sha:
        raise ErroDePreparacao("payload_sha256 não corresponde ao conteúdo")
    source_contract_sha = _hash(
        pacote.get("source_contract_sha256"), "source_contract_sha256")
    source_registry_sha = _hash(
        pacote.get("source_registry_sha256"), "source_registry_sha256")
    materializer_sha = _hash(
        pacote.get("materializer_sha256"), "materializer_sha256")
    parser_sha = _hash(pacote.get("parser_sha256"), "parser_sha256")
    if materializer_sha != _sha256(
            (RAIZ / "ferramentas" / "materializar_etiqueta_radar.py").read_bytes()):
        raise ErroDePreparacao("materializador local diverge do pacote")
    if parser_sha != _sha256(
            (RAIZ / "coletor" / "etiqueta_radar.py").read_bytes()):
        raise ErroDePreparacao("parser local diverge do pacote")

    parser_version = _texto(
        pacote.get("parser_version"), "parser_version", maximo=120)
    cutoff = _data(pacote.get("cutoff_date"), "cutoff_date")
    _instante(pacote.get("generated_at"), "generated_at")
    repository_sha = pacote.get("repository_sha")
    if (repository_sha is not None
            and (not isinstance(repository_sha, str)
                 or not re.fullmatch(r"[0-9a-f]{7,64}", repository_sha))):
        raise ErroDePreparacao("repository_sha fora do contrato")
    source_id = _texto(pacote.get("source_id"), "source_id", maximo=80)
    if source_id != "datadrobe_curadoria_interna":
        raise ErroDePreparacao("source_id fora do contrato")

    identidade = {
        "contract": CONTRATO_ENTRADA,
        "materializer_version": VERSAO_MATERIALIZADOR,
        "parser_version": parser_version,
        "cutoff_date": cutoff,
        "input_sha256": input_sha,
        "payload_sha256": payload_sha,
        "source_contract_sha256": source_contract_sha,
        "source_registry_sha256": source_registry_sha,
    }
    if _sha256(_json_canonico(identidade)) != package_id:
        raise ErroDePreparacao("package_id não corresponde à identidade")

    # O hash declarado não basta: um atacante poderia alterar o registro, os
    # hashes e o package_id em conjunto. Reabrir a governança local pelo mesmo
    # portão do materializador prova que este checkout ainda reconhece a fonte.
    from materializar_etiqueta_radar import (
        ErroDeMaterializacao, carregar_contrato_da_fonte)

    try:
        contrato_atual = carregar_contrato_da_fonte(
            RAIZ / "anexos" / "fontes_radar.csv", dt.date.fromisoformat(cutoff))
    except ErroDeMaterializacao as erro:
        raise ErroDePreparacao("governança local bloqueou a fonte") from erro
    esperados_fonte = {
        "source_id": contrato_atual["source_id"],
        "source_contract_sha256": contrato_atual["source_contract_sha256"],
        "source_registry_sha256": contrato_atual["source_registry_sha256"],
        "authorization_sha256": contrato_atual["authorization_sha256"],
        "authorization_expires_on": contrato_atual[
            "authorization_expires_on"],
        "terms_version": contrato_atual["terms_version"],
    }
    recebidos_fonte = {
        "source_id": source_id,
        "source_contract_sha256": source_contract_sha,
        "source_registry_sha256": source_registry_sha,
        "authorization_sha256": _hash(
            pacote.get("authorization_sha256"), "authorization_sha256"),
        "authorization_expires_on": _data(
            pacote.get("authorization_expires_on"),
            "authorization_expires_on"),
        "terms_version": _texto(
            pacote.get("terms_version"), "terms_version", maximo=160),
    }
    if recebidos_fonte != esperados_fonte:
        raise ErroDePreparacao("governança da fonte diverge do pacote")

    itens = pacote.get("items")
    if not isinstance(itens, list):
        raise ErroDePreparacao("items deve ser lista")
    fatos = []
    ids_itens = set()
    ids_fatos = set()
    observados_por_familia = {familia: set() for familia in FAMILIAS}
    agregados = {}
    for numero_item, item in enumerate(itens, 1):
        if not isinstance(item, dict) or set(item) != CAMPOS_ITEM:
            raise ErroDePreparacao(
                "item {} fora do contrato".format(numero_item))
        item_id = _texto(
            item.get("source_item_external_id"),
            "source_item_external_id", maximo=500)
        if item_id in ids_itens:
            raise ErroDePreparacao("source_item_external_id repetido")
        ids_itens.add(item_id)
        produto_id = _inteiro(item.get("product_id"), "product_id", minimo=1)
        marca_id = _inteiro(item.get("brand_id"), "brand_id", minimo=1)
        _data(item.get("observed_on"), "observed_on")
        _data(item.get("source_snapshot_on"), "source_snapshot_on")
        _hash(item.get("content_sha256"), "content_sha256")
        confianca = item.get("parser_confidence")
        if not isinstance(confianca, str) or confianca not in {"baixa", "media", "alta"}:
            raise ErroDePreparacao("parser_confidence fora do contrato")
        _validar_lista_textos(item.get("warnings"), "warnings")
        _validar_lista_textos(
            item.get("abstained_fields"), "abstained_fields", maximo=80)
        fatos_do_item = item.get("facts")
        if not isinstance(fatos_do_item, list) or not fatos_do_item:
            raise ErroDePreparacao("item sem fatos candidatos")

        for fato in fatos_do_item:
            if not isinstance(fato, dict) or set(fato) != CAMPOS_FATO:
                raise ErroDePreparacao("fato fora do contrato")
            fato_id = _hash(fato.get("id"), "fact.id")
            if fato_id in ids_fatos:
                raise ErroDePreparacao("fact.id repetido")
            ids_fatos.add(fato_id)
            if (fato.get("status") != "candidate_fact"
                    or fato.get("requires_human_review") is not True):
                raise ErroDePreparacao("fato não é candidato revisável")
            familia = fato.get("family")
            if not isinstance(familia, str) or familia not in FAMILIAS:
                raise ErroDePreparacao("family fora do contrato")
            faceta = _texto(fato.get("facet_id"), "facet_id", maximo=80)
            candidato = _texto(
                fato.get("candidate_concept_id"),
                "candidate_concept_id", maximo=180)
            if candidato != "{}_{}".format(familia, faceta):
                raise ErroDePreparacao("candidate_concept_id divergente")
            valor = fato.get("value")
            if not isinstance(valor, dict) or len(_json_canonico(valor)) > 4096:
                raise ErroDePreparacao("fact.value fora do contrato")
            trecho = _texto(
                fato.get("source_excerpt"), "source_excerpt", maximo=500)
            if _id_fato(item_id, fato, parser_version) != fato_id:
                raise ErroDePreparacao("fact.id não corresponde ao conteúdo")
            fatos.append({
                "fact_id": fato_id,
                "product_id": produto_id,
                "brand_id": marca_id,
                "subject": _sujeito_do_fato(fato, parser_version),
            })
            observados_por_familia[familia].add(produto_id)
            acumulado = agregados.setdefault((familia, faceta), {
                "products": set(), "brands": set(), "facts": set(),
            })
            acumulado["products"].add(produto_id)
            acumulado["brands"].add(marca_id)
            acumulado["facts"].add(fato_id)
            if len(fatos) > MAXIMO_FATOS:
                raise ErroDePreparacao("pacote excede o teto de fatos")

    _validar_populacao(
        pacote.get("population"), itens, observados_por_familia)
    _validar_agregados(
        pacote.get("aggregates"), agregados, observados_por_familia)
    return {
        "package_id": package_id,
        "package_content_sha256": _sha256(_json_canonico(pacote)),
        "input_sha256": input_sha,
        "materializer_sha256": materializer_sha,
        "parser_sha256": parser_sha,
        "parser_version": parser_version,
        "source_id": source_id,
        "facts": fatos,
    }


def carregar_pacote(caminho):
    caminho = Path(caminho)
    if caminho.stat().st_size > MAXIMO_BYTES_ENTRADA:
        raise ErroDePreparacao("arquivo excede o teto de bytes")
    with caminho.open(encoding="utf-8") as arquivo:
        return json.load(arquivo)


def _preparar_fila_validada(origem):
    unicos = {}
    for fato in origem["facts"]:
        sujeito = fato["subject"]
        anterior = unicos.setdefault(sujeito["subject_id"], sujeito)
        if _json_canonico(anterior) != _json_canonico(sujeito):
            raise ErroDePreparacao("colisão de subject_id")
    if len(unicos) > MAXIMO_SUJEITOS_POR_LOTE:
        raise ErroDePreparacao(
            "pacote exige {} sujeitos únicos; o piloto aceita no máximo {} "
            "e não cria uma página impraticável".format(
                len(unicos), MAXIMO_SUJEITOS_POR_LOTE))
    ordenados = sorted(
        unicos.values(),
        key=lambda fato: _sha256(
            (origem["package_id"] + ":" + fato["subject_id"]).encode("ascii")),
    )
    nucleo = {
        "contract": CONTRATO_FILA,
        "submission_contract": CONTRATO_SUBMISSAO,
        "source_contract": CONTRATO_ENTRADA,
        "source_package_id": origem["package_id"],
        "source_package_content_sha256": origem["package_content_sha256"],
        "source_input_sha256": origem["input_sha256"],
        "source_materializer_sha256": origem["materializer_sha256"],
        "source_parser_sha256": origem["parser_sha256"],
        "source_parser_version": origem["parser_version"],
        "source_id": origem["source_id"],
        "rubric": RUBRICA,
        "rubric_sha256": _sha256(_json_canonico(RUBRICA)),
        "review_mode": "two_independent_reviewers_then_independent_adjudicator",
        "blind_to": [
            "aggregate_counts", "brand_identity", "parser_confidence",
            "product_identity", "shares", "trend_direction",
            "editorial_conclusion", "other_reviewer_decisions",
        ],
        "subject_count": len(ordenados),
        "subjects": ordenados,
    }
    return {**nucleo, "batch_id": _sha256(_json_canonico(nucleo))}


def preparar_fila(pacote):
    return _preparar_fila_validada(validar_pacote(pacote))


def _json_seguro_para_script(valor):
    texto = json.dumps(
        valor, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    return (texto.replace("<", "\\u003c")
                 .replace(">", "\\u003e")
                 .replace("&", "\\u0026")
                 .replace("\u2028", "\\u2028")
                 .replace("\u2029", "\\u2029"))


def renderizar_html(fila, template):
    html = Path(template).read_text(encoding="utf-8")
    if html.count(MARCADOR_HTML) != 1:
        raise ErroDePreparacao("template sem marcador único do lote")
    return html.replace(MARCADOR_HTML, _json_seguro_para_script(fila))


def escrever_texto_atomico(caminho, texto):
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
    except Exception:
        try:
            os.close(descritor)
        except OSError:
            pass
        try:
            os.unlink(temporario)
        except FileNotFoundError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pacote", type=Path, required=True)
    parser.add_argument("--saida", type=Path, required=True)
    parser.add_argument(
        "--template", type=Path,
        default=RAIZ / "ferramentas" / "revisao_etiqueta_radar.html")
    args = parser.parse_args()
    destinos = {args.pacote.resolve(), args.template.resolve()}
    if args.saida.resolve() in destinos:
        raise SystemExit("a saída não pode sobrescrever uma entrada")
    try:
        fila = preparar_fila(carregar_pacote(args.pacote))
        html = renderizar_html(fila, args.template)
        escrever_texto_atomico(args.saida, html)
    except (ErroDePreparacao, OSError, ValueError,
            json.JSONDecodeError) as erro:
        raise SystemExit("revisão bloqueada: {}".format(erro)) from erro
    print("Lote cego: {} fatos; {}".format(
        fila["subject_count"], fila["batch_id"]))
    print("Agregados, marcas, produtos e confiança expostos ao revisor: 0")


if __name__ == "__main__":
    main()
