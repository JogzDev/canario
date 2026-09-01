#!/usr/bin/env python3
"""Contrato offline do scout: rights gate, allowlist e abstencao publica."""

import csv
import datetime as dt
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import urllib.error


RAIZ = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(RAIZ / "ferramentas"))

import pesquisar_radar_luna as scout


def escrever_csv(caminho, linhas):
    with open(caminho, "w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(
            arquivo, fieldnames=scout.CAMPOS_DO_REGISTRO)
        escritor.writeheader()
        escritor.writerows(linhas)


def fonte(**alteracoes):
    linha = {
        "id": "allowed",
        "nome": "Allowed",
        "sensor": "editorial",
        "tier": "T1",
        "metodo": "hosted_web_search_domain_tree",
        "status": "green",
        "ai_processing": "full_text",
        "openai_retention_mode": "standard_30d",
        "display_rights": "facts_and_canonical_link",
        "retencao_dias": "30",
        "retencao_fatos_dias": "30",
        "base_url": "https://allowed.example",
        "url_scope": "domain_tree",
        "termos_url": "https://allowed.example/terms",
        "termos_versao": "2026-08-31",
        "termos_revisados_em": "2026-08-31",
        "autorizacao_sha256": "a" * 64,
        "aprovada_por": "fixture-reviewer",
        "aprovada_em": "2026-08-31",
        "autorizacao_expira_em": "2027-08-31",
        "observacao": "Fixture local sem acesso de rede",
        "ativa": "true",
    }
    linha.update(alteracoes)
    return linha


def candidato(url="https://allowed.example/report/1"):
    return {
        "topic_id": "cores",
        "title": "A report",
        "url": url,
        "publisher": "Allowed",
        "published_at": "2026-08-30",
        "origin_type": "original_report",
        "role": "supports",
        "region": "international",
        "candidate_facets": ["soft yellow"],
        "atomic_claim": "The report records more soft yellow items in its panel.",
        "why_relevant": "It may be compared with the Brazilian retail panel.",
        "missing_to_verify": "Open the canonical page and verify its methodology.",
        "evidence_status": "candidate_only",
        "requires_human_review": True,
    }


def esperar_erro(funcao, trecho):
    try:
        funcao()
    except (ValueError, scout.ErroDoScout, SystemExit) as erro:
        assert trecho in str(erro), (trecho, str(erro))
        return
    raise AssertionError("esperava erro contendo {!r}".format(trecho))


