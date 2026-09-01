#!/usr/bin/env python3
"""Descobre candidatos privados para o Market Brief da 1.3.

Este programa e deliberadamente um *scout*, nao um coletor nem um redator.
Uma URL encontrada aqui continua sendo candidata: nao vira evidencia, serie ou
texto publico sem passar pelo gate de direitos, ser aberta pela etapa de
ingestao, deduplicada e aprovada. A execucao escreve apenas um artefato local.

O acesso web da Responses API fica restrito aos dominios verdes registrados em
``anexos/fontes_radar.csv``. Fontes vermelhas, sem direito de processamento por
IA ou sem URL-base nunca entram no allowlist enviado ao modelo.
"""

import argparse
import csv
import datetime as dt
from decimal import Decimal, ROUND_CEILING
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request


MODELO = "gpt-5.6-luna"
# Na Responses API, o valor literal ``default`` seleciona o processamento de
# preco/desempenho padrao. ``standard`` e a descricao humana, nao um enum.
SERVICE_TIER = "default"
VERSAO_DO_PROMPT = "radar-scout-v1"
URL_RESPOSTAS = "https://api.openai.com/v1/responses"
VERSAO_DOS_PRECOS = "2026-09-01"
PRECO_INPUT_USD_POR_MILHAO = 0.20
# A Luna cobra a escrita de cache a 1,25x o input sem cache. O orcamento
# conservador precifica *todo* input como escrita de cache, mesmo quando o
# usage real inclui tokens comuns ou cache hits mais baratos.
MULTIPLICADOR_DE_ESCRITA_DE_CACHE = 1.25
PRECO_OUTPUT_USD_POR_MILHAO = 1.20
PRECO_WEB_SEARCH_USD_POR_CHAMADA = 0.01
LIMIAR_CONTEXTO_CARO = 272_000
MAXIMO_DE_DOMINIOS = 20
MAXIMO_DE_CANDIDATOS = 8
MAXIMO_DE_PAUTAS = 20
MAXIMO_DE_BYTES_DO_PROMPT = 30_000
MAXIMO_RETENCAO_ARTEFATO_DIAS = 7
MAXIMO_TOKENS_AUDITAVEIS = 10_000_000
AI_PROCESSING_PERMITIDO = {"full_text"}
STATUS_PERMITIDO = {"green"}
METODOS_DE_SCOUT_WEB = {"hosted_web_search_domain_tree"}
TIERS = {"T0", "T1", "T2", "T3"}
STATUS = {"green", "yellow", "red"}
AI_PROCESSING = {"none", "facts", "full_text"}
OPENAI_RETENTION_MODES = {"none", "standard_30d"}
DISPLAY_RIGHTS = {
    "own_content",
    "facts_and_canonical_link",
    "link_only",
    "official_metadata_with_attribution",
    "licensed_content",
    "none",
}
URL_SCOPES = {"internal", "exact_host", "domain_tree"}
CAMPOS_DO_REGISTRO = (
    "id",
    "nome",
    "sensor",
    "tier",
    "metodo",
    "status",
    "ai_processing",
    "openai_retention_mode",
    "display_rights",
    "retencao_dias",
    "retencao_fatos_dias",
    "base_url",
    "url_scope",
    "termos_url",
    "termos_versao",
    "termos_revisados_em",
    "autorizacao_sha256",
    "aprovada_por",
    "aprovada_em",
    "autorizacao_expira_em",
    "observacao",
    "ativa",
)
METODO_INTERNO = "curadoria_interna"
PRAZO_DE_REVISAO_DIAS = {"T0": 365, "T1": 90, "T2": 90}
ORIGENS = {
    "original_report",
    "press_release",
    "syndication",
    "commentary",
    "retail_observation",
    "unknown",
}
PAPEIS = {"supports", "contradicts", "context"}
REGIOES = {"br", "international", "unknown"}
VOCABULARIO_PROIBIDO = (
    "chance de sucesso",
    "probabilidade de",
    "vai vender",
    "vender bem",
    "recomendamos produzir",
    "deve produzir",
    "sales probability",
    "will sell",
    "likely to sell",
)
CAMPOS_CANDIDATO = (
    "topic_id", "title", "url", "publisher", "published_at",
    "origin_type", "role", "region", "candidate_facets", "atomic_claim",
    "why_relevant", "missing_to_verify", "evidence_status",
    "requires_human_review",
)
CAMPOS_DA_PAUTA = (
    "id", "fenomeno", "consulta_pt", "consulta_en", "ativa",
)
PARAMETROS_DE_RASTREAMENTO = {
    "dclid", "fbclid", "gclid", "igshid", "mc_cid", "mc_eid",
    "msclkid", "ref_src", "s_cid", "vero_conv", "vero_id",
}


class ErroDoScout(RuntimeError):
    """Falha curta, sem ecoar chave, prompt inteiro ou resposta bruta."""


def _booleano(valor):
    return str(valor or "").strip().lower() in {"1", "true", "sim", "yes"}


def _booleano_do_registro(valor, numero_da_linha):
    normalizado = str(valor or "").strip()
    if normalizado not in {"true", "false"}:
        raise ValueError(
            "Linha {}: ativa deve ser true ou false".format(numero_da_linha))
    return normalizado == "true"


def _inteiro_nao_negativo(valor, campo, numero_da_linha):
    texto = str(valor or "").strip()
    if not re.fullmatch(r"0|[1-9][0-9]*", texto):
        raise ValueError(
            "Linha {}: {} deve ser inteiro nao negativo".format(
                numero_da_linha, campo))
    return int(texto)


def _texto_do_registro(valor, campo, numero_da_linha, minimo, maximo):
    texto = str(valor or "").strip()
    if not minimo <= len(texto) <= maximo:
        raise ValueError(
            "Linha {}: {} deve ter entre {} e {} caracteres".format(
                numero_da_linha, campo, minimo, maximo))
    if any(ord(caractere) < 32 for caractere in texto):
        raise ValueError(
            "Linha {}: {} contem caractere de controle".format(
                numero_da_linha, campo))
    return texto


def _data_iso_do_registro(valor, campo, numero_da_linha):
    texto = str(valor or "").strip()
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", texto):
        raise ValueError(
            "Linha {}: {} deve usar AAAA-MM-DD".format(numero_da_linha, campo))
    try:
        return dt.date.fromisoformat(texto)
    except ValueError as erro:
        raise ValueError(
            "Linha {}: {} invalida".format(numero_da_linha, campo)) from erro


def _url_https_valida(url):
    if (not isinstance(url, str)
            or any(ord(caractere) <= 32 or ord(caractere) > 126
                   for caractere in url)):
        return False
    try:
        partes = urllib.parse.urlsplit(url)
        porta = partes.port
    except (TypeError, ValueError, AttributeError):
        return False
    return (
        partes.scheme == "https"
        and bool(partes.hostname)
        and not partes.hostname.endswith(".")
        and bool(re.fullmatch(
            r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
            r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+",
            partes.hostname.lower().rstrip(".")))
        and partes.username is None
        and partes.password is None
        and porta is None
        and not partes.query
        and not partes.fragment
        and bool(re.fullmatch(
            r"(?:/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?", partes.path))
        and not re.search(r"%(?![0-9a-f]{2})", partes.path, re.IGNORECASE)
        and not re.search(
            r"/(?:[.]|%2e)(?:[.]|%2e)?(?:/|$)",
            partes.path, re.IGNORECASE)
        and not re.search(
            r"%(?:0[0-9a-f]|1[0-9a-f]|7f|25|2f|3f|23|5c)",
            partes.path, flags=re.IGNORECASE)
    )


