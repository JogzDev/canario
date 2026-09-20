#!/usr/bin/env python3
"""Teste sem rede da sonda pública A57/A58."""

from io import BytesIO
from contextlib import redirect_stdout
from datetime import date
from io import StringIO
import json
from pathlib import Path
import tempfile
import urllib.error

from sonda_significado_publico import (
    FalhaDaSonda, avaliar_publicacao, chamar_rpc, main, sondar,
    sondar_painel,
)


class Resposta:
    def __init__(self, corpo):
        self.corpo = json.dumps(corpo).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return self.corpo


def abrir_verde(chamadas):
    respostas = {
        "similares_da_peca_amplo_v2": {
            "resumo": {
                "n_similares": 0, "n_marcas": 0,
                "atributos_pedidos": 2, "minimo_em_comum": 0,
                "n_com_todos": 0, "com_preco": 0, "exibidos": 0,
                "painel_observado_em": "2026-09-02",
                "painel_dias_desde_a_observacao": 16,
            },
            "pecas": [],
        },
        "resumo_de_eventos": {
            "tipo": "reposicao", "de": "2026-08-27", "ate": "2026-09-02",
            "dias": 7, "dias_desde_o_fim": 16, "unidade": "pecas",
            "denominador_em": "2026-09-02", "total_pecas": 0,
            "total_eventos": 0, "marcas": []},
        "buscar_referencia_editorial": {
            "expressao": "napoleon", "buscavel": True, "total": 0,
            "materias": []},
    }

    def abrir(pedido, timeout):
        nome = pedido.full_url.rsplit("/", 1)[-1]
        chamadas.append((nome, json.loads(pedido.data),
                         pedido.headers.get("Apikey"), timeout))
        return Resposta(respostas[nome])
    return abrir


def testar_verde():
    chamadas = []
    resultado = sondar("https://projeto.supabase.co", "publica",
                       abrir_verde(chamadas))
    assert resultado["amostras"] == {
        "similares_da_peca_amplo_v2": 0,
        "resumo_de_eventos": 0,
        "buscar_referencia_editorial": 0,
    }
    assert [c[0] for c in chamadas] == [
        "similares_da_peca_amplo_v2", "resumo_de_eventos",
        "buscar_referencia_editorial"]
    assert all(c[2] == "publica" and c[3] == 20 for c in chamadas)
    assert resultado["observacao"]["painel_observado_em"] == "2026-09-02"


def testar_publicacao_nao_depende_da_busca_editorial():
    chamadas = []
    resultado = sondar_painel(
        "https://projeto.supabase.co", "publica", abrir_verde(chamadas))
    assert [c[0] for c in chamadas] == [
        "similares_da_peca_amplo_v2", "resumo_de_eventos"]
    assert resultado["amostras"] == {
        "similares_da_peca_amplo_v2": 0,
        "resumo_de_eventos": 0,
    }


def testar_contrato_incompleto():
    def abrir(_pedido, timeout):
        assert timeout == 20
        return Resposta({"pecas": []})
    try:
        sondar("https://projeto.supabase.co", "publica", abrir)
        raise AssertionError("contrato incompleto deveria falhar")
    except FalhaDaSonda as erro:
        assert "resumo" in str(erro)


def testar_funcao_ausente():
    def abrir(pedido, timeout):
        corpo = BytesIO(json.dumps({"code": "PGRST202"}).encode("utf-8"))
        raise urllib.error.HTTPError(
            pedido.full_url, 404, "Not Found", {}, corpo)
    try:
        chamar_rpc("https://projeto.supabase.co", "publica",
                   "resumo_de_eventos", {}, abrir)
        raise AssertionError("PGRST202 deveria falhar")
    except FalhaDaSonda as erro:
        assert "PGRST202" in str(erro)
        assert "cache de schema" in str(erro)


HOJE = date(2026, 9, 19)


def observacao(painel="2026-09-19", eventos="2026-09-19"):
    def idade(valor):
        return (HOJE - date.fromisoformat(valor)).days if valor else None
    return {
        "painel_observado_em": painel,
        "painel_dias_desde_a_observacao": idade(painel),
        "eventos_ate": eventos,
        "eventos_dias_desde_o_fim": idade(eventos),
    }


