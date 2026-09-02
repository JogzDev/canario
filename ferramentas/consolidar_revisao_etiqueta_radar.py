#!/usr/bin/env python3
"""Consolida duas revisões cegas e uma adjudicação independente da Etiqueta.

O processo recalcula os agregados somente a partir dos fatos confirmados. Ele
não promove conceito, não grava evidência e não publica leitura de mercado.
Quando os revisores divergem, produz um novo HTML que contém exclusivamente os
fatos divergentes e esconde as escolhas anteriores do adjudicador.
"""

from __future__ import annotations

import argparse
import datetime as dt
from decimal import Decimal, ROUND_HALF_UP
import json
import os
from pathlib import Path
import re
import tempfile
import unicodedata

from preparar_revisao_etiqueta_radar import (
    CONTRATO_ENTRADA,
    ErroDePreparacao,
    RUBRICA,
    _preparar_fila_validada,
    _json_canonico,
    _sha256,
    carregar_pacote,
    escrever_texto_atomico,
    renderizar_html,
    validar_pacote,
)


CONTRATO_COMPARACAO = "datadrobe_fact_review_comparison_v1"
CONTRATO_ADJUDICACAO = "datadrobe_fact_adjudication_batch_v1"
CONTRATO_SUBMISSAO_ADJUDICACAO = (
    "datadrobe_fact_adjudication_submission_v1")
CONTRATO_PACOTE_REVISADO = "datadrobe_label_reviewed_fact_pack_v1"
MAXIMO_BYTES_REVISAO = 64 * 1024 * 1024
PADRAO_ALIAS = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,39}")
DECISOES = {
    "supported_candidate", "rejected_candidate", "insufficient_context",
}
MOTIVOS = {
    "supported_candidate": {None},
    "rejected_candidate": {
        "wrong_family", "wrong_facet", "wrong_value",
        "not_supported_by_excerpt", "other",
    },
    "insufficient_context": {
        "excerpt_ambiguous", "excerpt_incomplete", "other",
    },
}
CAMPOS_SUBMISSAO = {
    "contract", "batch_id", "source_package_id", "rubric_version",
    "rubric_sha256", "reviewer_alias", "state", "submitted_at", "decisions",
}
CAMPOS_DECISAO = {
    "subject_id", "decision", "reason_code", "note", "reviewed_at",
}


class ErroDeConsolidacao(RuntimeError):
    """O conjunto humano não satisfaz o contrato de revisão."""


def _hash(valor, campo):
    if not isinstance(valor, str) or not re.fullmatch(r"[0-9a-f]{64}", valor):
        raise ErroDeConsolidacao("{} fora do contrato".format(campo))
    return valor


def _texto(valor, campo, minimo=0, maximo=1000):
    if not isinstance(valor, str) or not minimo <= len(valor) <= maximo:
        raise ErroDeConsolidacao("{} fora do contrato".format(campo))
    if any(unicodedata.category(c).startswith("C") for c in valor):
        raise ErroDeConsolidacao("{} contém controle Unicode".format(campo))
    if unicodedata.normalize("NFC", valor) != valor:
        raise ErroDeConsolidacao("{} não está em NFC".format(campo))
    return valor


def _instante(valor, campo, agora):
    if not isinstance(valor, str):
        raise ErroDeConsolidacao("{} fora do contrato".format(campo))
    try:
        instante = dt.datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError as erro:
        raise ErroDeConsolidacao("{} inválido".format(campo)) from erro
    if instante.tzinfo is None:
        raise ErroDeConsolidacao("{} deve conter fuso".format(campo))
    instante = instante.astimezone(dt.timezone.utc)
    if instante > agora + dt.timedelta(minutes=10):
        raise ErroDeConsolidacao("{} está no futuro".format(campo))
    return instante


def _carregar_json(caminho):
    caminho = Path(caminho)
    if caminho.stat().st_size > MAXIMO_BYTES_REVISAO:
        raise ErroDeConsolidacao("revisão excede o teto de bytes")
    with caminho.open(encoding="utf-8") as arquivo:
        return json.load(arquivo)