def _origem_do_scout_valida(url):
    """Hosted web search só admite autorização para a origem inteira.

    A ferramenta da API restringe por domínio, não por path. Aceitar uma
    licença limitada a ``/fashion`` como se cobrisse o host inteiro seria
    ampliar direitos em runtime. O host exato (inclusive ``www``) é preservado
    para a URL materializada e a ``base_url`` do banco permanecerem idênticas.
    """
    if not _url_https_valida(url):
        return False
    partes = urllib.parse.urlsplit(url)
    return (
        partes.path in ("", "/")
        and not partes.query
        and not partes.fragment
    )


def dominio_da_url(url):
    try:
        partes = urllib.parse.urlsplit(url)
    except (TypeError, ValueError, AttributeError):
        return None
    if partes.scheme != "https" or not partes.hostname:
        return None
    return partes.hostname.lower().rstrip(".")


def host_da_url(url):
    if not isinstance(url, str) or any(ord(caractere) <= 32 for caractere in url):
        return None
    try:
        partes = urllib.parse.urlsplit(url)
        porta = partes.port
    except (TypeError, ValueError, AttributeError):
        return None
    if (partes.scheme != "https" or not partes.hostname or porta is not None
            or partes.username is not None or partes.password is not None):
        return None
    return partes.hostname.lower().rstrip(".")


def _host_no_escopo(host, raiz):
    """O filtro oficial cobre o domínio informado e todos os subdomínios."""
    return bool(host and raiz) and (host == raiz or host.endswith("." + raiz))


def carregar_registro_fontes(caminho, hoje=None):
    """Valida o registro inteiro sem promover silenciosamente linha invalida.

    ``hoje`` existe para o teste offline poder atravessar exatamente o limite
    de validade. Em producao, a data UTC corrente e a unica referencia.
    """
    hoje = hoje or dt.datetime.now(dt.timezone.utc).date()
    if isinstance(hoje, dt.datetime):
        hoje = hoje.date()
    if not isinstance(hoje, dt.date):
        raise TypeError("hoje deve ser date")

    linhas = []
    ids = set()
    with open(caminho, encoding="utf-8", newline="") as arquivo:
        leitor = csv.DictReader(arquivo)
        cabecalho = tuple(leitor.fieldnames or ())
        ausentes = set(CAMPOS_DO_REGISTRO) - set(cabecalho)
        extras = set(cabecalho) - set(CAMPOS_DO_REGISTRO)
        if ausentes or extras:
            partes = []
            if ausentes:
                partes.append("ausentes: " + ", ".join(sorted(ausentes)))
            if extras:
                partes.append("desconhecidas: " + ", ".join(sorted(extras)))
            raise ValueError(
                "Cabecalho do registro invalido (" + "; ".join(partes) + ")")
        if cabecalho != CAMPOS_DO_REGISTRO:
            raise ValueError("Colunas do registro fora da ordem contratual")

        for numero_da_linha, bruta in enumerate(leitor, start=2):
            if None in bruta:
                raise ValueError(
                    "Linha {}: colunas a mais".format(numero_da_linha))
            linha = {campo: str(bruta.get(campo) or "").strip()
                     for campo in CAMPOS_DO_REGISTRO}
            opcionais = {
                "base_url", "autorizacao_sha256", "aprovada_por",
                "aprovada_em", "autorizacao_expira_em",
            }
            vazios = [campo for campo in CAMPOS_DO_REGISTRO
                      if not linha[campo] and campo not in opcionais]
            if vazios:
                raise ValueError(
                    "Linha {}: campos vazios: {}".format(
                        numero_da_linha, ", ".join(vazios)))

            identificador = linha["id"]
            if (len(identificador) > 80
                    or not re.fullmatch(
                        r"[a-z0-9]+(?:[._-][a-z0-9]+)*", identificador)):
                raise ValueError(
                    "Linha {}: id deve ser ASCII estavel em minusculas".format(
                        numero_da_linha))
            if identificador in ids:
                raise ValueError("Linha {}: id repetido ({})".format(
                    numero_da_linha, identificador))
            ids.add(identificador)

            for campo, permitidos in (
                    ("tier", TIERS),
                    ("status", STATUS),
                    ("ai_processing", AI_PROCESSING),
                    ("openai_retention_mode", OPENAI_RETENTION_MODES),
                    ("display_rights", DISPLAY_RIGHTS),
                    ("url_scope", URL_SCOPES)):
                if linha[campo] not in permitidos:
                    raise ValueError(
                        "Linha {}: {} fora do enum ({})".format(
                            numero_da_linha, campo, linha[campo]))

            linha["retencao_dias"] = _inteiro_nao_negativo(
                linha["retencao_dias"], "retencao_dias", numero_da_linha)
            linha["retencao_fatos_dias"] = _inteiro_nao_negativo(
                linha["retencao_fatos_dias"],
                "retencao_fatos_dias", numero_da_linha)
            if linha["retencao_dias"] > 90:
                raise ValueError(
                    "Linha {}: retencao_dias excede 90".format(
                        numero_da_linha))
            if linha["retencao_fatos_dias"] > 3650:
                raise ValueError(
                    "Linha {}: retencao_fatos_dias excede 3650".format(
                        numero_da_linha))
            linha["ativa"] = _booleano_do_registro(
                linha["ativa"], numero_da_linha)

            for campo, minimo, maximo in (
                    ("nome", 1, 160),
                    ("sensor", 1, 80),
                    ("metodo", 1, 120),
                    ("termos_versao", 1, 160),
                    ("observacao", 1, 2000)):
                linha[campo] = _texto_do_registro(
                    linha[campo], campo, numero_da_linha, minimo, maximo)
            if len(linha["base_url"]) > 2048:
                raise ValueError(
                    "Linha {}: base_url excede 2048 caracteres".format(
                        numero_da_linha))
            if not 1 <= len(linha["termos_url"]) <= 2048:
                raise ValueError(
                    "Linha {}: termos_url deve ter entre 1 e 2048 caracteres".
                    format(numero_da_linha))

            revisados_em = _data_iso_do_registro(
                linha["termos_revisados_em"],
                "termos_revisados_em", numero_da_linha)
            linha["termos_revisados_em"] = revisados_em
            if revisados_em > hoje:
                raise ValueError(
                    "Linha {}: termos revisados no futuro".format(numero_da_linha))

            interna = linha["tier"] == "T0" and linha["metodo"] == METODO_INTERNO
            if linha["base_url"]:
                if not _url_https_valida(linha["base_url"]):
                    raise ValueError(
                        "Linha {}: base_url deve ser HTTPS".format(numero_da_linha))
            elif not interna:
                raise ValueError(
                    "Linha {}: base_url vazia so e aceita para curadoria interna T0".
                    format(numero_da_linha))

            if interna:
                if linha["url_scope"] != "internal":
                    raise ValueError(
                        "Linha {}: curadoria interna exige url_scope internal".
                        format(numero_da_linha))
                if linha["termos_url"] != (
                        "GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md"):
                    raise ValueError(
                        "Linha {}: curadoria interna deve apontar ao contrato local".
                        format(numero_da_linha))
            else:
                if linha["url_scope"] == "internal":
                    raise ValueError(
                        "Linha {}: fonte externa nao pode usar url_scope internal".
                        format(numero_da_linha))
                if not _url_https_valida(linha["termos_url"]):
                    raise ValueError(
                        "Linha {}: termos_url deve ser HTTPS".format(
                            numero_da_linha))

            if (linha["metodo"] in METODOS_DE_SCOUT_WEB
                    and (linha["url_scope"] != "domain_tree"
                         or not _origem_do_scout_valida(linha["base_url"]))):
                raise ValueError(
                    "Linha {}: hosted_web_search_domain_tree exige base_url "
                    "canonica da origem inteira, url_scope domain_tree e "
                    "ausencia de path, porta, query ou fragmento".
                    format(numero_da_linha))

            if linha["status"] == "green" and linha["tier"] == "T3":
                raise ValueError(
                    "Linha {}: T3 nunca pode ser green".format(numero_da_linha))
            if (linha["status"] == "green"
                    and linha["display_rights"] == "none"):
                raise ValueError(
                    "Linha {}: fonte green exige direito de exibicao".format(
                        numero_da_linha))
            if (linha["status"] == "green"
                    and linha["retencao_fatos_dias"] < 1):
                raise ValueError(
                    "Linha {}: fonte green exige retencao factual positiva".
                    format(numero_da_linha))
            campos_de_aprovacao = (
                linha["autorizacao_sha256"], linha["aprovada_por"],
                linha["aprovada_em"], linha["autorizacao_expira_em"],
            )
            if any(campos_de_aprovacao) and not all(campos_de_aprovacao):
                raise ValueError(
                    "Linha {}: aprovacao deve ser preenchida por inteiro".
                    format(numero_da_linha))
            if all(campos_de_aprovacao):
                if not re.fullmatch(
                        r"[0-9a-f]{64}", linha["autorizacao_sha256"]):
                    raise ValueError(
                        "Linha {}: autorizacao_sha256 invalido".format(
                            numero_da_linha))
                linha["aprovada_por"] = _texto_do_registro(
                    linha["aprovada_por"], "aprovada_por",
                    numero_da_linha, 1, 160)
                linha["aprovada_em"] = _data_iso_do_registro(
                    linha["aprovada_em"], "aprovada_em", numero_da_linha)
                linha["autorizacao_expira_em"] = _data_iso_do_registro(
                    linha["autorizacao_expira_em"],
                    "autorizacao_expira_em", numero_da_linha)
                if linha["aprovada_em"] > hoje:
                    raise ValueError(
                        "Linha {}: aprovacao no futuro".format(numero_da_linha))
                if linha["autorizacao_expira_em"] <= hoje:
                    raise ValueError(
                        "Linha {}: autorizacao expirada".format(
                            numero_da_linha))
                if linha["autorizacao_expira_em"] < linha["aprovada_em"]:
                    raise ValueError(
                        "Linha {}: autorizacao expira antes da aprovacao".
                        format(numero_da_linha))
            else:
                linha["aprovada_em"] = None
                linha["autorizacao_expira_em"] = None
            if linha["status"] == "green" and not all(campos_de_aprovacao):
                raise ValueError(
                    "Linha {}: fonte green exige aprovacao completa".format(
                        numero_da_linha))
            modo_openai = linha["openai_retention_mode"]
            if linha["ai_processing"] == "none":
                if modo_openai != "none":
                    raise ValueError(
                        "Linha {}: fonte sem IA deve usar retencao OpenAI none".
                        format(numero_da_linha))
            elif modo_openai == "none":
                raise ValueError(
                    "Linha {}: processamento por IA exige modo de retencao OpenAI".
                    format(numero_da_linha))
            if (modo_openai == "standard_30d"
                    and linha["retencao_dias"] < 30):
                raise ValueError(
                    "Linha {}: modo OpenAI padrao exige retencao de ao menos 30 dias".
                    format(numero_da_linha))
            if linha["ativa"] and linha["status"] == "green":
                prazo = PRAZO_DE_REVISAO_DIAS.get(linha["tier"])
                if prazo is None:
                    raise ValueError(
                        "Linha {}: tier sem prazo de revisao".format(
                            numero_da_linha))
                if hoje >= revisados_em + dt.timedelta(days=prazo):
                    raise ValueError(
                        "Linha {}: revisao dos termos expirada".format(
                            numero_da_linha))
            linhas.append(linha)

    if not linhas:
        raise ValueError("Registro de fontes vazio")
    return linhas


