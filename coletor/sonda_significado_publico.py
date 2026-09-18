#!/usr/bin/env python3
"""Prova que o backend A57/A58 publicado atende o contrato público do app.

Usa a publishable key -- a mesma credencial pública embutida no binário -- e
faz apenas três leituras pequenas. A sonda deve rodar depois das migrations e
do refresh do schema do PostgREST, antes de liberar o app consumidor.
"""

import json
import os
from pathlib import Path
import urllib.error
import urllib.request


RAIZ = Path(__file__).resolve().parents[1]
AGENTE = "DataDrobeSignificadoProbe/1.0"


class FalhaDaSonda(RuntimeError):
    """Falha de rota, autorização ou contrato público."""


def configuracao(ambiente=None, caminho=None):
    ambiente = ambiente or os.environ
    url = ambiente.get("SUPABASE_URL", "").strip()
    chave = ambiente.get("SUPABASE_PUBLISHABLE_KEY", "").strip()

    if not url or not chave:
        valores = {}
        caminho = Path(caminho or RAIZ / "app" / "Config.xcconfig")
        if caminho.is_file():
            for linha in caminho.read_text(encoding="utf-8").splitlines():
                if "=" not in linha or linha.lstrip().startswith("//"):
                    continue
                nome, valor = linha.split("=", 1)
                valores[nome.strip()] = valor.strip()
        url = url or valores.get("SUPABASE_URL", "")
        chave = chave or valores.get("SUPABASE_PUBLISHABLE_KEY", "")

    if url and not url.startswith("http"):
        url = "https://" + url
    if not url or not chave:
        raise FalhaDaSonda(
            "SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY são obrigatórios")
    return url.rstrip("/"), chave


def chamar_rpc(base, chave, nome, argumentos, abrir=urllib.request.urlopen):
    pedido = urllib.request.Request(
        base + "/rest/v1/rpc/" + nome,
        data=json.dumps(argumentos).encode("utf-8"),
        headers={
            "apikey": chave,
            "Authorization": "Bearer " + chave,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": AGENTE,
        },
        method="POST",
    )
    try:
        with abrir(pedido, timeout=20) as resposta:
            return json.loads(resposta.read().decode("utf-8"))
    except urllib.error.HTTPError as erro:
        corpo = erro.read().decode("utf-8", "replace")
        try:
            codigo = json.loads(corpo).get("code")
        except (json.JSONDecodeError, AttributeError):
            codigo = None
        detalhe = "{} / {}".format(erro.code, codigo or "sem código PostgREST")
        if codigo == "PGRST202":
            detalhe += " (função ausente do cache de schema)"
        raise FalhaDaSonda("{}: HTTP {}".format(nome, detalhe)) from erro
    except (urllib.error.URLError, TimeoutError) as erro:
        raise FalhaDaSonda("{}: falha de rede: {}".format(nome, erro)) from erro
    except (json.JSONDecodeError, UnicodeDecodeError) as erro:
        raise FalhaDaSonda("{}: resposta não é JSON válido".format(nome)) from erro


def exigir_objeto(nome, resposta, chaves, listas=()):
    if not isinstance(resposta, dict):
        raise FalhaDaSonda("{}: resposta não é objeto JSON".format(nome))
    ausentes = [chave for chave in chaves if chave not in resposta]
    if ausentes:
        raise FalhaDaSonda(
            "{}: campos ausentes: {}".format(nome, ", ".join(ausentes)))
    invalidas = [chave for chave in listas
                 if not isinstance(resposta.get(chave), list)]
    if invalidas:
        raise FalhaDaSonda(
            "{}: campos não são listas: {}".format(nome, ", ".join(invalidas)))


def sondar(base, chave, abrir=urllib.request.urlopen):
    similares = chamar_rpc(
        base, chave, "similares_da_peca_amplo_v2",
        {"termos": ["vestido", "preto"], "limite": 1,
         "preco_alvo": None}, abrir)
    exigir_objeto("similares_da_peca_amplo_v2", similares,
                  ("resumo", "pecas"), ("pecas",))
    exigir_objeto(
        "similares_da_peca_amplo_v2.resumo", similares["resumo"],
        ("n_similares", "n_marcas", "atributos_pedidos",
         "minimo_em_comum", "n_com_todos", "com_preco", "exibidos",
         "painel_observado_em", "painel_dias_desde_a_observacao"))
    if similares["pecas"]:
        exigir_objeto(
            "similares_da_peca_amplo_v2.pecas[0]", similares["pecas"][0],
            ("id", "marca", "em_comum", "visto_em"))

    resumo = chamar_rpc(
        base, chave, "resumo_de_eventos",
        {"tipo_evento": "reposicao", "dias": 7,
         "exemplos_por_marca": 1, "ate": None}, abrir)
    exigir_objeto("resumo_de_eventos", resumo,
                  ("tipo", "de", "ate", "dias", "dias_desde_o_fim",
                   "unidade", "denominador_em", "total_pecas",
                   "total_eventos", "marcas"),
                  ("marcas",))
    if resumo["marcas"]:
        exigir_objeto(
            "resumo_de_eventos.marcas[0]", resumo["marcas"][0],
            ("marca", "pecas", "eventos", "exemplos"), ("exemplos",))

    editorial = chamar_rpc(
        base, chave, "buscar_referencia_editorial",
        {"expressao": "napoleon", "limite": 1}, abrir)
    exigir_objeto("buscar_referencia_editorial", editorial,
                  ("expressao", "buscavel", "total", "materias"),
                  ("materias",))
    if editorial["materias"]:
        exigir_objeto(
            "buscar_referencia_editorial.materias[0]", editorial["materias"][0],
            ("titulo", "veiculo", "data", "url"))

    return {
        "similares_da_peca_amplo_v2": len(similares["pecas"]),
        "resumo_de_eventos": len(resumo["marcas"]),
        "buscar_referencia_editorial": len(editorial["materias"]),
    }


def main():
    base, chave = configuracao()
    resultado = sondar(base, chave)
    for nome, quantidade in resultado.items():
        print("OK {} · {} item(ns) na amostra".format(nome, quantidade))
    print("Backend A57/A58 público pronto para o app.")


if __name__ == "__main__":
    try:
        main()
    except FalhaDaSonda as erro:
        raise SystemExit("FALHOU: {}".format(erro))