def validar_submissao(dados, lote, agora=None):
    agora = (agora or dt.datetime.now(dt.timezone.utc)).astimezone(
        dt.timezone.utc)
    if not isinstance(dados, dict) or set(dados) != CAMPOS_SUBMISSAO:
        raise ErroDeConsolidacao("submissão contém campos inesperados")
    if dados["contract"] != lote["submission_contract"]:
        raise ErroDeConsolidacao("contrato da submissão diverge do lote")
    if dados["batch_id"] != lote["batch_id"]:
        raise ErroDeConsolidacao("batch_id diverge do lote")
    if dados["source_package_id"] != lote["source_package_id"]:
        raise ErroDeConsolidacao("source_package_id diverge do lote")
    if (dados["rubric_version"] != lote["rubric"]["version"]
            or dados["rubric_sha256"] != lote["rubric_sha256"]):
        raise ErroDeConsolidacao("rubrica diverge do lote")
    alias = dados["reviewer_alias"]
    if not isinstance(alias, str) or not PADRAO_ALIAS.fullmatch(alias):
        raise ErroDeConsolidacao("reviewer_alias fora do contrato")
    if dados["state"] != "submitted":
        raise ErroDeConsolidacao("submissão não está finalizada")
    enviado_em = _instante(dados["submitted_at"], "submitted_at", agora)
    decisoes = dados["decisions"]
    if not isinstance(decisoes, list):
        raise ErroDeConsolidacao("decisions deve ser lista")
    esperados = [item["subject_id"] for item in lote["subjects"]]
    recebidos = []
    validadas = {}
    for decisao in decisoes:
        if not isinstance(decisao, dict) or set(decisao) != CAMPOS_DECISAO:
            raise ErroDeConsolidacao("decisão contém campos inesperados")
        subject_id = _hash(decisao["subject_id"], "subject_id")
        recebidos.append(subject_id)
        escolha = decisao["decision"]
        if not isinstance(escolha, str) or escolha not in DECISOES:
            raise ErroDeConsolidacao("decision fora da rubrica")
        motivo = decisao["reason_code"]
        if (motivo is not None and not isinstance(motivo, str)) or motivo not in MOTIVOS[escolha]:
            raise ErroDeConsolidacao("reason_code incompatível com decision")
        nota = _texto(decisao["note"], "note", maximo=1000)
        if escolha == "supported_candidate" and nota:
            raise ErroDeConsolidacao("fato sustentado não aceita nota corretiva")
        if motivo == "other" and not nota.strip():
            raise ErroDeConsolidacao("motivo other exige nota")
        revisado_em = _instante(
            decisao["reviewed_at"], "reviewed_at", agora)
        if revisado_em > enviado_em:
            raise ErroDeConsolidacao("reviewed_at posterior a submitted_at")
        validadas[subject_id] = {
            "subject_id": subject_id,
            "decision": escolha,
            "reason_code": motivo,
            "note": nota,
            "reviewed_at": revisado_em.isoformat(),
        }
    if recebidos != esperados or len(set(recebidos)) != len(recebidos):
        raise ErroDeConsolidacao(
            "decisions deve cobrir os sujeitos exatamente na ordem do lote")
    return {
        "reviewer_alias": alias,
        "submitted_at": enviado_em.isoformat(),
        "submitted_at_utc": enviado_em,
        "submission_sha256": _sha256(_json_canonico(dados)),
        "decisions": validadas,
    }


def validar_revisores_distintos(revisoes):
    aliases = [revisao["reviewer_alias"].casefold() for revisao in revisoes]
    if len(set(aliases)) != len(aliases):
        raise ErroDeConsolidacao(
            "revisores e adjudicador devem usar aliases distintos")


def comparar(revisoes, lote):
    if len(revisoes) != 2:
        raise ErroDeConsolidacao("a comparação exige exatamente dois revisores")
    validar_revisores_distintos(revisoes)
    finais = {}
    divergencias = []
    for sujeito in lote["subjects"]:
        subject_id = sujeito["subject_id"]
        primeira = revisoes[0]["decisions"][subject_id]
        segunda = revisoes[1]["decisions"][subject_id]
        if primeira["decision"] == segunda["decision"]:
            finais[subject_id] = {
                "decision": primeira["decision"],
                "basis": "two_reviewer_consensus",
                "reason_codes": sorted({
                    motivo for motivo in (
                        primeira["reason_code"], segunda["reason_code"])
                    if motivo is not None
                }),
                "decision_notes": sorted({
                    nota for nota in (primeira["note"], segunda["note"])
                    if nota
                }),
            }
        else:
            divergencias.append(subject_id)
    return finais, divergencias