def carregar_fontes(caminho, hoje=None):
    """Retorna somente fontes web elegiveis; todo o resto falha fechado."""
    fontes = {}
    dominios = set()
    for linha in carregar_registro_fontes(caminho, hoje=hoje):
        if not linha["ativa"]:
            continue
        if linha["status"] not in STATUS_PERMITIDO:
            continue
        if linha["metodo"] not in METODOS_DE_SCOUT_WEB:
            continue
        if linha["url_scope"] != "domain_tree":
            continue
        if linha["ai_processing"] not in AI_PROCESSING_PERMITIDO:
            continue
        if linha["openai_retention_mode"] != "standard_30d":
            continue
        if linha["retencao_fatos_dias"] < 1:
            continue
        # T0 interno pode ser green, mas nunca vira permissao de busca web.
        dominio = dominio_da_url(linha["base_url"])
        if not dominio:
            continue
        if any(
                _host_no_escopo(dominio, existente)
                or _host_no_escopo(existente, dominio)
                for existente in dominios):
            raise ValueError(
                "Escopos de dominio sobrepostos em fontes verdes do scout")
        dominios.add(dominio)
        identificador = linha["id"]
        fontes[identificador] = {
            "id": identificador,
            "nome": linha["nome"],
            "dominio": dominio,
            "host": host_da_url(linha["base_url"]),
            "base_url": linha["base_url"],
            "url_scope": linha["url_scope"],
            "metodo": linha["metodo"],
            "ai_processing": linha["ai_processing"],
            "openai_retention_mode": linha["openai_retention_mode"],
            "display_rights": linha["display_rights"],
            "retencao_dias": linha["retencao_dias"],
            "retencao_fatos_dias": linha["retencao_fatos_dias"],
            "termos_url": linha["termos_url"],
            "termos_versao": linha["termos_versao"],
            "termos_revisados_em": linha["termos_revisados_em"].isoformat(),
            "autorizacao_sha256": linha["autorizacao_sha256"],
            "aprovada_por": linha["aprovada_por"],
            "aprovada_em": linha["aprovada_em"].isoformat(),
            "autorizacao_expira_em": (
                linha["autorizacao_expira_em"].isoformat()),
        }
    if not fontes:
        raise ValueError("Nenhuma fonte verde autoriza processamento por IA")
    if len({f["dominio"] for f in fontes.values()}) > MAXIMO_DE_DOMINIOS:
        raise ValueError("Allowlist excede o teto de dominios do scout")
    return fontes