def main():
    pautas_reais = scout.carregar_pautas(
        RAIZ / "anexos" / "pautas_radar.csv")
    assert len(pautas_reais) == 8
    assert {pauta["id"] for pauta in pautas_reais} >= {
        "cores_e_combinacoes", "fibras_e_materiais",
        "brasil_e_exterior", "recuos_e_desaparecimentos",
    }

    with tempfile.TemporaryDirectory(prefix="radar-scout-test-") as temporaria:
        registro = Path(temporaria) / "fontes.csv"
        escrever_csv(registro, [
            fonte(),
            fonte(
                id="pinterest", nome="Pinterest",
                base_url="https://pinterest.com", status="red",
                ai_processing="none", openai_retention_mode="none",
                display_rights="none"),
            fonte(
                id="inactive", nome="Inactive",
                base_url="https://inactive.example", ai_processing="full_text",
                ativa="false"),
        ])
        fontes = scout.carregar_fontes(
            registro, hoje=dt.date(2026, 8, 31))
        assert set(fontes) == {"allowed"}, fontes
        assert fontes["allowed"]["dominio"] == "allowed.example"
        assert scout.verificar_prontidao(
            registro, hoje=dt.date(2026, 8, 31)) is True
        assert scout.retencao_do_artefato(fontes) == 7

        pautas = [{
            "id": "cores", "fenomeno": "cor", "consulta": "women fashion color",
        }]
        payload = scout.montar_payload(fontes, pautas)
        ferramenta = payload["tools"][0]
        assert ferramenta["filters"]["allowed_domains"] == ["allowed.example"]
        assert payload["store"] is False
        assert payload["service_tier"] == "default"
        assert payload["max_tool_calls"] == 8
        serializado = json.dumps(payload, ensure_ascii=False).lower()
        assert "pinterest.com" not in serializado
        assert "candidate_only" in serializado

        saida = {
            "summary": "One candidate for human review.",
            "candidates": [candidato()],
            "coverage_gaps": ["No Brazilian observation yet."],
        }
        normalizada = scout.validar_saida(
            saida, fontes, pautas,
            urls_pesquisadas={
                "https://allowed.example/report/1?utm_source=search"})
        item = normalizada["candidates"][0]
        assert item["source_id"] == "allowed"
        assert item["url"] == "https://allowed.example/report/1"

        esperar_erro(
            lambda: scout.validar_saida(
                saida, fontes, pautas,
                urls_pesquisadas={"https://allowed.example/report/2"}),
            "nao consta nas fontes")

        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [candidato(
                    "https://allowed.example/report?id=1")]},
                fontes, pautas,
                urls_pesquisadas={"https://allowed.example/report?id=1"}),
            "query semantica")

        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [candidato(
                    "https://allowed.example/a/%252e%252e/secret")]},
                fontes, pautas,
                urls_pesquisadas={
                    "https://allowed.example/a/%252e%252e/secret"}),
            "escape de caminho proibido")

        for url_invalida in (
                "https://allowed.example/a/../secret",
                "https://allowed.example/report/%ZZ",
                "https://allowed.example/report/1#private-fragment",
                "https://allowed.example/relatório"):
            esperar_erro(
                lambda url=url_invalida: scout.validar_saida(
                    {**saida, "candidates": [candidato(url)]},
                    fontes, pautas, urls_pesquisadas={url}),
                "URL candidata")

        esperar_erro(
            lambda: scout.validar_saida(
                saida, fontes, pautas,
                urls_pesquisadas={
                    "https://allowed.example/report/1",
                    "https://evil.example/report",
                }),
            "fora do allowlist")

        esperar_erro(
            lambda: scout.validar_saida(
                saida, fontes, pautas, urls_pesquisadas=set()),
            "nao consta nas fontes")

        campo_extra = candidato()
        campo_extra["raw_text"] = "conteudo que nao pode ser persistido"
        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [campo_extra]}, fontes, pautas),
            "Campos do candidato")

        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [candidato("https://pinterest.com/pin/1")]},
                fontes, pautas),
            "fora do allowlist")

        promovido = candidato()
        promovido["evidence_status"] = "approved"
        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [promovido]}, fontes, pautas),
            "promover candidato")

        previsao = candidato()
        previsao["atomic_claim"] = "This color will sell next season."
        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [previsao]}, fontes, pautas),
            "vocabulario preditivo")

        invisivel = candidato()
        invisivel["atomic_claim"] = "Claim with bidi override \u202e hidden"
        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [invisivel]}, fontes, pautas),
            "atomic_claim fora do contrato")

        data_inventada = candidato()
        data_inventada["published_at"] = "2026-02-30"
        esperar_erro(
            lambda: scout.validar_saida(
                {**saida, "candidates": [data_inventada]}, fontes, pautas),
            "published_at invalida")

        # Falha transitoria nao dispara outra pesquisa paga automaticamente.
        chamadas = []
        urlopen_original = scout.urllib.request.urlopen
        try:
            def falhar_uma_vez(*args, **kwargs):
                chamadas.append((args, kwargs))
                raise urllib.error.URLError("fixture offline")

            scout.urllib.request.urlopen = falhar_uma_vez
            esperar_erro(
                lambda: scout.chamar_openai(
                    {"model": "fixture"}, "segredo", "proj_fixture123"),
                "Falha de rede")
        finally:
            scout.urllib.request.urlopen = urlopen_original
        assert len(chamadas) == 1, chamadas

        subdominio = candidato(
            "https://news.allowed.example/report/1")
        normalizado_subdominio = scout.validar_saida(
            {**saida, "candidates": [subdominio]}, fontes, pautas,
            urls_pesquisadas={
                "https://news.allowed.example/report/1"})
        assert normalizado_subdominio["candidates"][0]["url"] == (
            "https://news.allowed.example/report/1")

        arquivo_pautas = Path(temporaria) / "pautas.csv"
        with open(arquivo_pautas, "w", encoding="utf-8", newline="") as arquivo:
            escritor = csv.DictWriter(
                arquivo, fieldnames=scout.CAMPOS_DA_PAUTA)
            escritor.writeheader()
            escritor.writerow({
                "id": "cores",
                "fenomeno": "cor",
                "consulta_pt": "cores na moda feminina",
                "consulta_en": "women fashion colors",
                "ativa": "true",
            })

        resposta_fixture = {
            "id": "resp_fixture",
            "status": "completed",
            "model": scout.MODELO,
            "service_tier": "default",
            "usage": {
                "input_tokens": 100,
                "output_tokens": 50,
                "total_tokens": 150,
            },
            "output": [
                {
                    "type": "web_search_call",
                    "status": "completed",
                    "action": {
                        "type": "search",
                        "sources": [{
                            "url": "https://allowed.example/report/1",
                        }],
                    },
                },
                {
                    "type": "message",
                    "content": [{
                        "type": "output_text",
                        "text": json.dumps(saida),
                    }],
                },
            ],
        }
        uso, urls, n_buscas = scout._auditar_resposta(resposta_fixture)
        assert uso["total_tokens"] == 150
        assert urls == {"https://allowed.example/report/1"}
        assert n_buscas == 1

        resposta_id_invalido = json.loads(json.dumps(resposta_fixture))
        resposta_id_invalido["id"] = "request-without-response-prefix"
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_id_invalido),
            "id auditavel")

        resposta_usage_absurdo = json.loads(json.dumps(resposta_fixture))
        resposta_usage_absurdo["usage"]["input_tokens"] = (
            scout.MAXIMO_TOKENS_AUDITAVEIS + 1)
        resposta_usage_absurdo["usage"]["total_tokens"] = (
            scout.MAXIMO_TOKENS_AUDITAVEIS + 51)
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_usage_absurdo),
            "input_tokens valido")

        resposta_dupla = json.loads(json.dumps(resposta_fixture))
        resposta_dupla["output"].append({
            "type": "message",
            "content": [{"type": "output_text", "text": "{}"}],
        })
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_dupla),
            "unico output_text")

        resposta_com_recusa_tardia = json.loads(json.dumps(resposta_fixture))
        resposta_com_recusa_tardia["output"][1]["content"].append({
            "type": "refusal", "refusal": "fixture",
        })
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_com_recusa_tardia),
            "recusou")

        # As tres acoes oficiais sao auditaveis. open/find nao precisam de
        # ``sources``, mas suas URLs entram no mesmo gate de allowlist.
        resposta_com_navegacao = json.loads(json.dumps(resposta_fixture))
        resposta_com_navegacao["output"][1:1] = [
            {
                "type": "web_search_call",
                "status": "completed",
                "action": {
                    "type": "open_page",
                    "url": "https://news.allowed.example/report/1",
                },
            },
            {
                "type": "web_search_call",
                "status": "completed",
                "action": {
                    "type": "find_in_page",
                    "url": "https://allowed.example/report/1",
                    "pattern": "yellow",
                },
            },
        ]
        _, urls_navegadas, chamadas_navegadas = scout._auditar_resposta(
            resposta_com_navegacao)
        assert chamadas_navegadas == 3
        assert urls_navegadas == {
            "https://allowed.example/report/1",
            "https://news.allowed.example/report/1",
        }
        scout.validar_saida(
            saida, fontes, pautas, urls_pesquisadas=urls_navegadas)

        resposta_fora_do_escopo = json.loads(
            json.dumps(resposta_com_navegacao))
        resposta_fora_do_escopo["output"][1]["action"]["url"] = (
            "https://evil.example/report/1")
        _, urls_fora, _ = scout._auditar_resposta(resposta_fora_do_escopo)
        esperar_erro(
            lambda: scout.validar_saida(
                saida, fontes, pautas, urls_pesquisadas=urls_fora),
            "fora do allowlist")

        resposta_acao_desconhecida = json.loads(json.dumps(resposta_fixture))
        resposta_acao_desconhecida["output"][0]["action"] = {
            "type": "crawl",
            "url": "https://allowed.example/report/1",
        }
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_acao_desconhecida),
            "Tipo de acao web desconhecido")

        resposta_tier_incorreto = json.loads(json.dumps(resposta_fixture))
        resposta_tier_incorreto["service_tier"] = "priority"
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_tier_incorreto),
            "Service tier resolvido")

        resposta_modelo_incorreto = json.loads(json.dumps(resposta_fixture))
        resposta_modelo_incorreto["model"] = "gpt-5.6-sol"
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_modelo_incorreto),
            "Modelo resolvido fora da tarifa Luna")
        resposta_snapshot = json.loads(json.dumps(resposta_fixture))
        resposta_snapshot["model"] = scout.MODELO + "-2026-09-01"
        scout._auditar_resposta(resposta_snapshot)
        resposta_snapshot_invalido = json.loads(json.dumps(resposta_fixture))
        resposta_snapshot_invalido["model"] = scout.MODELO + "-2026-99-99"
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_snapshot_invalido),
            "Modelo resolvido")

        # O teto trata todo input como cache write (1,25x), aplica os
        # multiplicadores de long context e sempre arredonda para cima.
        assert scout._custo_maximo_estimado({
            "input_tokens": 200_000,
            "output_tokens": 200_000,
        }, 2) == 0.31
        assert scout._custo_maximo_estimado({
            "input_tokens": 272_001,
            "output_tokens": 100_000,
        }, 1) == 0.326001

        args = SimpleNamespace(
            fontes=registro,
            pautas=arquivo_pautas,
            saida=Path(temporaria) / "saida.json",
            recibo=Path(temporaria) / "recibo.json",
        )
        args_sobrescreve_contrato = SimpleNamespace(
            fontes=registro,
            pautas=arquivo_pautas,
            saida=registro,
            recibo=Path(temporaria) / "recibo-conflito.json",
        )
        esperar_erro(
            lambda: scout.executar(args_sobrescreve_contrato),
            "nao podem sobrescrever os CSVs")
        chamar_original = scout.chamar_openai
        chave_anterior = os.environ.get("OPENAI_SCOUT_API_KEY")
        projeto_anterior = os.environ.get("OPENAI_SCOUT_PROJECT_ID")
        try:
            os.environ["OPENAI_SCOUT_API_KEY"] = "fixture-secret-123456"
            os.environ["OPENAI_SCOUT_PROJECT_ID"] = "proj_fixture123"
            scout.chamar_openai = lambda payload, chave, projeto: resposta_fixture
            artefato = scout.executar(args)
        finally:
            scout.chamar_openai = chamar_original
            if chave_anterior is None:
                os.environ.pop("OPENAI_SCOUT_API_KEY", None)
            else:
                os.environ["OPENAI_SCOUT_API_KEY"] = chave_anterior
            if projeto_anterior is None:
                os.environ.pop("OPENAI_SCOUT_PROJECT_ID", None)
            else:
                os.environ["OPENAI_SCOUT_PROJECT_ID"] = projeto_anterior
        recibo = json.loads(args.recibo.read_text(encoding="utf-8"))
        assert recibo["status"] == "validated"
        assert recibo["billing_status"] == "response_received"
        assert recibo["service_tier_requested"] == "default"
        assert recibo["service_tier_resolved"] == "default"
        assert recibo["web_search_calls"] == 1
        assert artefato["web_search_calls"] == 1
        assert artefato["service_tier_requested"] == "default"
        assert artefato["service_tier_resolved"] == "default"
        assert artefato["estimated_cost_usd_upper_bound"] > 0
        assert artefato["source_contracts"][0]["method"] == (
            "hosted_web_search_domain_tree")
        assert artefato["source_registry_sha256"]

        resposta_invalida = json.loads(json.dumps(resposta_fixture))
        resposta_invalida["output"][1]["content"][0]["text"] = json.dumps({
            **saida,
            "candidates": [candidato("https://allowed.example/report/2")],
        })
        args_falha = SimpleNamespace(
            fontes=registro,
            pautas=arquivo_pautas,
            saida=Path(temporaria) / "saida-invalida.json",
            recibo=Path(temporaria) / "recibo-invalido.json",
        )
        try:
            os.environ["OPENAI_SCOUT_API_KEY"] = "fixture-secret-123456"
            os.environ["OPENAI_SCOUT_PROJECT_ID"] = "proj_fixture123"
            scout.chamar_openai = lambda payload, chave, projeto: resposta_invalida
            esperar_erro(lambda: scout.executar(args_falha), "nao consta")
        finally:
            scout.chamar_openai = chamar_original
            if chave_anterior is None:
                os.environ.pop("OPENAI_SCOUT_API_KEY", None)
            else:
                os.environ["OPENAI_SCOUT_API_KEY"] = chave_anterior
            if projeto_anterior is None:
                os.environ.pop("OPENAI_SCOUT_PROJECT_ID", None)
            else:
                os.environ["OPENAI_SCOUT_PROJECT_ID"] = projeto_anterior
        recibo_invalido = json.loads(
            args_falha.recibo.read_text(encoding="utf-8"))
        assert recibo_invalido["status"] == "validation_failed"
        assert recibo_invalido["billing_status"] == "response_received"
        assert recibo_invalido["usage"] == resposta_fixture["usage"]
        assert recibo_invalido["web_search_calls"] == 1
        assert recibo_invalido["pricing_version"] == scout.VERSAO_DOS_PRECOS
        assert recibo_invalido["estimated_cost_usd_upper_bound"] > 0
        assert recibo_invalido["service_tier_resolved"] == "default"
        assert not args_falha.saida.exists()

        # Uma resposta faturada em rota sem tarifa conhecida preserva usage e
        # chamadas, mas nao recebe um teto Luna/default enganoso.
        resposta_rota_invalida = json.loads(json.dumps(resposta_fixture))
        resposta_rota_invalida["service_tier"] = "priority"
        args_rota = SimpleNamespace(
            fontes=registro,
            pautas=arquivo_pautas,
            saida=Path(temporaria) / "saida-rota-invalida.json",
            recibo=Path(temporaria) / "recibo-rota-invalida.json",
        )
        try:
            os.environ["OPENAI_SCOUT_API_KEY"] = "fixture-secret-123456"
            os.environ["OPENAI_SCOUT_PROJECT_ID"] = "proj_fixture123"
            scout.chamar_openai = (
                lambda payload, chave, projeto: resposta_rota_invalida)
            esperar_erro(lambda: scout.executar(args_rota), "Service tier")
        finally:
            scout.chamar_openai = chamar_original
            if chave_anterior is None:
                os.environ.pop("OPENAI_SCOUT_API_KEY", None)
            else:
                os.environ["OPENAI_SCOUT_API_KEY"] = chave_anterior
            if projeto_anterior is None:
                os.environ.pop("OPENAI_SCOUT_PROJECT_ID", None)
            else:
                os.environ["OPENAI_SCOUT_PROJECT_ID"] = projeto_anterior
        recibo_rota = json.loads(args_rota.recibo.read_text(encoding="utf-8"))
        assert recibo_rota["status"] == "validation_failed"
        assert recibo_rota["cost_reconciliation_status"] == "unavailable"
        assert recibo_rota["cost_reconciliation_reason"] == (
            "unpriced_service_tier")
        assert "estimated_cost_usd_upper_bound" not in recibo_rota

        resposta_nao_concluida = {
            **resposta_fixture,
            "status": "failed",
        }
        esperar_erro(
            lambda: scout._auditar_resposta(resposta_nao_concluida),
            "nao concluida")

        escrever_csv(registro, [
            fonte(
                id="internal", nome="Internal", tier="T0",
                metodo="curadoria_interna", base_url="",
                url_scope="internal",
                termos_url="GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md"),
        ])
        assert scout.verificar_prontidao(
            registro, hoje=dt.date(2026, 8, 31)) is False

        pautas_invalidas = Path(temporaria) / "pautas-invalidas.csv"
        pautas_invalidas.write_text(
            "id,coluna_errada\ncores,x\n", encoding="utf-8")
        esperar_erro(
            lambda: scout.verificar_prontidao(
                registro, pautas=pautas_invalidas,
                hoje=dt.date(2026, 8, 31)),
            "Cabecalho das pautas fora do contrato")

        escrever_csv(registro, [fonte(metodo="api_oficial")])
        assert scout.verificar_prontidao(
            registro, hoje=dt.date(2026, 8, 31)) is False

        escrever_csv(registro, [fonte(base_url="https://allowed.example/fashion")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                registro, hoje=dt.date(2026, 8, 31)),
            "origem inteira")

    print("OK: scout privado falha fechado antes de promover qualquer fonte")


if __name__ == "__main__":
    main()
