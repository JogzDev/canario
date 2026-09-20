#!/usr/bin/env python3
"""Confere contrato público e, opcionalmente, publicação do dia operacional.

Usa a publishable key -- a mesma credencial pública embutida no binário.
No modo de contrato, confere as três RPCs públicas. No modo de publicação,
confere somente as duas RPCs que carregam a data do painel: a busca editorial
não publica nem comprova esse marco e não pode mascará-lo com um timeout.
A sonda deve rodar depois das migrations e do refresh do schema do PostgREST.
Contrato válido NÃO prova atualização. O pipeline diário usa
--exigir-publicacao e a data fixada no início da coleta.
Saídas: 0 = verificação solicitada passou; 1 = leitura/contrato inválido;
2 = contrato válido, mas publicação esperada não foi comprovada.
"""

import argparse
from datetime import date, datetime, timezone
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
    ambiente = os.environ if ambiente is None else ambiente
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


def sondar_painel(base, chave, abrir=urllib.request.urlopen):
    """Confere os contratos e os marcos que comprovam a publicação diária."""
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

    return {
        "amostras": {
            "similares_da_peca_amplo_v2": len(similares["pecas"]),
            "resumo_de_eventos": len(resumo["marcas"]),
        },
        "observacao": {
            "painel_observado_em": similares["resumo"]["painel_observado_em"],
            "painel_dias_desde_a_observacao": similares["resumo"][
                "painel_dias_desde_a_observacao"],
            "eventos_ate": resumo["ate"],
            "eventos_dias_desde_o_fim": resumo["dias_desde_o_fim"],
        },
    }


def sondar_editorial(base, chave, abrir=urllib.request.urlopen):
    """Confere separadamente o contrato público da busca editorial."""
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

    return len(editorial["materias"])


def sondar(base, chave, abrir=urllib.request.urlopen):
    """Confere o contrato público completo das três RPCs A57/A58."""
    resultado = sondar_painel(base, chave, abrir)
    resultado["amostras"]["buscar_referencia_editorial"] = sondar_editorial(
        base, chave, abrir)
    return resultado


def data_iso(valor, nome):
    try:
        convertida = date.fromisoformat(valor)
    except (ValueError, TypeError):
        raise FalhaDaSonda("{}: use uma data YYYY-MM-DD válida".format(nome))
    if convertida.isoformat() != valor:
        raise FalhaDaSonda("{}: use o formato YYYY-MM-DD".format(nome))
    return convertida


def avaliar_publicacao(observacao, data_operacional, hoje=None):
    """O marco do SQL, não o contador de upserts do motor, prova publicação.

    Uma reexecução pode gravar zero marcos e encontrar o dia já publicado.
    A data esperada vem da coleta, não do relógio ao terminar após meia-noite.
    Um marco posterior também satisfaz uma reexecução de um dia anterior.
    """
    hoje = hoje or datetime.now(timezone.utc).date()
    esperada = data_iso(data_operacional, "data_operacional")
    if esperada > hoje:
        raise FalhaDaSonda("data_operacional não pode estar no futuro")
    datas = []
    for nome, idade in (
            ("painel_observado_em", "painel_dias_desde_a_observacao"),
            ("eventos_ate", "eventos_dias_desde_o_fim")):
        valor, dias = observacao[nome], observacao[idade]
        if valor is None:
            if dias is not None:
                raise FalhaDaSonda("{}: idade sem data conhecida".format(nome))
            datas.append(None)
            continue
        convertido = data_iso(valor, nome)
        if convertido > hoje or type(dias) is not int or dias < 0:
            raise FalhaDaSonda("{}: data futura ou idade inválida".format(nome))
        datas.append(convertido)
    if None in datas:
        return {"estado": "nao_atualizado", "motivo": "observacao_ausente"}
    if datas[0] != datas[1]:
        # Duas leituras não são uma transação. Pode haver publicação entre
        # elas; reportar inconclusivo, nunca verde nem recolher tudo de novo.
        return {"estado": "inconclusivo", "motivo": "leituras_divergentes"}
    if datas[0] < esperada:
        return {"estado": "nao_atualizado", "motivo": "observacao_anterior"}
    return {"estado": "atualizado", "motivo": "data_publicada_confirmada"}


def main(argv=None, ambiente=None, abrir=urllib.request.urlopen):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exigir-publicacao", action="store_true")
    parser.add_argument("--data-operacional")
    parser.add_argument("--relatorio", help="Gravar diagnóstico JSON local")
    args = parser.parse_args(argv)
    resultado = {
        "modo": "publicacao" if args.exigir_publicacao else "contrato",
        "data_operacional": args.data_operacional,
        "verificado_em": datetime.now(timezone.utc).isoformat(),
    }
    try:
        if args.exigir_publicacao:
            # Falha antes da rede se a propagação da data sumir do workflow.
            esperada = data_iso(args.data_operacional, "data_operacional")
            if esperada > datetime.now(timezone.utc).date():
                raise FalhaDaSonda("data_operacional não pode estar no futuro")
        elif args.data_operacional:
            raise FalhaDaSonda("data_operacional exige --exigir-publicacao")
        base, chave = configuracao(ambiente)
        if args.exigir_publicacao:
            resultado.update(sondar_painel(base, chave, abrir))
            resultado["contrato_painel"] = "valido"
            resultado.update(avaliar_publicacao(
                resultado["observacao"], args.data_operacional))
        else:
            resultado.update(sondar(base, chave, abrir))
            resultado["contrato"] = "valido"
            resultado.update(estado="contrato_valido",
                             motivo="atualizacao_nao_avaliada")
        codigo = 2 if resultado["estado"] in ("nao_atualizado", "inconclusivo") else 0
    except FalhaDaSonda as erro:
        resultado.update(estado="erro", motivo=str(erro))
        codigo = 1

    if args.relatorio:
        Path(args.relatorio).write_text(
            json.dumps(resultado, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")
    for nome, quantidade in resultado.get("amostras", {}).items():
        print("OK {} · {} item(ns) na amostra".format(nome, quantidade))
    if "observacao" in resultado:
        o = resultado["observacao"]
        print("Painel: {} ({} dias). Eventos até: {} ({} dias).".format(
            o["painel_observado_em"], o["painel_dias_desde_a_observacao"],
            o["eventos_ate"], o["eventos_dias_desde_o_fim"]))
    if resultado["estado"] == "atualizado":
        print("ATUALIZADO: API confirma publicação para {} ou posterior.".format(
            args.data_operacional))
    elif resultado["estado"] == "contrato_valido":
        print("Contrato público A57/A58 válido. Atualização do painel NÃO avaliada.")
    else:
        print("{}: {}. Nenhuma coleta foi repetida.".format(
            resultado["estado"].upper(), resultado["motivo"]))
    return codigo


if __name__ == "__main__":
    raise SystemExit(main())