def retencao_do_artefato(fontes):
    if not fontes:
        raise ValueError("Nenhuma fonte elegivel para calcular retencao")
    return min(
        MAXIMO_RETENCAO_ARTEFATO_DIAS,
        min(fonte["retencao_fatos_dias"] for fonte in fontes.values()),
    )


def carregar_pautas(caminho):
    pautas = []
    ids = set()
    with open(caminho, encoding="utf-8", newline="") as arquivo:
        leitor = csv.DictReader(arquivo)
        cabecalho = tuple(leitor.fieldnames or ())
        if cabecalho != CAMPOS_DA_PAUTA:
            raise ValueError("Cabecalho das pautas fora do contrato")
        for numero_da_linha, bruta in enumerate(leitor, start=2):
            if None in bruta:
                raise ValueError(
                    "Linha {} das pautas tem colunas a mais".format(
                        numero_da_linha))
            identificador = str(bruta.get("id") or "").strip()
            if (len(identificador) > 80
                    or not re.fullmatch(
                        r"[a-z0-9]+(?:[._-][a-z0-9]+)*", identificador)):
                raise ValueError(
                    "Linha {} das pautas tem id invalido".format(
                        numero_da_linha))
            if identificador in ids:
                raise ValueError(
                    "Linha {} das pautas repete id {}".format(
                        numero_da_linha, identificador))
            ids.add(identificador)
            fenomeno = _texto_do_registro(
                bruta.get("fenomeno"), "fenomeno", numero_da_linha, 1, 80)
            consulta_pt = str(bruta.get("consulta_pt") or "").strip()
            consulta_en = str(bruta.get("consulta_en") or "").strip()
            for campo, consulta in (
                    ("consulta_pt", consulta_pt), ("consulta_en", consulta_en)):
                if len(consulta) > 300 or any(
                        ord(caractere) < 32 for caractere in consulta):
                    raise ValueError(
                        "Linha {}: {} fora do contrato".format(
                            numero_da_linha, campo))
            if not consulta_pt and not consulta_en:
                raise ValueError(
                    "Linha {}: pauta sem consulta".format(numero_da_linha))
            ativa = _booleano_do_registro(
                bruta.get("ativa"), numero_da_linha)
            if not ativa:
                continue
            consulta = " / ".join(
                parte for parte in (consulta_pt, consulta_en) if parte)
            pautas.append({
                "id": identificador,
                "fenomeno": fenomeno,
                "consulta": consulta,
            })
    if not pautas:
        raise ValueError("Nenhuma pauta ativa")
    if len(pautas) > MAXIMO_DE_PAUTAS:
        raise ValueError("Pautas ativas excedem o teto")
    return pautas


def schema_da_saida(ids_de_pauta):
    candidato = {
        "type": "object",
        "properties": {
            "topic_id": {"type": "string", "enum": sorted(ids_de_pauta)},
            "title": {"type": "string", "minLength": 1, "maxLength": 240},
            "url": {"type": "string", "minLength": 9, "maxLength": 2048},
            "publisher": {"type": "string", "minLength": 1, "maxLength": 120},
            "published_at": {"type": ["string", "null"]},
            "origin_type": {"type": "string", "enum": sorted(ORIGENS)},
            "role": {"type": "string", "enum": sorted(PAPEIS)},
            "region": {"type": "string", "enum": sorted(REGIOES)},
            "candidate_facets": {
                "type": "array",
                "items": {"type": "string", "minLength": 1, "maxLength": 80},
                "maxItems": 8,
            },
            "atomic_claim": {"type": "string", "minLength": 1, "maxLength": 500},
            "why_relevant": {"type": "string", "minLength": 1, "maxLength": 500},
            "missing_to_verify": {"type": "string", "minLength": 1, "maxLength": 500},
            "evidence_status": {"type": "string", "enum": ["candidate_only"]},
            "requires_human_review": {"type": "boolean", "enum": [True]},
        },
        "required": [
            "topic_id", "title", "url", "publisher", "published_at",
            "origin_type", "role", "region", "candidate_facets", "atomic_claim",
            "why_relevant", "missing_to_verify", "evidence_status",
            "requires_human_review",
        ],
        "additionalProperties": False,
    }
    return {
        "type": "object",
        "properties": {
            "summary": {"type": "string", "minLength": 1, "maxLength": 800},
            "candidates": {
                "type": "array", "items": candidato, "maxItems": MAXIMO_DE_CANDIDATOS,
            },
            "coverage_gaps": {
                "type": "array",
                "items": {"type": "string", "minLength": 1, "maxLength": 240},
                "maxItems": 12,
            },
        },
        "required": ["summary", "candidates", "coverage_gaps"],
        "additionalProperties": False,
    }


def instrucoes(fontes, pautas):
    lista_fontes = "\n".join(
        "- {}: {} ({}; method={})".format(
            f["id"], f["nome"], f["base_url"], f["metodo"])
        for f in sorted(fontes.values(), key=lambda item: item["id"]))
    lista_pautas = "\n".join(
        "- {} [{}]: {}".format(p["id"], p["fenomeno"], p["consulta"])
        for p in pautas)
    return """You are the private discovery scout for DataDrobe, a Brazilian
women's-fashion market evidence product. Find at most eight current candidate
pages that deserve human review. This is discovery, never publication.

Hard epistemic rules:
- A search result or snippet is never evidence. Mark every item candidate_only.
- Do not forecast sales, adoption probability, assortment share or quantities.
- Product launch is not consumer adoption. Unavailability is not a sale.
- Do not infer causality between runway, creators, search and retail.
- Prefer an original report over copies. Ten syndications count as one origin.
- Sponsored/partner content is launch evidence, not independent confirmation.
- Include contrary or cooling signals when found.
- Never quote passages. Paraphrase one atomic, externally verifiable claim.
- If a date is not visible, return null. Never estimate it.
- A candidate needs a canonical HTTPS URL from the allowed domains below.
- Explain what is still missing before the candidate could support a reading.

Allowed sources (the runtime also enforces these domains):
{}

Research topics:
{}
""".format(lista_fontes, lista_pautas)


def montar_payload(fontes, pautas):
    dominios = sorted({fonte["host"] for fonte in fontes.values()})
    prompt = instrucoes(fontes, pautas)
    if len(prompt.encode("utf-8")) > MAXIMO_DE_BYTES_DO_PROMPT:
        raise ValueError("Prompt do scout excede o teto de bytes")
    return {
        "model": MODELO,
        "service_tier": SERVICE_TIER,
        "store": False,
        "reasoning": {"effort": "low"},
        "max_output_tokens": 4500,
        "max_tool_calls": 8,
        "instructions": prompt,
        "input": [{
            "role": "user",
            "content": [{
                "type": "input_text",
                "text": (
                    "Search the allowed sources for current candidate signals. "
                    "Return fewer items instead of weak or duplicate claims."
                ),
            }],
        }],
        "tools": [{
            "type": "web_search",
            "search_context_size": "medium",
            "filters": {"allowed_domains": dominios},
        }],
        "tool_choice": "required",
        "include": ["web_search_call.action.sources"],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "datadrobe_market_scout",
                "strict": True,
                "schema": schema_da_saida({p["id"] for p in pautas}),
            },
        },
    }


