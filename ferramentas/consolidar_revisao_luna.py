#!/usr/bin/env python3
"""Compara revisores cegos e mede uma rodada do Luna contra ouro humano.

Este script nunca chama a OpenAI. O portao de 300 so e escrito a partir de um
gabarito adjudicado e do JSONL completo produzido pelo avaliador.
"""

import argparse
import json
import math
from pathlib import Path


CAMPOS_HUMANOS = (
    "target_clarity",
    "category",
    "structure",
    "primary_color",
    "secondary_colors",
)
CAMPOS_DO_PORTAO = (
    "target_clarity",
    "category",
    "structure",
    "primary_color",
)


def carregar_revisao(caminho):
    dados = json.loads(caminho.read_text(encoding="utf-8"))
    respostas = dados.get("answers")
    if not isinstance(respostas, list) or not respostas:
        raise ValueError("Revisao sem answers: {}".format(caminho))
    por_id = {}
    for resposta in respostas:
        sample_id = resposta.get("sample_id")
        if not sample_id or sample_id in por_id:
            raise ValueError("sample_id ausente ou repetido em {}".format(caminho))
        ausentes = [campo for campo in CAMPOS_HUMANOS if campo not in resposta]
        if ausentes:
            raise ValueError("Campos ausentes em {}: {}".format(
                sample_id, ", ".join(ausentes)))
        por_id[sample_id] = resposta
    return {
        "reviewer": dados.get("reviewer") or caminho.stem,
        "rubric_version": dados.get("rubric_version"),
        "answers": por_id,
    }


def _comparavel(campo, valor):
    if campo == "secondary_colors":
        return tuple(sorted(valor))
    return valor


def comparar_revisoes(revisoes):
    if len(revisoes) < 2:
        raise ValueError("A comparacao cega exige pelo menos dois revisores.")
    ids = set(revisoes[0]["answers"])
    rubrica = revisoes[0]["rubric_version"]
    for revisao in revisoes[1:]:
        if set(revisao["answers"]) != ids:
            raise ValueError("Revisores nao cobrem as mesmas amostras.")
        if revisao["rubric_version"] != rubrica:
            raise ValueError("Revisores usaram versoes diferentes da rubrica.")

    acordos = {campo: 0 for campo in CAMPOS_HUMANOS}
    divergencias = []
    for sample_id in sorted(ids):
        campos_divergentes = {}
        for campo in CAMPOS_HUMANOS:
            valores = [
                _comparavel(campo, revisao["answers"][sample_id][campo])
                for revisao in revisoes
            ]
            if len(set(valores)) == 1:
                acordos[campo] += 1
            else:
                campos_divergentes[campo] = {
                    revisao["reviewer"]: revisao["answers"][sample_id][campo]
                    for revisao in revisoes
                }
        if campos_divergentes:
            divergencias.append({
                "sample_id": sample_id,
                "fields": campos_divergentes,
            })
    return {
        "rubric_version": rubrica,
        "reviewers": [revisao["reviewer"] for revisao in revisoes],
        "sample_size": len(ids),
        "agreements": acordos,
        "disagreements": divergencias,
    }


def ids_para_adjudicar(comparacao):
    """Só o que pode mudar categoria/cor do portão; secundárias ficam fora."""
    return {
        item["sample_id"]
        for item in comparacao["disagreements"]
        if any(campo in CAMPOS_DO_PORTAO for campo in item["fields"])
    }


def adjudicar_revisoes(revisoes, adjudicacao):
    """Fecha o ouro: consenso dos dois revisores + voto cego do adjudicador."""
    comparacao = comparar_revisoes(revisoes)
    ids_divergentes = ids_para_adjudicar(comparacao)
    ids_adjudicados = set(adjudicacao["answers"])
    if ids_adjudicados != ids_divergentes:
        faltam = sorted(ids_divergentes - ids_adjudicados)
        sobram = sorted(ids_adjudicados - ids_divergentes)
        raise ValueError(
            "Adjudicacao deve cobrir apenas divergencias: faltam={}, sobram={}".format(
                faltam, sobram))
    if adjudicacao["rubric_version"] != comparacao["rubric_version"]:
        raise ValueError("Adjudicacao usou outra versao da rubrica.")

    respostas = []
    nao_adjudicados = []
    for sample_id in sorted(revisoes[0]["answers"]):
        final = dict(revisoes[0]["answers"][sample_id])
        final["sample_id"] = sample_id
        for campo in CAMPOS_HUMANOS:
            valores = [
                _comparavel(campo, revisao["answers"][sample_id][campo])
                for revisao in revisoes
            ]
            if len(set(valores)) == 1:
                final[campo] = revisoes[0]["answers"][sample_id][campo]
            elif campo in CAMPOS_DO_PORTAO or sample_id in ids_adjudicados:
                final[campo] = adjudicacao["answers"][sample_id][campo]
            else:
                # Cor secundaria nao participa do portao A17. Nao obrigamos o
                # adjudicador a rever uma imagem apenas por ela, e nao fingimos
                # consenso: o ouro registra explicitamente o campo descartado.
                final[campo] = []
                nao_adjudicados.append({
                    "sample_id": sample_id,
                    "field": campo,
                    "reason": "fora do portao A17",
                })
        final["notes"] = (adjudicacao["answers"].get(sample_id, {}).get("notes")
                          or final.get("notes") or "")
        respostas.append(final)
    return {
        "reviewer": "ADJUDICADO: {}".format(adjudicacao["reviewer"]),
        "rubric_version": comparacao["rubric_version"],
        "source_reviewers": comparacao["reviewers"],
        "unresolved_non_gate_fields": nao_adjudicados,
        "answers": respostas,
    }