def testar_publicacao():
    casos = [
        (observacao(), "2026-09-19", "atualizado", "data_publicada_confirmada"),
        # Pode terminar depois da virada do dia ou ser reexecução idempotente.
        (observacao(), "2026-09-18", "atualizado", "data_publicada_confirmada"),
        (observacao("2026-09-18", "2026-09-18"), "2026-09-18",
         "atualizado", "data_publicada_confirmada"),
        (observacao("2026-09-02", "2026-09-02"), "2026-09-19",
         "nao_atualizado", "observacao_anterior"),
        (observacao(None, None), "2026-09-19",
         "nao_atualizado", "observacao_ausente"),
        (observacao(None, "2026-09-19"), "2026-09-19",
         "nao_atualizado", "observacao_ausente"),
        (observacao("2026-09-19", "2026-09-18"), "2026-09-19",
         "inconclusivo", "leituras_divergentes"),
    ]
    for o, esperada, estado, motivo in casos:
        assert avaliar_publicacao(o, esperada, HOJE) == {
            "estado": estado, "motivo": motivo}


def testar_datas_invalidas():
    invalidos = [None, "", "2026-02-30", "19/09/2026", "20260919",
                 "2026-09-20"]
    for esperada in invalidos:
        try:
            avaliar_publicacao(observacao(), esperada, HOJE)
        except FalhaDaSonda:
            pass
        else:
            raise AssertionError("data esperada inválida aceita: {}".format(esperada))
    for campo, valor in (
            ("painel_observado_em", "2026-09-20"),
            ("eventos_ate", "ontem"),
            ("painel_dias_desde_a_observacao", True),
            ("eventos_dias_desde_o_fim", -1),
            ("eventos_dias_desde_o_fim", "0"),
            ("eventos_ate", None)):
        o = observacao()
        o[campo] = valor
        try:
            avaliar_publicacao(o, "2026-09-19", HOJE)
        except FalhaDaSonda:
            pass
        else:
            raise AssertionError("metadado inválido aceito: {}".format(campo))


def testar_cli_e_relatorio():
    ambiente = {"SUPABASE_URL": "https://projeto.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "publica-nao-imprimir"}
    with tempfile.TemporaryDirectory() as pasta:
        destino = Path(pasta) / "publicacao.json"
        for argumentos, codigo, estado in (
                ([], 0, "contrato_valido"),
                (["--exigir-publicacao", "--data-operacional", "2026-09-19"],
                 2, "nao_atualizado"),
                (["--exigir-publicacao", "--data-operacional", "2026-09-02"],
                 0, "atualizado"),
                (["--exigir-publicacao"], 1, "erro"),
                (["--data-operacional", "2026-09-19"], 1, "erro")):
            chamadas, saida = [], StringIO()
            with redirect_stdout(saida):
                retorno = main(argumentos + ["--relatorio", str(destino)],
                               ambiente, abrir_verde(chamadas))
            assert retorno == codigo
            relatorio = json.loads(destino.read_text(encoding="utf-8"))
            assert relatorio["estado"] == estado
            esperadas = 0 if estado == "erro" else (2 if argumentos else 3)
            assert len(chamadas) == esperadas
            assert "publica-nao-imprimir" not in destino.read_text(encoding="utf-8")
            assert "pronto para o app" not in saida.getvalue()
            if estado == "contrato_valido":
                assert "NÃO avaliada" in saida.getvalue()

        # Indisponibilidade não vira dado velho nem mercado vazio.
        def indisponivel(*_args, **_kwargs):
            raise urllib.error.URLError("sem rede")
        with redirect_stdout(StringIO()):
            retorno = main(["--exigir-publicacao", "--data-operacional",
                            "2026-09-19", "--relatorio", str(destino)],
                           ambiente, indisponivel)
        assert retorno == 1
        assert json.loads(destino.read_text())["estado"] == "erro"


if __name__ == "__main__":
    testar_verde()
    testar_publicacao_nao_depende_da_busca_editorial()
    testar_contrato_incompleto()
    testar_funcao_ausente()
    testar_publicacao()
    testar_datas_invalidas()
    testar_cli_e_relatorio()
    print("ok: sonda separa contrato, publicação do dia e falha de leitura sem rede")