def hash_do_prompt(fontes, pautas):
    return hashlib.sha256(
        instrucoes(fontes, pautas).encode("utf-8")).hexdigest()


def _sha256_do_arquivo(caminho):
    return hashlib.sha256(Path(caminho).read_bytes()).hexdigest()


def _codigo_sha():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def _repository_sha():
    valor = os.environ.get("GITHUB_SHA", "").strip().lower()
    return valor if re.fullmatch(r"[0-9a-f]{7,64}", valor) else None


def _escrever_json_atomico(caminho, valor):
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


def _projeto_openai_valido(valor):
    return bool(re.fullmatch(r"proj_[A-Za-z0-9_-]{6,200}", valor or ""))


def _credencial_openai_valida(valor):
    return (
        isinstance(valor, str)
        and 20 <= len(valor) <= 512
        and all(33 <= ord(caractere) <= 126 for caractere in valor)
    )


def _modelo_luna_precificado(valor):
    """Aceita o alias pedido e snapshots datados da mesma família/tarifa."""
    if valor == MODELO:
        return True
    if not isinstance(valor, str):
        return False
    correspondencia = re.fullmatch(
        re.escape(MODELO) + r"-(\d{4}-\d{2}-\d{2})", valor)
    if correspondencia is None:
        return False
    try:
        dt.date.fromisoformat(correspondencia.group(1))
    except ValueError:
        return False
    return True


def _rota_com_tarifa_conhecida(resposta):
    return (
        isinstance(resposta, dict)
        and _modelo_luna_precificado(resposta.get("model"))
        and resposta.get("service_tier") == SERVICE_TIER
    )