def carregar_resultados(caminho):
    resultados = {}
    with caminho.open(encoding="utf-8") as arquivo:
        for numero, linha in enumerate(arquivo, 1):
            if not linha.strip():
                continue
            resultado = json.loads(linha)
            sample_id = resultado.get("sample_id")
            if not sample_id or sample_id in resultados:
                raise ValueError(
                    "sample_id ausente ou repetido na linha {}".format(numero))
            resultados[sample_id] = resultado
    if not resultados:
        raise ValueError("JSONL de resultados vazio.")
    return resultados


def intervalo_wilson(acertos, total, z=1.959963984540054):
    if total <= 0:
        return (0.0, 0.0)
    proporcao = acertos / total
    denominador = 1 + z * z / total
    centro = (proporcao + z * z / (2 * total)) / denominador
    margem = z * math.sqrt(
        proporcao * (1 - proporcao) / total + z * z / (4 * total * total)
    ) / denominador
    return (max(0.0, centro - margem), min(1.0, centro + margem))


def avaliar_contra_gabarito(gabarito, resultados):
    respostas = gabarito["answers"]
    if set(respostas) != set(resultados):
        faltam = sorted(set(respostas) - set(resultados))
        sobram = sorted(set(resultados) - set(respostas))
        raise ValueError("Gabarito e resultados divergem: faltam={}, sobram={}".format(
            faltam, sobram))
    versoes = {resultado.get("prompt_version") for resultado in resultados.values()}
    if len(versoes) != 1 or None in versoes:
        raise ValueError("Resultados nao registram uma unica prompt_version.")

    contagens = {
        "category": 0,
        "primary_color": 0,
        "target_clarity": 0,
    }
    linhas = []
    for sample_id in sorted(respostas):
        ouro = respostas[sample_id]
        analise = resultados[sample_id].get("analysis") or {}
        cores = analise.get("colors") or []
        previsto = {
            "category": analise.get("category"),
            "primary_color": cores[0] if cores else "not_visible",
            "target_clarity": analise.get("target_clarity"),
        }
        correto = {
            campo: previsto[campo] == ouro[campo]
            for campo in contagens
        }
        for campo, acertou in correto.items():
            contagens[campo] += int(acertou)
        linhas.append({
            "sample_id": sample_id,
            "gold": {campo: ouro[campo] for campo in contagens},
            "predicted": previsto,
            "correct": correto,
        })

    total = len(respostas)
    metricas = {}
    for campo, acertos in contagens.items():
        metricas[campo] = {
            "correct": acertos,
            "total": total,
            "accuracy": acertos / total,
            "wilson_95": list(intervalo_wilson(acertos, total)),
        }
    passou = (
        metricas["category"]["accuracy"] >= 0.80
        and metricas["primary_color"]["accuracy"] >= 0.80
    )
    return {
        "prompt_version": next(iter(versoes)),
        "rubric_version": gabarito["rubric_version"],
        "gold_reviewer": gabarito["reviewer"],
        "sample_size": total,
        "metrics": metricas,
        "passed": passou,
        "rows": linhas,
    }