def preparar_lote_adjudicacao(lote, revisoes, divergencias):
    por_id = {sujeito["subject_id"]: sujeito for sujeito in lote["subjects"]}
    nucleo = {
        "contract": CONTRATO_ADJUDICACAO,
        "submission_contract": CONTRATO_SUBMISSAO_ADJUDICACAO,
        "source_contract": CONTRATO_ENTRADA,
        "source_package_id": lote["source_package_id"],
        "source_package_content_sha256": lote[
            "source_package_content_sha256"],
        "source_review_batch_id": lote["batch_id"],
        "source_review_submission_sha256": sorted(
            revisao["submission_sha256"] for revisao in revisoes),
        "rubric": RUBRICA,
        "rubric_sha256": lote["rubric_sha256"],
        "review_mode": "independent_adjudication_of_disagreements",
        "blind_to": [
            "aggregate_counts", "brand_identity", "parser_confidence",
            "product_identity", "shares", "trend_direction",
            "editorial_conclusion", "reviewer_identity",
            "previous_reviewer_decisions",
        ],
        "subject_count": len(divergencias),
        "subjects": [por_id[subject_id] for subject_id in divergencias],
    }
    return {**nucleo, "batch_id": _sha256(_json_canonico(nucleo))}


def _estado_final(decisao):
    return {
        "supported_candidate": "confirmed_candidate",
        "rejected_candidate": "rejected_candidate",
        "insufficient_context": "unresolved_candidate",
    }[decisao]