def chamar_openai(payload, chave, projeto):
    """Executa uma unica chamada paga.

    Repeticao automatica sem mudar o pacote mascara custo e pode duplicar uma
    pesquisa que o servidor concluiu antes da conexao cair. Uma nova tentativa
    precisa ser uma decisao explicita do operador.
    """
    dados = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    requisicao = urllib.request.Request(
        URL_RESPOSTAS,
        data=dados,
        headers={
            "Authorization": "Bearer " + chave,
            "Content-Type": "application/json",
            "OpenAI-Project": projeto,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(requisicao, timeout=180) as resposta:
            return json.load(resposta)
    except urllib.error.HTTPError as erro:
        erro.read()
        raise ErroDoScout("OpenAI HTTP {}".format(erro.code))
    except (urllib.error.URLError, TimeoutError, OSError) as erro:
        raise ErroDoScout("Falha de rede ao chamar a OpenAI") from erro


def verificar_prontidao(caminho, pautas=None, hoje=None):
    """Valida o registro e informa se existe fonte web elegivel.

    Falta de fonte autorizada e um bloqueio esperado do laboratorio, nao uma
    falha de infraestrutura. Qualquer outro erro do contrato continua subindo.
    """
    pautas_carregadas = carregar_pautas(pautas) if pautas is not None else None
    try:
        fontes = carregar_fontes(caminho, hoje=hoje)
    except ValueError as erro:
        if str(erro) == "Nenhuma fonte verde autoriza processamento por IA":
            return False
        raise
    if pautas_carregadas is not None:
        montar_payload(fontes, pautas_carregadas)
    return True


def extrair_texto(resposta):
    status = resposta.get("status")
    if status != "completed":
        motivo = (resposta.get("incomplete_details") or {}).get(
            "reason", status or "desconhecido")
        raise ErroDoScout("Resposta nao concluida ({})".format(motivo))
    saida = resposta.get("output")
    if not isinstance(saida, list):
        raise ErroDoScout("Output da resposta fora do contrato")
    textos = []
    for item in saida:
        if not isinstance(item, dict):
            raise ErroDoScout("Item da resposta fora do contrato")
        if item.get("type") != "message":
            continue
        conteudos = item.get("content")
        if not isinstance(conteudos, list):
            raise ErroDoScout("Conteudo da mensagem fora do contrato")
        for conteudo in conteudos:
            if not isinstance(conteudo, dict):
                raise ErroDoScout("Conteudo da mensagem fora do contrato")
            if conteudo.get("type") == "refusal":
                raise ErroDoScout("O modelo recusou a pesquisa")
            if conteudo.get("type") == "output_text":
                textos.append(conteudo.get("text", ""))
    if len(textos) != 1 or not isinstance(textos[0], str):
        raise ErroDoScout("Resposta deve conter um unico output_text")
    return textos[0]


def _urls_de_fontes_web(resposta):
    """Extrai todas as URLs tocadas pelas acoes auditaveis de web search.

    ``search`` materializa a lista completa em ``action.sources`` quando o
    include correspondente foi pedido. ``open_page`` e ``find_in_page``
    carregam a URL diretamente na acao e nao precisam repetir ``sources``.
    Toda URL encontrada segue para o mesmo allowlist estrito de
    :func:`validar_saida`; uma navegacao auxiliar nunca amplia o escopo.
    """
    urls = set()
    chamadas = 0
    for item in resposta.get("output", []):
        if not isinstance(item, dict) or item.get("type") != "web_search_call":
            continue
        chamadas += 1
        if item.get("status") != "completed":
            raise ErroDoScout("Chamada de busca web nao concluida")
        action = item.get("action")
        if not isinstance(action, dict):
            raise ErroDoScout("Acao da busca web fora do contrato")
        tipo = action.get("type")
        if tipo == "search":
            fontes = action.get("sources")
            if not isinstance(fontes, list):
                raise ErroDoScout("Busca web sem lista de fontes auditavel")
            for fonte in fontes:
                if (not isinstance(fonte, dict)
                        or not isinstance(fonte.get("url"), str)):
                    raise ErroDoScout("Fonte da busca fora do contrato")
                urls.add(fonte["url"])
        elif tipo in {"open_page", "find_in_page"}:
            if not isinstance(action.get("url"), str):
                raise ErroDoScout("Navegacao web sem URL auditavel")
            urls.add(action["url"])
        else:
            raise ErroDoScout("Tipo de acao web desconhecido")
    if chamadas == 0 or not urls:
        raise ErroDoScout("Resposta sem fonte de busca auditavel")
    return urls, chamadas


def _uso_auditavel(resposta):
    if not isinstance(resposta, dict):
        raise ErroDoScout("Envelope da resposta fora do contrato")
    uso = resposta.get("usage")
    if not isinstance(uso, dict):
        raise ErroDoScout("Resposta sem usage auditavel")
    for campo in ("input_tokens", "output_tokens", "total_tokens"):
        if (not isinstance(uso.get(campo), int) or isinstance(uso.get(campo), bool)
                or not 0 <= uso[campo] <= MAXIMO_TOKENS_AUDITAVEIS):
            raise ErroDoScout("Usage sem {} valido".format(campo))
    if uso["total_tokens"] < uso["input_tokens"] + uso["output_tokens"]:
        raise ErroDoScout("Usage total menor que entrada mais saida")
    return uso


def _numero_de_chamadas_web_disponivel(resposta):
    """Conta envelopes de ferramenta sem presumir que passaram na auditoria.

    O numero ainda e util para reconciliacao de custo quando a resposta chegou,
    mas o conteudo do modelo, uma URL ou uma acao falha no gate posterior.
    ``None`` distingue output ausente/malformado de uma lista valida sem calls.
    """
    saida = resposta.get("output")
    if not isinstance(saida, list):
        return None
    return sum(
        1 for item in saida
        if isinstance(item, dict) and item.get("type") == "web_search_call"
    )


def _auditar_resposta(resposta):
    if not isinstance(resposta, dict):
        raise ErroDoScout("Envelope da resposta fora do contrato")
    extrair_texto(resposta)
    if resposta.get("error") is not None:
        raise ErroDoScout("Resposta concluida com erro")
    if not isinstance(resposta.get("id"), str) or not re.fullmatch(
            r"resp_[A-Za-z0-9_-]{6,200}", resposta["id"]):
        raise ErroDoScout("Resposta sem id auditavel")
    if not _modelo_luna_precificado(resposta.get("model")):
        raise ErroDoScout("Modelo resolvido fora da tarifa Luna versionada")
    if resposta.get("service_tier") != SERVICE_TIER:
        raise ErroDoScout("Service tier resolvido fora do contrato")
    uso = _uso_auditavel(resposta)
    urls, chamadas = _urls_de_fontes_web(resposta)
    if chamadas > 8:
        raise ErroDoScout("Resposta excedeu o teto de buscas web")
    return uso, urls, chamadas


def _custo_maximo_estimado(uso, chamadas_web):
    """Teto conservador segundo a tabela Luna versionada neste arquivo.

    Para nao subestimar cache writes, todo input usa 1,25x a tarifa de input.
    Acima de 272 mil tokens de entrada, as tarifas de input e output recebem os
    multiplicadores publicados de 2x e 1,5x. O arredondamento e sempre para
    cima, em micros de dolar; portanto a serializacao nao arredonda o teto para
    baixo.
    """
    longo = uso["input_tokens"] > LIMIAR_CONTEXTO_CARO
    multiplicador_input = Decimal("2") if longo else Decimal("1")
    multiplicador_output = Decimal("1.5") if longo else Decimal("1")
    custo = (
        Decimal(uso["input_tokens"]) / Decimal(1_000_000)
        * Decimal(str(PRECO_INPUT_USD_POR_MILHAO))
        * Decimal(str(MULTIPLICADOR_DE_ESCRITA_DE_CACHE))
        * multiplicador_input
        + Decimal(uso["output_tokens"]) / Decimal(1_000_000)
        * Decimal(str(PRECO_OUTPUT_USD_POR_MILHAO))
        * multiplicador_output
        + Decimal(chamadas_web)
        * Decimal(str(PRECO_WEB_SEARCH_USD_POR_CHAMADA))
    )
    return float(custo.quantize(Decimal("0.000001"), rounding=ROUND_CEILING))


def _data_ou_nulo(valor):
    if valor is None:
        return None
    if not isinstance(valor, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", valor):
        raise ErroDoScout("published_at fora de AAAA-MM-DD")
    try:
        return dt.date.fromisoformat(valor).isoformat()
    except ValueError as erro:
        raise ErroDoScout("published_at invalida") from erro


def _texto_limitado(valor, campo, minimo, maximo):
    if not isinstance(valor, str):
        raise ErroDoScout("{} fora do contrato".format(campo))
    normalizado = unicodedata.normalize("NFC", valor).strip()
    if (not minimo <= len(normalizado) <= maximo
            or any(unicodedata.category(caractere).startswith("C")
                   for caractere in normalizado)):
        raise ErroDoScout("{} fora do contrato".format(campo))
    return normalizado


def _lista_de_textos(valor, campo, maximo_itens, maximo_caracteres):
    if not isinstance(valor, list) or len(valor) > maximo_itens:
        raise ErroDoScout("{} fora do contrato".format(campo))
    return [
        _texto_limitado(item, campo, 1, maximo_caracteres)
        for item in valor
    ]


def _query_sem_rastreamento(query):
    try:
        pares = urllib.parse.parse_qsl(
            query, keep_blank_values=True, max_num_fields=64)
    except ValueError as erro:
        raise ErroDoScout("Query da URL candidata fora do contrato") from erro
    filtrados = [
        (chave, valor) for chave, valor in pares
        if not chave.lower().startswith("utm_")
        and chave.lower() not in PARAMETROS_DE_RASTREAMENTO
    ]
    return urllib.parse.urlencode(filtrados, doseq=True)


def _url_canonica(url, host_raiz=None):
    if (not isinstance(url, str)
            or any(ord(caractere) <= 32 or ord(caractere) > 126
                   for caractere in url)):
        raise ErroDoScout("URL candidata nao e HTTPS canonica")
    try:
        partes = urllib.parse.urlsplit(url)
    except (TypeError, ValueError, AttributeError) as erro:
        raise ErroDoScout("URL candidata nao e HTTPS canonica") from erro
    host = host_da_url(url)
    if (not host
            or not re.fullmatch(
                r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
                r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", host)
            or (host_raiz and not _host_no_escopo(host, host_raiz))
            or partes.fragment
            or not re.fullmatch(
                r"(?:/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?", partes.path)
            or re.search(r"%(?![0-9a-f]{2})", partes.path, re.IGNORECASE)):
        raise ErroDoScout("URL candidata nao e HTTPS canonica")
    if re.search(
            r"%(?:0[0-9a-f]|1[0-9a-f]|7f|25|2f|3f|23|5c)",
            partes.path, flags=re.IGNORECASE):
        raise ErroDoScout("URL candidata tem escape de caminho proibido")
    query = _query_sem_rastreamento(partes.query)
    if query:
        raise ErroDoScout(
            "URL candidata tem query semantica sem contrato especifico")
    caminho = partes.path or "/"
    segmentos = [
        urllib.parse.unquote(segmento).lower()
        for segmento in caminho.split("/")
    ]
    if any(segmento in {".", ".."} for segmento in segmentos):
        raise ErroDoScout("URL candidata contem dot-segment")
    return urllib.parse.urlunsplit((
        "https", host, caminho.rstrip("/") or "/", "", ""))


def validar_saida(saida, fontes, pautas, urls_pesquisadas=None, hoje=None):
    if not isinstance(saida, dict) or set(saida) != {
            "summary", "candidates", "coverage_gaps"}:
        raise ErroDoScout("Saida nao corresponde ao contrato")
    if not isinstance(saida["candidates"], list):
        raise ErroDoScout("candidates nao e lista")
    if len(saida["candidates"]) > MAXIMO_DE_CANDIDATOS:
        raise ErroDoScout("Candidatos excedem o teto")
    resumo = _texto_limitado(saida["summary"], "summary", 1, 800)
    lacunas = _lista_de_textos(
        saida["coverage_gaps"], "coverage_gaps", 12, 240)

    ids_de_pauta = {p["id"] for p in pautas}
    def fonte_para_host(host):
        correspondencias = [
            fonte for fonte in fontes.values()
            if _host_no_escopo(host, fonte["host"])
        ]
        if len(correspondencias) != 1:
            return None
        return correspondencias[0]

    hoje = hoje or dt.datetime.now(dt.timezone.utc).date()
    if isinstance(hoje, dt.datetime):
        hoje = hoje.date()
    if not isinstance(hoje, dt.date):
        raise TypeError("hoje deve ser date")
    pesquisadas_canonicas = None
    if urls_pesquisadas is not None:
        pesquisadas_canonicas = set()
        for url_pesquisada in urls_pesquisadas:
            fonte_pesquisada = fonte_para_host(host_da_url(url_pesquisada))
            if fonte_pesquisada is None:
                raise ErroDoScout("Busca consultou fonte fora do allowlist")
            canonica_pesquisada = _url_canonica(
                url_pesquisada, fonte_pesquisada["host"])
            pesquisadas_canonicas.add(canonica_pesquisada)
    vistas = set()
    normalizados = []
    for candidato in saida["candidates"]:
        if not isinstance(candidato, dict):
            raise ErroDoScout("Candidato nao e objeto")
        if set(candidato) != set(CAMPOS_CANDIDATO):
            raise ErroDoScout("Campos do candidato fora do contrato")
        titulo = _texto_limitado(candidato["title"], "title", 1, 240)
        publisher = _texto_limitado(
            candidato["publisher"], "publisher", 1, 120)
        topic_id = _texto_limitado(
            candidato["topic_id"], "topic_id", 1, 120)
        origin_type = _texto_limitado(
            candidato["origin_type"], "origin_type", 1, 40)
        role = _texto_limitado(candidato["role"], "role", 1, 40)
        region = _texto_limitado(candidato["region"], "region", 1, 40)
        evidence_status = _texto_limitado(
            candidato["evidence_status"], "evidence_status", 1, 40)
        facetas = _lista_de_textos(
            candidato["candidate_facets"], "candidate_facets", 8, 80)
        atomic_claim = _texto_limitado(
            candidato["atomic_claim"], "atomic_claim", 1, 500)
        why_relevant = _texto_limitado(
            candidato["why_relevant"], "why_relevant", 1, 500)
        missing_to_verify = _texto_limitado(
            candidato["missing_to_verify"], "missing_to_verify", 1, 500)
        url = candidato.get("url")
        if not isinstance(url, str) or len(url) > 2048:
            raise ErroDoScout("URL candidata fora do contrato")
        fonte = fonte_para_host(host_da_url(url))
        if fonte is None:
            raise ErroDoScout("Candidato fora do allowlist")
        canonica = _url_canonica(url, fonte["host"])
        if canonica in vistas:
            raise ErroDoScout("URL candidata repetida")
        if (pesquisadas_canonicas is not None
                and canonica not in pesquisadas_canonicas):
            raise ErroDoScout("URL candidata nao consta nas fontes da busca")
        vistas.add(canonica)
        if topic_id not in ids_de_pauta:
            raise ErroDoScout("Candidato aponta pauta desconhecida")
        if evidence_status != "candidate_only":
            raise ErroDoScout("Scout tentou promover candidato a evidencia")
        if candidato.get("requires_human_review") is not True:
            raise ErroDoScout("Candidato sem revisao humana obrigatoria")
        if origin_type not in ORIGENS:
            raise ErroDoScout("origin_type fora do contrato")
        if role not in PAPEIS:
            raise ErroDoScout("role fora do contrato")
        if region not in REGIOES:
            raise ErroDoScout("region fora do contrato")
        published_at = _data_ou_nulo(candidato.get("published_at"))
        if published_at is not None and dt.date.fromisoformat(published_at) > hoje:
            raise ErroDoScout("published_at esta no futuro")
        texto = " ".join(item.lower() for item in (
            atomic_claim, why_relevant, missing_to_verify))
        if any(expressao in texto for expressao in VOCABULARIO_PROIBIDO):
            raise ErroDoScout("Candidato usa vocabulario preditivo proibido")
        copia = {campo: candidato[campo] for campo in CAMPOS_CANDIDATO}
        copia.update({
            "title": titulo,
            "url": canonica,
            "publisher": publisher,
            "topic_id": topic_id,
            "published_at": published_at,
            "origin_type": origin_type,
            "role": role,
            "region": region,
            "candidate_facets": facetas,
            "atomic_claim": atomic_claim,
            "why_relevant": why_relevant,
            "missing_to_verify": missing_to_verify,
            "evidence_status": evidence_status,
        })
        copia["consulted_source_url"] = canonica
        copia["source_id"] = fonte["id"]
        normalizados.append(copia)

    return {
        "summary": "{} candidatos privados aguardam revisao humana.".format(
            len(normalizados)),
        "candidates": normalizados,
        "coverage_gaps": lacunas,
    }


def executar(args):
    caminhos_de_entrada = {
        Path(args.fontes).resolve(), Path(args.pautas).resolve(),
    }
    caminhos_de_saida = {
        Path(args.saida).resolve(), Path(args.recibo).resolve(),
    }
    if (len(caminhos_de_saida) != 2
            or caminhos_de_entrada & caminhos_de_saida):
        raise SystemExit(
            "saida e recibo devem ser distintos e nao podem sobrescrever os CSVs")
    chave = os.environ.get("OPENAI_SCOUT_API_KEY", "").strip()
    if not _credencial_openai_valida(chave):
        raise SystemExit("OPENAI_SCOUT_API_KEY ausente ou invalida")
    projeto = os.environ.get("OPENAI_SCOUT_PROJECT_ID", "").strip()
    if not _projeto_openai_valido(projeto):
        raise SystemExit("OPENAI_SCOUT_PROJECT_ID ausente ou invalido")
    fontes = carregar_fontes(args.fontes)
    pautas = carregar_pautas(args.pautas)
    payload = montar_payload(fontes, pautas)
    recibo = {
        "contract": "scout_execution_receipt_v1",
        "call_started": False,
        "billing_status": "not_started",
        "status": "prepared",
        "prepared_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "model_requested": MODELO,
        "service_tier_requested": SERVICE_TIER,
        "project_id": projeto,
        "prompt_version": VERSAO_DO_PROMPT,
        "prompt_sha256": hash_do_prompt(fontes, pautas),
        "code_sha256": _codigo_sha(),
        "repository_sha": _repository_sha(),
        "source_registry_sha256": _sha256_do_arquivo(args.fontes),
        "topics_registry_sha256": _sha256_do_arquivo(args.pautas),
        "allowed_domains": sorted({f["host"] for f in fontes.values()}),
    }
    _escrever_json_atomico(args.recibo, recibo)
    inicio = time.monotonic()
    recibo.update({
        "call_started": True,
        "billing_status": "possible",
        "status": "request_started",
        "request_started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    })
    _escrever_json_atomico(args.recibo, recibo)
    try:
        resposta = chamar_openai(payload, chave, projeto)
    except BaseException:
        recibo.update({
            "billing_status": "unknown",
            "status": "request_failed_or_uncertain",
            "latency_seconds": round(time.monotonic() - inicio, 3),
        })
        _escrever_json_atomico(args.recibo, recibo)
        raise

    envelope = resposta if isinstance(resposta, dict) else {}
    recibo.update({
        "billing_status": "response_received",
        "status": "response_received",
        "response_id": envelope.get("id"),
        "model_resolved": envelope.get("model"),
        "service_tier_resolved": envelope.get("service_tier"),
        "usage_available": isinstance(envelope.get("usage"), dict),
        "latency_seconds": round(time.monotonic() - inicio, 3),
    })
    # Preserva os metadados de conciliacao antes de qualquer gate semantico.
    # Assim, uma resposta faturada que falhe por tier, URL ou JSON candidato
    # continua auditavel sem persistir texto bruto do modelo.
    try:
        uso_disponivel = _uso_auditavel(resposta)
    except ErroDoScout:
        uso_disponivel = None
    chamadas_disponiveis = _numero_de_chamadas_web_disponivel(envelope)
    if uso_disponivel is not None:
        recibo["usage"] = uso_disponivel
    if chamadas_disponiveis is not None:
        recibo["web_search_calls"] = chamadas_disponiveis
    if (uso_disponivel is not None and chamadas_disponiveis is not None
            and _rota_com_tarifa_conhecida(envelope)):
        recibo.update({
            "cost_reconciliation_status": "upper_bound_available",
            "pricing_version": VERSAO_DOS_PRECOS,
            "estimated_cost_usd_upper_bound": _custo_maximo_estimado(
                uso_disponivel, chamadas_disponiveis),
        })
    else:
        recibo["cost_reconciliation_status"] = "unavailable"
        if uso_disponivel is None:
            recibo["cost_reconciliation_reason"] = "usage_not_auditable"
        elif chamadas_disponiveis is None:
            recibo["cost_reconciliation_reason"] = "web_calls_not_auditable"
        elif not _modelo_luna_precificado(envelope.get("model")):
            recibo["cost_reconciliation_reason"] = "unpriced_resolved_model"
        else:
            recibo["cost_reconciliation_reason"] = "unpriced_service_tier"
    _escrever_json_atomico(args.recibo, recibo)
    try:
        uso, urls_pesquisadas, chamadas_web = _auditar_resposta(resposta)
        try:
            bruta = json.loads(extrair_texto(resposta))
        except json.JSONDecodeError as erro:
            raise ErroDoScout("output_text nao e JSON valido") from erro
        validada = validar_saida(
            bruta, fontes, pautas,
            urls_pesquisadas=urls_pesquisadas)
    except BaseException:
        recibo["status"] = "validation_failed"
        _escrever_json_atomico(args.recibo, recibo)
        raise

    agora = dt.datetime.now(dt.timezone.utc).isoformat()
    artefato = {
        "contract": "candidate_only",
        "generated_at": agora,
        "model_requested": MODELO,
        "model_resolved": resposta.get("model"),
        "service_tier_requested": SERVICE_TIER,
        "service_tier_resolved": resposta.get("service_tier"),
        "prompt_version": VERSAO_DO_PROMPT,
        "prompt_sha256": hash_do_prompt(fontes, pautas),
        "code_sha256": recibo["code_sha256"],
        "repository_sha": recibo["repository_sha"],
        "source_registry_sha256": recibo["source_registry_sha256"],
        "topics_registry_sha256": recibo["topics_registry_sha256"],
        "response_id": resposta.get("id"),
        "usage": uso,
        "web_search_calls": chamadas_web,
        "pricing_version": VERSAO_DOS_PRECOS,
        "cost_reconciliation_status": "upper_bound_available",
        "estimated_cost_usd_upper_bound": _custo_maximo_estimado(
            uso, chamadas_web),
        "latency_seconds": round(time.monotonic() - inicio, 3),
        "allowed_domains": sorted({f["host"] for f in fontes.values()}),
        "retention_days": retencao_do_artefato(fontes),
        "source_contracts": [
            {
                "source_id": fonte["id"],
                "base_url": fonte["base_url"],
                "domain_tree": fonte["host"],
                "url_scope": fonte["url_scope"],
                "method": fonte["metodo"],
                "ai_processing": fonte["ai_processing"],
                "openai_retention_mode": fonte["openai_retention_mode"],
                "display_rights": fonte["display_rights"],
                "raw_retention_days": fonte["retencao_dias"],
                "fact_retention_days": fonte["retencao_fatos_dias"],
                "terms_url": fonte["termos_url"],
                "terms_version": fonte["termos_versao"],
                "terms_reviewed_at": fonte["termos_revisados_em"],
                "authorization_sha256": fonte["autorizacao_sha256"],
                "approved_by": fonte["aprovada_por"],
                "approved_at": fonte["aprovada_em"],
                "authorization_expires_at": fonte[
                    "autorizacao_expira_em"],
            }
            for fonte in sorted(fontes.values(), key=lambda item: item["id"])
        ],
        "result": validada,
    }
    try:
        _escrever_json_atomico(args.saida, artefato)
    except BaseException:
        recibo["status"] = "validated_output_write_failed"
        _escrever_json_atomico(args.recibo, recibo)
        raise
    recibo.update({
        "status": "validated",
        "validated_at": agora,
        "candidate_count": len(validada["candidates"]),
        "usage": uso,
        "web_search_calls": chamadas_web,
        "pricing_version": VERSAO_DOS_PRECOS,
        "cost_reconciliation_status": "upper_bound_available",
        "estimated_cost_usd_upper_bound": artefato[
            "estimated_cost_usd_upper_bound"],
    })
    _escrever_json_atomico(args.recibo, recibo)
    return artefato


def main():
    raiz = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fontes", type=Path, default=raiz / "anexos" / "fontes_radar.csv")
    parser.add_argument(
        "--pautas", type=Path, default=raiz / "anexos" / "pautas_radar.csv")
    parser.add_argument(
        "--saida", type=Path, default=Path("radar-scout.json"))
    parser.add_argument(
        "--recibo", type=Path, default=Path("radar-scout-receipt.json"))
    parser.add_argument(
        "--verificar-prontidao", action="store_true",
        help="valida o registro sem rede nem chave e imprime ready/blocked")
    parser.add_argument(
        "--retencao-artefato", action="store_true",
        help="imprime o menor TTL elegivel, limitado a sete dias")
    args = parser.parse_args()
    if args.verificar_prontidao:
        print("ready" if verificar_prontidao(
            args.fontes, pautas=args.pautas) else "blocked")
        return
    if args.retencao_artefato:
        print(retencao_do_artefato(carregar_fontes(args.fontes)))
        return
    artefato = executar(args)
    print("Scout privado: {} candidatos; {} tokens; {:.1f}s".format(
        len(artefato["result"]["candidates"]),
        int((artefato["usage"] or {}).get("total_tokens", 0)),
        artefato["latency_seconds"],
    ))


if __name__ == "__main__":
    main()