def relatorio_markdown(comparacao=None, avaliacao=None):
    linhas = ["# Revisao Luna — consolidacao", ""]
    if comparacao:
        total = comparacao["sample_size"]
        linhas += [
            "## Independencia entre revisores",
            "",
            "Revisores: {}. Rubrica: `{}`.".format(
                ", ".join(comparacao["reviewers"]),
                comparacao["rubric_version"]),
            "",
            "| campo | acordo |",
            "|---|---:|",
        ]
        for campo, acertos in comparacao["agreements"].items():
            linhas.append("| {} | {}/{} ({:.1%}) |".format(
                campo, acertos, total, acertos / total))
        linhas += ["", "### Itens para adjudicar no portão", ""]
        ids_portao = ids_para_adjudicar(comparacao)
        if not ids_portao:
            linhas.append("Nenhuma divergencia.")
        for item in comparacao["disagreements"]:
            campos = [campo for campo in item["fields"]
                      if campo in CAMPOS_DO_PORTAO]
            if campos:
                linhas.append("- **{}**: {}".format(
                    item["sample_id"], ", ".join(campos)))
        somente_secundarias = [
            item["sample_id"] for item in comparacao["disagreements"]
            if item["sample_id"] not in ids_portao
        ]
        if somente_secundarias:
            linhas += [
                "",
                "Divergencias apenas em cores secundarias, fora do portao A17: {}.".format(
                    ", ".join(somente_secundarias)),
            ]
        linhas.append("")

    if avaliacao:
        linhas += [
            "## Prompt contra gabarito adjudicado",
            "",
            "Prompt: `{}`. Amostra: **{}**. Portao: **{}**.".format(
                avaliacao["prompt_version"], avaliacao["sample_size"],
                "ABERTO" if avaliacao["passed"] else "FECHADO"),
            "",
            "| medida | acertos | resultado | IC 95% Wilson |",
            "|---|---:|---:|---:|",
        ]
        for campo, metrica in avaliacao["metrics"].items():
            inferior, superior = metrica["wilson_95"]
            linhas.append("| {} | {}/{} | {:.1%} | {:.1%}–{:.1%} |".format(
                campo, metrica["correct"], metrica["total"],
                metrica["accuracy"], inferior, superior))
        divergentes = [
            linha for linha in avaliacao["rows"]
            if not all(linha["correct"].values())
        ]
        linhas += ["", "### Divergencias", ""]
        if not divergentes:
            linhas.append("Nenhuma divergencia.")
        for linha in divergentes:
            campos = [campo for campo, certo in linha["correct"].items() if not certo]
            linhas.append("- **{}**: {}".format(
                linha["sample_id"], ", ".join(campos)))
        linhas.append("")
    return "\n".join(linhas)


def argumentos():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revisoes", nargs="*", type=Path, default=[])
    parser.add_argument("--gabarito", type=Path)
    parser.add_argument("--resultados", type=Path)
    parser.add_argument("--adjudicacao", type=Path)
    parser.add_argument("--gabarito-saida", type=Path)
    parser.add_argument("--relatorio", type=Path, required=True)
    parser.add_argument("--portao", type=Path)
    return parser.parse_args()


def main():
    args = argumentos()
    comparacao = None
    avaliacao = None
    if args.revisoes:
        revisoes = [carregar_revisao(caminho) for caminho in args.revisoes]
        comparacao = comparar_revisoes(revisoes)
        if bool(args.adjudicacao) != bool(args.gabarito_saida):
            raise SystemExit(
                "--adjudicacao e --gabarito-saida devem ser usados juntos")
        if args.adjudicacao:
            gabarito = adjudicar_revisoes(
                revisoes, carregar_revisao(args.adjudicacao))
            args.gabarito_saida.write_text(
                json.dumps(gabarito, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8")
    elif args.adjudicacao or args.gabarito_saida:
        raise SystemExit("Adjudicacao exige --revisoes")
    if bool(args.gabarito) != bool(args.resultados):
        raise SystemExit("--gabarito e --resultados devem ser usados juntos")
    if args.gabarito:
        avaliacao = avaliar_contra_gabarito(
            carregar_revisao(args.gabarito),
            carregar_resultados(args.resultados),
        )
    if not comparacao and not avaliacao:
        raise SystemExit("Informe revisoes ou gabarito+resultados")
    args.relatorio.write_text(
        relatorio_markdown(comparacao, avaliacao) + "\n", encoding="utf-8")
    if args.portao:
        if not avaliacao:
            raise SystemExit("--portao exige gabarito+resultados")
        portao = {
            "prompt_version": avaliacao["prompt_version"],
            "rubric_version": avaliacao["rubric_version"],
            "sample_size": avaliacao["sample_size"],
            "category_accuracy": avaliacao["metrics"]["category"]["accuracy"],
            "primary_color_accuracy": avaliacao["metrics"]["primary_color"]["accuracy"],
            "passed": avaliacao["passed"],
        }
        args.portao.write_text(
            json.dumps(portao, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print("Consolidacao sem chamadas a OpenAI concluida.")


if __name__ == "__main__":
    main()
