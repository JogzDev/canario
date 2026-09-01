#!/usr/bin/env python3
"""Contrato offline estrito do registro executável de fontes do radar."""

import csv
import datetime as dt
import hashlib
from pathlib import Path
import sys
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "ferramentas"))

import pesquisar_radar_luna as scout


DATA_DO_CONTRATO = dt.date(2026, 8, 31)
REGISTRO_REAL = RAIZ / "anexos" / "fontes_radar.csv"
CONTRATO_DE_GOVERNANCA = (
    RAIZ / "GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md")


def fonte(**alteracoes):
    linha = {
        "id": "fonte_teste",
        "nome": "Fonte de teste",
        "sensor": "cobertura_editorial",
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
        "observacao": "Fixture determinística sem rede",
        "ativa": "true",
    }
    linha.update(alteracoes)
    return linha


def interna(**alteracoes):
    linha = fonte(
        id="datadrobe_interna",
        nome="DataDrobe interna",
        sensor="curadoria_propria",
        tier="T0",
        metodo="curadoria_interna",
        display_rights="own_content",
        base_url="",
        url_scope="internal",
        termos_url="GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md",
        termos_versao="1.0.0",
    )
    linha.update(alteracoes)
    return linha


def escrever(caminho, linhas, campos=None):
    campos = campos or scout.CAMPOS_DO_REGISTRO
    with open(caminho, "w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(arquivo, fieldnames=campos)
        escritor.writeheader()
        escritor.writerows(linhas)


def esperar_erro(funcao, trecho):
    try:
        funcao()
    except (TypeError, ValueError, scout.ErroDoScout) as erro:
        assert trecho in str(erro), (trecho, str(erro))
        return
    raise AssertionError("esperava erro contendo {!r}".format(trecho))


def main():
    linhas_reais = scout.carregar_registro_fontes(
        REGISTRO_REAL, hoje=DATA_DO_CONTRATO)
    assert {linha["tier"] for linha in linhas_reais} == {
        "T0", "T1", "T2", "T3",
    }
    assert {linha["status"] for linha in linhas_reais} == {
        "green", "yellow", "red",
    }
    por_id = {linha["id"]: linha for linha in linhas_reais}
    interna_real = por_id["datadrobe_curadoria_interna"]
    assert interna_real["status"] == "green"
    assert interna_real["base_url"] == ""
    assert interna_real["url_scope"] == "internal"
    assert interna_real["metodo"] == "curadoria_interna"
    assert interna_real["openai_retention_mode"] == "standard_30d"
    assert interna_real["autorizacao_sha256"] == hashlib.sha256(
        CONTRATO_DE_GOVERNANCA.read_bytes()).hexdigest()
    assert interna_real["autorizacao_sha256"] != "0" * 64
    assert interna_real["aprovada_por"] == "jpscoliveira"
    assert interna_real["aprovada_em"] == dt.date(2026, 8, 31)
    assert interna_real["autorizacao_expira_em"] == dt.date(2027, 8, 31)
    assert interna_real["aprovada_em"] <= DATA_DO_CONTRATO
    assert interna_real["autorizacao_expira_em"] > DATA_DO_CONTRATO
    assert {linha["openai_retention_mode"] for linha in linhas_reais} <= {
        "none", "standard_30d",
    }
    assert all(
        linha["metodo"] != "hosted_web_search_domain_tree"
        or linha["url_scope"] == "domain_tree"
        for linha in linhas_reais)
    assert por_id["pinterest_trends_api"]["status"] == "red"
    assert por_id["guardian_open_platform_commercial"]["status"] == "yellow"
    assert por_id["youtube_data_api_curated"]["status"] == "yellow"
    esperar_erro(
        lambda: scout.carregar_fontes(
            REGISTRO_REAL, hoje=DATA_DO_CONTRATO),
        "Nenhuma fonte verde")

    with tempfile.TemporaryDirectory(prefix="fontes-radar-test-") as temporaria:
        caminho = Path(temporaria) / "fontes.csv"

        # Somente uma fonte web explicitamente green e vigente chega ao Scout.
        escrever(caminho, [
            fonte(),
            fonte(
                id="vermelha", status="red",
                base_url="https://red.example", ai_processing="facts"),
            fonte(
                id="amarela", status="yellow",
                base_url="https://yellow.example", ai_processing="facts"),
            fonte(
                id="somente_pacote_factual",
                base_url="https://facts.example", ai_processing="facts"),
            fonte(
                id="inativa", base_url="https://inactive.example",
                ativa="false"),
            interna(),
        ])
        liberadas = scout.carregar_fontes(caminho, hoje=DATA_DO_CONTRATO)
        assert set(liberadas) == {"fonte_teste"}, liberadas
        assert liberadas["fonte_teste"]["dominio"] == "allowed.example"

        # Enum desconhecido nunca e ignorado nem tratado como permissao futura.
        for campo, valor in (
                ("tier", "T4"),
                ("status", "approved"),
                ("ai_processing", "summary"),
                ("openai_retention_mode", "maybe"),
                ("openai_retention_mode", "mam_verified"),
                ("openai_retention_mode", "zdr_verified"),
                ("url_scope", "path_prefix"),
                ("display_rights", "fair_use")):
            escrever(caminho, [fonte(**{campo: valor})])
            esperar_erro(
                lambda: scout.carregar_registro_fontes(
                    caminho, hoje=DATA_DO_CONTRATO),
                "{} fora do enum".format(campo))

        escrever(caminho, [fonte(openai_retention_mode="none")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "processamento por IA exige modo")
        escrever(caminho, [fonte(retencao_dias="29")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "ao menos 30 dias")
        escrever(caminho, [fonte(
            ai_processing="none", openai_retention_mode="standard_30d")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "fonte sem IA deve usar")

        # O bloco de aprovacao e atomico, nominal, hasheado e estritamente
        # vigente: o proprio dia de expiracao ja bloqueia a fonte.
        escrever(caminho, [fonte(
            autorizacao_sha256="", aprovada_por="", aprovada_em="",
            autorizacao_expira_em="")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "fonte green exige aprovacao completa")
        escrever(caminho, [fonte(autorizacao_sha256="")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "aprovacao deve ser preenchida por inteiro")
        escrever(caminho, [fonte(autorizacao_sha256="A" * 64)])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "autorizacao_sha256 invalido")
        escrever(caminho, [fonte(
            autorizacao_expira_em=DATA_DO_CONTRATO.isoformat())])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "autorizacao expirada")

        for valor in ("yes", "TRUE"):
            escrever(caminho, [fonte(ativa=valor)])
            esperar_erro(
                lambda: scout.carregar_registro_fontes(
                    caminho, hoje=DATA_DO_CONTRATO),
                "ativa deve ser true ou false")

        escrever(caminho, [fonte(id="fonte inválida")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "id deve ser ASCII")
        escrever(caminho, [fonte(), fonte()])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "id repetido")

        # T1 e T2 expiram no inicio do 90o dia sem revisao. O limite e
        # deterministico e nao depende do relogio da maquina de CI.
        escrever(caminho, [fonte(termos_revisados_em="2026-06-03")])
        assert scout.carregar_registro_fontes(
            caminho, hoje=DATA_DO_CONTRATO)
        escrever(caminho, [fonte(termos_revisados_em="2026-06-02")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "revisao dos termos expirada")
        escrever(caminho, [interna(termos_revisados_em="2025-08-31")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "revisao dos termos expirada")

        escrever(caminho, [fonte(tier="T3")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "T3 nunca pode ser green")
        escrever(caminho, [fonte(display_rights="none")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "fonte green exige direito de exibicao")
        escrever(caminho, [fonte(retencao_fatos_dias="0")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "fonte green exige retencao factual positiva")
        escrever(caminho, [fonte(base_url="")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "base_url vazia so e aceita")

        escrever(caminho, [fonte(
            base_url="https://allowed.example/reports")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "origem inteira")
        escrever(caminho, [fonte(
            termos_url="https://allowed.example/terms?token=x")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "termos_url deve ser HTTPS")
        escrever(caminho, [fonte(url_scope="exact_host")])
        esperar_erro(
            lambda: scout.carregar_registro_fontes(
                caminho, hoje=DATA_DO_CONTRATO),
            "url_scope domain_tree")

        # Uma licença de API não é permissão para o hosted web search do host.
        escrever(caminho, [fonte(metodo="api_oficial")])
        esperar_erro(
            lambda: scout.carregar_fontes(caminho, hoje=DATA_DO_CONTRATO),
            "Nenhuma fonte verde")

        for campo, valor, trecho in (
                ("retencao_dias", "91", "excede 90"),
                ("retencao_fatos_dias", "3651", "excede 3650"),
                ("nome", "x" * 161, "entre 1 e 160")):
            escrever(caminho, [fonte(**{campo: valor})])
            esperar_erro(
                lambda: scout.carregar_registro_fontes(
                    caminho, hoje=DATA_DO_CONTRATO),
                trecho)

        # Ausencia e desconhecido bloqueiam por default: nao ha fallback de
        # dominio nem promocao de uma linha red com ai_processing=facts.
        escrever(caminho, [
            fonte(
                id="somente_vermelha", status="red",
                base_url="https://red.example"),
            interna(),
        ])
        esperar_erro(
            lambda: scout.carregar_fontes(caminho, hoje=DATA_DO_CONTRATO),
            "Nenhuma fonte verde")

    print(
        "OK: registro valida contrato hasheado, aprovacao, enums, "
        "expiracao e bloqueio default")


if __name__ == "__main__":
    main()
