#!/usr/bin/env python3
"""Invariantes offline da fundacao evidence-first da Market Intelligence 1.3."""

import csv
import hashlib
import json
from pathlib import Path
import re


RAIZ = Path(__file__).resolve().parents[1]
MIGRATION = (
    RAIZ / "supabase" / "migrations" /
    "20260831170000_a51_fundacao_de_evidencias_13.sql"
)
REGISTRO = RAIZ / "anexos" / "fontes_radar.csv"
GOVERNANCA = RAIZ / "GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md"


def falhar(mensagem):
    raise AssertionError(mensagem)


def exigir(texto, trecho, mensagem):
    if trecho.lower() not in texto.lower():
        falhar(mensagem + ": " + trecho)


def proibir(texto, trecho, mensagem):
    if trecho.lower() in texto.lower():
        falhar(mensagem + ": " + trecho)


def definicao(texto, assinatura):
    inicio = texto.lower().find(assinatura.lower())
    if inicio < 0:
        falhar("funcao ausente: " + assinatura)
    fim = texto.find("$$;", inicio)
    if fim < 0:
        falhar("corpo sem terminador: " + assinatura)
    return texto[inicio:fim + 3]


def hash_do_contrato(linha):
    canonico = json.dumps(
        linha, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonico.encode("utf-8")).hexdigest()


def verificar_espelho_do_registro(texto):
    registro_sha = hashlib.sha256(REGISTRO.read_bytes()).hexdigest()
    governanca_sha = hashlib.sha256(GOVERNANCA.read_bytes()).hexdigest()
    with REGISTRO.open(encoding="utf-8", newline="") as arquivo:
        linhas = list(csv.DictReader(arquivo))

    inicio = texto.index("insert into public.fontes_de_sinal")
    fim = texto.index("\n\n-- --------------------------------", inicio)
    semente = texto[inicio:fim]
    if semente.count(registro_sha) != len(linhas):
        falhar("hash integral do CSV nao acompanha cada fonte semeada")
    for linha in linhas:
        exigir(semente, "'{}'".format(linha["id"]),
               "fonte do CSV ausente da migration")
        exigir(semente, hash_do_contrato(linha),
               "hash canonico da fonte diverge do CSV")

    interna = next(
        linha for linha in linhas
        if linha["id"] == "datadrobe_curadoria_interna")
    if interna["autorizacao_sha256"] != governanca_sha:
        falhar("autorizacao interna nao aponta aos bytes da governanca")
    exigir(semente, governanca_sha,
           "autorizacao interna diverge no espelho SQL")


