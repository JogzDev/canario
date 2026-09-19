#!/usr/bin/env python3
"""Teste sem rede da sonda pública A57/A58."""

from io import BytesIO
import json
import urllib.error

from sonda_significado_publico import FalhaDaSonda, chamar_rpc, sondar


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
    assert resultado == {
        "similares_da_peca_amplo_v2": 0,
        "resumo_de_eventos": 0,
        "buscar_referencia_editorial": 0,
    }
    assert [c[0] for c in chamadas] == [
        "similares_da_peca_amplo_v2", "resumo_de_eventos",
        "buscar_referencia_editorial"]
    assert all(c[2] == "publica" and c[3] == 20 for c in chamadas)


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


if __name__ == "__main__":
    testar_verde()
    testar_contrato_incompleto()
    testar_funcao_ausente()
    print("ok: sonda pública A57/A58 classifica rota e contrato sem rede")