def _percentual(numerador, denominador):
    if not denominador:
        return None
    valor = Decimal(numerador) * Decimal(100) / Decimal(denominador)
    return float(valor.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def _recalcular_agregados(fatos_origem, finais):
    observados = {}
    acumulados = {}
    for fato in fatos_origem:
        sujeito = fato["subject"]
        subject_id = sujeito["subject_id"]
        if finais[subject_id]["decision"] != "supported_candidate":
            continue
        familia = sujeito["family"]
        observados.setdefault(familia, set()).add(fato["product_id"])
        chave = (familia, sujeito["facet_id"])
        acumulado = acumulados.setdefault(chave, {
            "products": set(), "brands": set(), "facts": set(),
            "candidate_concept_id": sujeito["candidate_concept_id"],
        })
        acumulado["products"].add(fato["product_id"])
        acumulado["brands"].add(fato["brand_id"])
        acumulado["facts"].add(fato["fact_id"])
    resultado = []
    for (familia, faceta), dados in sorted(acumulados.items()):
        denominador = len(observados[familia])
        resultado.append({
            "family": familia,
            "facet_id": faceta,
            "candidate_concept_id": dados["candidate_concept_id"],
            "state": "descriptive_reviewed_candidate",
            "product_count": len(dados["products"]),
            "brand_count": len(dados["brands"]),
            "denominator_products": denominador,
            "share_among_review_confirmed_dimension_observed_pct": _percentual(
                len(dados["products"]), denominador),
            "denominator_definition": (
                "products with at least one human-confirmed fact in this family"
            ),
            "supporting_fact_ids": sorted(dados["facts"]),
        })
    return resultado


def consolidar(pacote, revisoes_brutas, adjudicacao_bruta=None, agora=None):
    origem = validar_pacote(pacote)
    lote = _preparar_fila_validada(origem)
    revisoes = [
        validar_submissao(revisao, lote, agora=agora)
        for revisao in revisoes_brutas
    ]
    revisoes.sort(key=lambda revisao: revisao["submission_sha256"])
    finais, divergencias = comparar(revisoes, lote)
    lote_adjudicacao = None
    adjudicacao = None
    if divergencias:
        lote_adjudicacao = preparar_lote_adjudicacao(
            lote, revisoes, divergencias)
        if adjudicacao_bruta is None:
            nucleo_comparacao = {
                "contract": CONTRATO_COMPARACAO,
                "source_package_id": lote["source_package_id"],
                "source_package_content_sha256": lote[
                    "source_package_content_sha256"],
                "review_batch_id": lote["batch_id"],
                "rubric_version": lote["rubric"]["version"],
                "rubric_sha256": lote["rubric_sha256"],
                "reviewer_aliases": [
                    revisao["reviewer_alias"] for revisao in revisoes],
                "review_submission_sha256": sorted(
                    revisao["submission_sha256"] for revisao in revisoes),
                "state": "needs_independent_adjudication",
                "candidate_fact_count": len(origem["facts"]),
                "subject_count": lote["subject_count"],
                "consensus_count": len(finais),
                "divergence_count": len(divergencias),
                "divergent_subject_ids": divergencias,
                "adjudication_batch_id": lote_adjudicacao["batch_id"],
            }
            comparacao = {
                **nucleo_comparacao,
                "comparison_id": _sha256(_json_canonico(nucleo_comparacao)),
            }
            return comparacao, lote_adjudicacao
        adjudicacao = validar_submissao(
            adjudicacao_bruta, lote_adjudicacao, agora=agora)
        validar_revisores_distintos(revisoes + [adjudicacao])
        for subject_id in divergencias:
            decisao = adjudicacao["decisions"][subject_id]
            finais[subject_id] = {
                "decision": decisao["decision"],
                "basis": "independent_adjudication",
                "reason_codes": (
                    [] if decisao["reason_code"] is None
                    else [decisao["reason_code"]]),
                "decision_notes": (
                    [] if not decisao["note"] else [decisao["note"]]),
            }
    elif adjudicacao_bruta is not None:
        raise ErroDeConsolidacao("não há divergências para adjudicar")

    contagens_fatos = {
        "confirmed_candidate": 0,
        "rejected_candidate": 0,
        "unresolved_candidate": 0,
    }
    contagens_sujeitos = {
        "confirmed_review_subjects": 0,
        "rejected_review_subjects": 0,
        "unresolved_review_subjects": 0,
    }
    sujeitos_revisados = []
    for sujeito in lote["subjects"]:
        final = finais[sujeito["subject_id"]]
        estado = _estado_final(final["decision"])
        contagens_sujeitos[{
            "confirmed_candidate": "confirmed_review_subjects",
            "rejected_candidate": "rejected_review_subjects",
            "unresolved_candidate": "unresolved_review_subjects",
        }[estado]] += 1
        sujeitos_revisados.append({
            **sujeito,
            "review_state": estado,
            "decision_basis": final["basis"],
            "reason_codes": final["reason_codes"],
            "decision_notes": final["decision_notes"],
        })
    fatos_revisados = []
    for fato in origem["facts"]:
        sujeito = fato["subject"]
        final = finais[sujeito["subject_id"]]
        estado = _estado_final(final["decision"])
        contagens_fatos[estado] += 1
        fatos_revisados.append({
            "fact_id": fato["fact_id"],
            "review_subject_id": sujeito["subject_id"],
        })
    agregados = _recalcular_agregados(origem["facts"], finais)
    revisao_sha = sorted(
        revisao["submission_sha256"] for revisao in revisoes)
    contagens_com_agregados = {
        "candidate_facts": len(origem["facts"]),
        "review_subjects": lote["subject_count"],
        **contagens_fatos,
        **contagens_sujeitos,
        "reviewed_aggregates": len(agregados),
    }
    concluidos_em = [revisao["submitted_at_utc"] for revisao in revisoes]
    if adjudicacao:
        concluidos_em.append(adjudicacao["submitted_at_utc"])
    estado_liberacao = "private_human_reviewed_candidates"
    identidade = {
        "contract": CONTRATO_PACOTE_REVISADO,
        "source_package_id": lote["source_package_id"],
        "source_package_content_sha256": lote[
            "source_package_content_sha256"],
        "review_batch_id": lote["batch_id"],
        "review_submission_sha256": revisao_sha,
        "adjudication_batch_id": (
            lote_adjudicacao["batch_id"] if lote_adjudicacao else None),
        "adjudication_submission_sha256": (
            adjudicacao["submission_sha256"] if adjudicacao else None),
        "rubric_sha256": lote["rubric_sha256"],
        "review_completed_at": max(concluidos_em).isoformat(),
        "release_state": estado_liberacao,
        "raw_content_persisted": False,
        "requires_concept_review": True,
        "evidence_staging_allowed": False,
        "counts_sha256": _sha256(_json_canonico(contagens_com_agregados)),
        "reviewed_subjects_sha256": _sha256(
            _json_canonico(sujeitos_revisados)),
        "reviewed_facts_sha256": _sha256(_json_canonico(fatos_revisados)),
        "reviewed_aggregates_sha256": _sha256(_json_canonico(agregados)),
    }
    resultado = {
        **identidade,
        "reviewed_package_id": _sha256(_json_canonico(identidade)),
        "rubric_version": lote["rubric"]["version"],
        "review_mode": lote["review_mode"],
        "reviewer_aliases": [
            revisao["reviewer_alias"] for revisao in revisoes],
        "adjudicator_alias": (
            adjudicacao["reviewer_alias"] if adjudicacao else None),
        "counts": contagens_com_agregados,
        "reviewed_subjects": sujeitos_revisados,
        "reviewed_facts": fatos_revisados,
        "reviewed_aggregates": agregados,
    }
    return resultado, None


def escrever_json_atomico(caminho, valor):
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    descritor, temporario = tempfile.mkstemp(
        prefix=caminho.name + ".", suffix=".tmp", dir=str(caminho.parent))
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            json.dump(valor, arquivo, ensure_ascii=False, indent=2,
                      sort_keys=True, allow_nan=False)
            arquivo.write("\n")
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
    raiz = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--pacote", type=Path, required=True)
    parser.add_argument(
        "--revisao", type=Path, action="append", required=True)
    parser.add_argument("--adjudicacao", type=Path)
    parser.add_argument("--saida", type=Path, required=True)
    parser.add_argument(
        "--saida-adjudicacao", type=Path,
        help=("caminho opcional; por padrão usa <saida>-adjudicacao.html "
              "somente quando houver divergência"))
    parser.add_argument(
        "--template", type=Path,
        default=raiz / "ferramentas" / "revisao_etiqueta_radar.html")
    args = parser.parse_args()
    if len(args.revisao) != 2:
        raise SystemExit("informe exatamente dois arquivos --revisao")
    entradas = {args.pacote.resolve(), args.template.resolve()}
    entradas.update(caminho.resolve() for caminho in args.revisao)
    if args.adjudicacao:
        entradas.add(args.adjudicacao.resolve())
    saida_adjudicacao = args.saida_adjudicacao or args.saida.with_name(
        args.saida.stem + "-adjudicacao.html")
    destinos = {args.saida.resolve(), saida_adjudicacao.resolve()}
    if entradas & destinos or len(destinos) != 2:
        raise SystemExit("saídas não podem colidir com entradas ou entre si")
    try:
        if args.saida.exists():
            raise ErroDeConsolidacao("a saída já existe")
        pacote = carregar_pacote(args.pacote)
        revisoes = [_carregar_json(caminho) for caminho in args.revisao]
        adjudicacao = (
            _carregar_json(args.adjudicacao) if args.adjudicacao else None)
        resultado, lote_adjudicacao = consolidar(
            pacote, revisoes, adjudicacao_bruta=adjudicacao)
        if lote_adjudicacao is not None:
            if saida_adjudicacao.exists():
                raise ErroDeConsolidacao("a saída de adjudicação já existe")
            html = renderizar_html(lote_adjudicacao, args.template)
            escrever_texto_atomico(saida_adjudicacao, html)
            try:
                # O JSON é o marcador de conclusão: ele só nasce depois da
                # página que promete. Se sua escrita falhar, removemos apenas
                # o HTML novo cuja ausência foi verificada acima.
                escrever_json_atomico(args.saida, resultado)
            except BaseException:
                saida_adjudicacao.unlink(missing_ok=True)
                raise
        else:
            if saida_adjudicacao.exists():
                raise ErroDeConsolidacao(
                    "há uma saída de adjudicação obsoleta no destino")
            escrever_json_atomico(args.saida, resultado)
    except (ErroDeConsolidacao, ErroDePreparacao, OSError, ValueError,
            json.JSONDecodeError) as erro:
        raise SystemExit("consolidação bloqueada: {}".format(erro)) from erro
    print("{}: {}".format(resultado["contract"], resultado.get(
        "reviewed_package_id", resultado.get("adjudication_batch_id"))))


if __name__ == "__main__":
    main()