def main():
    texto = MIGRATION.read_text(encoding="utf-8")
    minusculo = texto.lower()

    tabelas = (
        "conceitos_de_moda", "mapeamentos_de_conceito_legado",
        "fontes_de_sinal", "execucoes_de_pesquisa", "itens_de_fonte",
        "evidencias_de_sinal", "leituras_de_mercado", "leitura_evidencias",
    )
    for tabela in tabelas:
        exigir(minusculo, "create table public." + tabela,
               "tabela da fundacao ausente")
        exigir(
            minusculo,
            "alter table public.{} force row level security".format(tabela),
            "RLS nao foi forcada")
        exigir(minusculo, "revoke all on table public." + tabela,
               "privilegio inicial nao foi revogado")

    verificar_espelho_do_registro(texto)

    # O contrato inicial usa somente a retencao padrao comprovada. MAM/ZDR
    # exigirao nova revisao do schema e do projeto OpenAI.
    for trecho in (
        "openai_retention_mode in ('none', 'standard_30d')",
        "openai_retention_mode = 'standard_30d'",
        "retencao_dias >= 30",
        "retencao_fatos_dias between 0 and 3650",
        "service_tier = 'default'",
        "modelo ~ '^gpt-5[.]6-luna",
        "executor = 'openai_responses'",
        "openai_project_id",
        "response_id",
    ):
        exigir(minusculo, trecho, "contrato OpenAI incompleto")
    proibir(minusculo, "mam_verified", "MAM nao foi verificado neste projeto")
    proibir(minusculo, "zdr_verified", "ZDR nao foi verificado neste projeto")

    # URL, escopo e payloads compactos usam um unico portao fail-closed.
    for trecho in (
        "create or replace function public._url_https_segura_13",
        "create or replace function public._url_no_escopo_13",
        "public._host_da_url_13(p_url) like '%.' || p_base_host",
        "substring(p_url from 9), '%[0-9a-fa-f]{2}'",
        "public._jsonb_sem_dados_brutos_13",
        "fonte_contrato_sha256",
        "autorizacao_sha256",
        "territorio",
        "periodo_inicio",
        "unidade_original",
        "transformacao_versao",
        "conceito_versao",
    ):
        exigir(minusculo, trecho, "proveniencia ou minimizacao incompleta")
    for chave in (
        "'body'", "'content'", "'fulltext'", "'rawtext'",
        "'sourcecontent'", "'transcript'", "'payload'", "'apikey'",
        "'authorization'", "'cookie'", "'secret'", "'token'",
        "(article|page|request|response)(body|content)$",
    ):
        exigir(minusculo, chave, "metadado sensivel ou bruto nao foi vedado")

    # As transicoes terminais sao centralizadas e serializadas.
    for trecho in (
        "execution_is_append_only",
        "evidence_must_start_draft",
        "reviewed_evidence_is_immutable",
        "reading_must_start_draft",
        "published_reading_is_immutable",
        "approved_concept_change_requires_next_version",
        "approved_or_retired_concept_cannot_be_deleted",
        "hashtextextended('canario:market-intelligence-13', 0)",
        "reading_requires_independent_supporting_sources",
        "insufficient_reading_requires_explicit_gap",
        "predictive_language_not_allowed",
        "concept_promotion_evidence_incomplete",
        "concept_already_reviewed",
        "approved_concept_not_found",
    ):
        exigir(minusculo, trecho, "portao transacional ausente")

    for trecho in (
        "exemplos_positivos", "exemplos_negativos",
        "protocolo_promocao_versao", "volume_observado",
        "volume_minimo_exigido", "revisada_por", "retirada_por",
        "create or replace function public.revisar_conceito_de_moda",
        "create or replace function public.retirar_conceito_de_moda",
        "grant execute on function public.revisar_conceito_de_moda",
        "grant execute on function public.retirar_conceito_de_moda",
    ):
        exigir(minusculo, trecho, "promocao humana de conceito incompleta")

    for verbo in ("insert", "update"):
        inicio = minusculo.index(
            "grant {} (".format(verbo),
            minusculo.index("revoke all on table public.conceitos_de_moda"))
        fim = minusculo.index(
            ") on table public.conceitos_de_moda to service_role;", inicio)
        concessao = minusculo[inicio:fim]
        for coluna in (
            "status", "versao", "revisada_em", "revisada_por",
            "retirada_em", "retirada_por",
        ):
            if re.search(r"\b{}\b".format(coluna), concessao):
                falhar("service_role altera ciclo do conceito por DML: " + coluna)

    revogacao = definicao(
        minusculo,
        "create or replace function "
        "public._retirar_leituras_de_fonte_revogada_13")
    for trecho in (
        "titulo = 'leitura retirada'",
        "cobertura = '{}'::jsonb",
        "status = 'revoked'",
        "motivo_revogacao = v_motivo",
        "set expira_em = least(",
        "new.contrato_sha256",
        "new.autorizacao_expira_em",
        "new.observacao",
    ):
        exigir(revogacao, trecho, "revogacao nao percorre toda a cadeia")

    poda = definicao(
        minusculo,
        "create or replace function public.podar_itens_de_fonte_13")
    exigir(poda, "security definer", "poda nao tem autoridade estreita")
    exigir(poda, "p_limite is null", "poda aceita limite nulo")
    exigir(poda, "status = 'withdrawn'", "poda nao retira leitura expirada")
    exigir(poda, "status = 'revoked'", "poda nao revoga evidencias")
    if poda.index("delete from public.evidencias_de_sinal") > poda.index(
            "delete from public.itens_de_fonte"):
        falhar("poda tenta apagar item antes da evidencia")

    publicavel = definicao(
        minusculo,
        "create or replace function public._leitura_publicavel_13")
    for trecho in (
        "e.expira_em <= now()",
        "i.fonte_contrato_sha256 <> f.contrato_sha256",
        "f.autorizacao_expira_em <= current_date",
        "f.display_rights in ('none', 'link_only')",
        "public._url_no_escopo_13(",
        "count(distinct i.fonte_id)",
        "count(distinct i.familia_origem)",
        "lx.service_tier = 'default'",
    ):
        exigir(publicavel, trecho, "predicado publico diverge da publicacao")

    # A superficie publica nao recebe SELECT direto nas tabelas privadas.
    if re.search(
            r"grant\s+select(?:\s*\([^;]*?\))?\s+on\s+table\s+public\."
            r"(?:conceitos_de_moda|mapeamentos_de_conceito_legado|"
            r"fontes_de_sinal|itens_de_fonte|evidencias_de_sinal|"
            r"leituras_de_mercado|leitura_evidencias)\s+to\s+"
            r"(?:anon|authenticated)", minusculo, flags=re.S):
        falhar("cliente recebeu SELECT direto e pode contornar a RPC publica")

    for padrao, mensagem in (
        (r"grant[^;]*(?:insert|update|delete)[^;]*"
         r"public\.fontes_de_sinal", "service_role altera registro fora do CSV"),
        (r"grant[^;]*delete[^;]*public\.execucoes_de_pesquisa",
         "execucao append-only recebeu DELETE"),
        (r"grant[^;]*(?:update|delete)[^;]*public\.itens_de_fonte",
         "item imutavel recebeu UPDATE/DELETE direto"),
        (r"grant[^;]*(?:update|delete)[^;]*public\.evidencias_de_sinal",
         "evidencia recebeu mutacao fora das RPCs"),
    ):
        if re.search(padrao, minusculo, flags=re.S):
            falhar(mensagem)

    for gatilho in (
        "conceitos_serializam_mudanca_13",
        "fontes_serializam_mudanca_13",
        "execucoes_serializam_mudanca_13",
        "leituras_serializam_mudanca_13",
        "leitura_evidencias_serializam_mudanca_13",
    ):
        exigir(minusculo, gatilho,
               "escrita critica pode inverter ordem de locks")

    for assinatura in (
        "create or replace function public.listar_leituras_de_mercado_publicadas",
        "create or replace function public.evidencias_da_leitura_publicada",
    ):
        corpo = definicao(minusculo, assinatura)
        exigir(corpo, "security definer", "RPC publica nao isola tabelas")
        exigir(corpo, "set search_path = pg_catalog, public, pg_temp",
               "RPC SECURITY DEFINER sem search_path fixo")

    for assinatura in (
        "create or replace function public._validar_fonte_do_item_13",
        "create or replace function public._proteger_evidencia_13",
        "create or replace function public._proteger_vinculo_de_leitura_13",
    ):
        corpo = definicao(minusculo, assinatura)
        exigir(corpo, "security definer",
               "trigger estreito nao consegue adquirir lock com ACL minima")
        exigir(corpo, "set search_path = pg_catalog, public, pg_temp",
               "trigger SECURITY DEFINER sem search_path fixo")

    leitura_publica = minusculo[minusculo.index(
        "create view public.leituras_de_mercado_publicadas"):]
    evidencia_publica = minusculo[minusculo.index(
        "create view public.evidencias_de_mercado_publicadas"):]
    for trecho in ("territorio", "lacunas"):
        exigir(leitura_publica, trecho, "leitura publica omite cobertura")
    for trecho in (
        "familia_origem", "tipo_origem", "conteudo_sha256",
        "fonte_contrato_sha256", "termos_versao",
    ):
        exigir(evidencia_publica, trecho, "trilha publica omite proveniencia")
    exigir(evidencia_publica, "case when f.display_rights = 'link_only'",
           "view perdeu defesa em profundidade para link_only")

    print("OK: fundacao 1.3 preserva direitos, proveniencia, RLS e abstencao")


if __name__ == "__main__":
    main()
