#!/usr/bin/env python3
"""Compara revisores cegos e mede uma rodada do Luna contra ouro humano.

Este script nunca chama a OpenAI. O portao de 300 so e escrito a partir de um
gabarito adjudicado e do JSONL completo produzido pelo avaliador.
"""

import argparse
import csv
import datetime as dt
import json
import math
import re
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

# Imagem que voltou sem analise: erro de contrato, timeout, falha do
# segmentador. Nao e um id da taxonomia de proposito, para nunca casar com o
# gabarito. Ver `_previsao` para o motivo de nao reaproveitar `not_visible`.
SEM_RESPOSTA = "sem_resposta"
CONTRATO_REVISAO = "canario_luna_review_submission_v1"
CONTRATO_GABARITO = "canario_luna_gold_v1"
RUBRICAS_SUPORTADAS = {"categoria-cor-v2", "categoria-cor-v3"}
CLAREZAS = {
    "clear", "partially_occluded", "multiple_garments_target_clear",
    "ambiguous_target",
}
CATEGORIA_POR_ESTRUTURA = {
    "one_piece_no_separate_legs": "vestido",
    "one_piece_with_separate_legs": "macacao",
    "lower_continuous_panel": "saia",
    "lower_two_legs_short": "short",
    "lower_two_legs_long": "calca",
    "upper_shirt_construction": "camisa",
    "upper_outer_layer": "casaco_jaqueta",
    "upper_other": "blusa_top",
    "target_not_determinable": "not_visible",
}
CORES = {
    "preto", "branco_cru", "cinza", "azul", "verde", "lilas_roxo",
    "vermelho_rosa", "amarelo_laranja", "terrosos", "outras_cores",
    "not_visible",
}
CAMPOS_RESPOSTA = {
    "sample_id", "imagem", "image_sha256", "target_clarity", "category",
    "structure", "primary_color", "secondary_colors", "notes", "reviewed_at",
}
CAMPOS_RESPOSTA_OPCIONAIS = {
    "adjudication_basis", "original_selection", "acceptable_primary_colors",
}
CAMPOS_CSV = (
    "contract", "batch_id", "rubric_version", "reviewer", "exported_at",
    "sample_id", "imagem", "image_sha256", "target_clarity", "category",
    "structure", "primary_color", "secondary_colors", "notes", "reviewed_at",
)


def _cores_secundarias(valor):
    if isinstance(valor, list):
        return valor
    if not valor:
        return []
    return [cor.strip() for cor in re.split(r"[;|,]", valor) if cor.strip()]


def _texto_controlado(valor, campo, minimo, maximo, permitir_quebras=False):
    if not isinstance(valor, str) or not minimo <= len(valor.strip()) <= maximo:
        raise ValueError("{} fora do contrato".format(campo))
    permitidos = "\n\r\t" if permitir_quebras else ""
    if any((ord(c) < 32 and c not in permitidos) or ord(c) == 127 for c in valor):
        raise ValueError("{} contem caractere de controle".format(campo))
    return valor.strip()


def _instante(valor, campo):
    texto = _texto_controlado(valor, campo, 1, 64)
    try:
        instante = dt.datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError as erro:
        raise ValueError("{} fora de ISO-8601".format(campo)) from erro
    if instante.tzinfo is None:
        raise ValueError("{} precisa registrar fuso".format(campo))
    if instante.astimezone(dt.timezone.utc) > (
            dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=10)):
        raise ValueError("{} esta no futuro".format(campo))
    return texto


def _validar_reviewer(valor):
    return _texto_controlado(valor, "reviewer", 1, 160)


def _validar_rubrica(valor):
    if valor not in RUBRICAS_SUPORTADAS:
        raise ValueError("rubric_version desconhecida: {}".format(valor))
    return valor


def _validar_resposta(resposta, estrita=True):
    if not isinstance(resposta, dict):
        raise ValueError("Resposta fora do contrato")
    if estrita and (not CAMPOS_RESPOSTA <= set(resposta)
                    or set(resposta) - CAMPOS_RESPOSTA
                    - CAMPOS_RESPOSTA_OPCIONAIS):
        raise ValueError("Campos da resposta fora do contrato")
    ausentes = [campo for campo in CAMPOS_RESPOSTA if campo not in resposta]
    if ausentes:
        raise ValueError("Campos ausentes: {}".format(", ".join(sorted(ausentes))))

    sample_id = resposta["sample_id"]
    if not isinstance(sample_id, str) or not re.fullmatch(r"S[0-9]{2,6}", sample_id):
        raise ValueError("sample_id fora do contrato")
    imagem = _texto_controlado(resposta["imagem"], "imagem", 1, 255)
    if (imagem in (".", "..") or Path(imagem).name != imagem or "\\" in imagem
            or not re.fullmatch(r"[^/\\\x00-\x1f]+[.](?:jpg|jpeg|png|webp|heic)",
                                imagem, re.IGNORECASE)):
        raise ValueError("imagem deve ser somente o nome do arquivo")
    if not isinstance(resposta["image_sha256"], str) or not re.fullmatch(
            r"[0-9a-f]{64}", resposta["image_sha256"]):
        raise ValueError("image_sha256 fora do contrato")
    if resposta["target_clarity"] not in CLAREZAS:
        raise ValueError("target_clarity fora do contrato em {}".format(sample_id))
    estrutura = resposta["structure"]
    if estrutura not in CATEGORIA_POR_ESTRUTURA:
        raise ValueError("structure fora do contrato em {}".format(sample_id))
    if resposta["category"] != CATEGORIA_POR_ESTRUTURA[estrutura]:
        raise ValueError("category contradiz structure em {}".format(sample_id))
    primaria = resposta["primary_color"]
    if primaria not in CORES:
        raise ValueError("primary_color fora do contrato em {}".format(sample_id))
    secundarias = resposta["secondary_colors"]
    if (not isinstance(secundarias, list) or len(secundarias) > 2
            or any(not isinstance(cor, str) for cor in secundarias)
            or len(set(secundarias)) != len(secundarias)
            or any(cor not in CORES - {"not_visible"} for cor in secundarias)
            or primaria in secundarias):
        raise ValueError("secondary_colors fora do contrato em {}".format(sample_id))
    ambiguo = resposta["target_clarity"] == "ambiguous_target"
    if ambiguo != (estrutura == "target_not_determinable"):
        raise ValueError("clareza e estrutura incoerentes em {}".format(sample_id))
    if ambiguo:
        if primaria != "not_visible" or secundarias:
            raise ValueError("alvo ambiguo deve abster cor em {}".format(sample_id))
    elif primaria == "not_visible":
        raise ValueError("alvo determinado exige cor em {}".format(sample_id))
    if not isinstance(resposta["notes"], str) or len(resposta["notes"]) > 2000:
        raise ValueError("notes fora do contrato em {}".format(sample_id))
    _texto_controlado(
        resposta["notes"], "notes", 0, 2000, permitir_quebras=True)
    _instante(resposta["reviewed_at"], "reviewed_at")
    if "adjudication_basis" in resposta:
        _texto_controlado(
            resposta["adjudication_basis"], "adjudication_basis", 0, 1000,
            permitir_quebras=True)
    if "original_selection" in resposta and not isinstance(
            resposta["original_selection"], dict):
        raise ValueError("original_selection fora do contrato")
    if "original_selection" in resposta:
        original = resposta["original_selection"]
        if (set(original) - set(CAMPOS_HUMANOS)
                or len(json.dumps(original, ensure_ascii=False)) > 4096):
            raise ValueError("original_selection fora do contrato")
        for campo, valor in original.items():
            if campo == "target_clarity" and valor not in CLAREZAS:
                raise ValueError("target_clarity original fora do contrato")
            if campo == "category" and valor not in set(
                    CATEGORIA_POR_ESTRUTURA.values()):
                raise ValueError("category original fora do contrato")
            if campo == "structure" and valor not in CATEGORIA_POR_ESTRUTURA:
                raise ValueError("structure original fora do contrato")
            if campo == "primary_color" and valor not in CORES:
                raise ValueError("primary_color original fora do contrato")
            if campo == "secondary_colors" and (
                    not isinstance(valor, list)
                    or len(valor) > 2
                    or any(not isinstance(cor, str) for cor in valor)
                    or len(set(valor)) != len(valor)
                    or any(cor not in CORES - {"not_visible"} for cor in valor)):
                raise ValueError("secondary_colors original fora do contrato")
    if "acceptable_primary_colors" in resposta:
        aceitaveis = resposta["acceptable_primary_colors"]
        if (not isinstance(aceitaveis, list) or not 1 <= len(aceitaveis) <= 2
                or any(not isinstance(cor, str) for cor in aceitaveis)
                or len(set(aceitaveis)) != len(aceitaveis)
                or any(cor not in CORES for cor in aceitaveis)
                or primaria not in aceitaveis):
            raise ValueError("acceptable_primary_colors fora do contrato")
    return resposta


def _dados_da_revisao(caminho, permitir_legado=False):
    """Aceita o JSON exportado pelo formulario e o CSV do revisor."""
    if caminho.suffix.lower() != ".csv":
        return json.loads(caminho.read_text(encoding="utf-8"))

    with caminho.open(encoding="utf-8-sig", newline="") as arquivo:
        leitor = csv.DictReader(arquivo)
        campos = tuple(leitor.fieldnames or ())
        respostas = list(leitor)
    if not respostas:
        return {"answers": []}
    if campos != CAMPOS_CSV:
        if not permitir_legado:
            raise ValueError("CSV fora do contrato: {}".format(caminho))
        campos_legados = (
            "rubric_version", "reviewer", "sample_id", "target_clarity",
            "category", "structure", "primary_color", "secondary_colors",
            "notes", "reviewed_at",
        )
        if campos != campos_legados:
            raise ValueError("CSV legado fora do contrato: {}".format(caminho))
        rubricas = {resposta.pop("rubric_version", "") for resposta in respostas}
        revisores = {resposta.pop("reviewer", "") for resposta in respostas}
        if len(rubricas) != 1 or len(revisores) != 1:
            raise ValueError("CSV mistura revisores ou versoes da rubrica: {}".format(
                caminho))
        for resposta in respostas:
            resposta["secondary_colors"] = _cores_secundarias(
                resposta.get("secondary_colors"))
        return {
            "rubric_version": next(iter(rubricas)),
            "reviewer": next(iter(revisores)),
            "answers": respostas,
        }

    contratos = {resposta.pop("contract", "") for resposta in respostas}
    lotes = {resposta.pop("batch_id", "") for resposta in respostas}
    rubricas = {resposta.pop("rubric_version", "") for resposta in respostas}
    revisores = {resposta.pop("reviewer", "") for resposta in respostas}
    exportados = {resposta.pop("exported_at", "") for resposta in respostas}
    if any(len(valores) != 1 for valores in (
            contratos, lotes, rubricas, revisores, exportados)):
        raise ValueError("CSV mistura revisores ou versoes da rubrica: {}".format(
            caminho))
    for resposta in respostas:
        resposta["secondary_colors"] = _cores_secundarias(
            resposta.get("secondary_colors"))
    return {
        "contract": next(iter(contratos)),
        "batch_id": next(iter(lotes)),
        "rubric_version": next(iter(rubricas)),
        "reviewer": next(iter(revisores)),
        "exported_at": next(iter(exportados)),
        "answers": respostas,
    }


def carregar_revisao(caminho, permitir_legado=False):
    dados = _dados_da_revisao(caminho, permitir_legado=permitir_legado)
    if not isinstance(dados, dict):
        raise ValueError("Envelope de revisao fora do contrato: {}".format(caminho))
    contrato = dados.get("contract")
    novo = contrato == CONTRATO_REVISAO
    gabarito = contrato == CONTRATO_GABARITO
    if not novo and not gabarito and not permitir_legado:
        raise ValueError("Contrato de revisao ausente ou desconhecido: {}".format(
            caminho))
    if novo and set(dados) != {
            "contract", "batch_id", "rubric_version", "reviewer",
            "exported_at", "answers"}:
        raise ValueError("Envelope de revisao fora do contrato: {}".format(caminho))
    if gabarito and set(dados) != {
            "contract", "batch_id", "reviewer", "rubric_version",
            "source_reviewers", "unresolved_non_gate_fields", "answers"}:
        raise ValueError("Envelope de gabarito fora do contrato: {}".format(caminho))
    if novo:
        if not isinstance(dados["batch_id"], str) or not re.fullmatch(
                r"[0-9a-f]{64}", dados["batch_id"]):
            raise ValueError("batch_id fora do contrato: {}".format(caminho))
        _instante(dados["exported_at"], "exported_at")
    elif gabarito:
        if not isinstance(dados.get("batch_id"), str) or not re.fullmatch(
                r"[0-9a-f]{64}", dados["batch_id"]):
            raise ValueError("batch_id do gabarito fora do contrato")

    reviewer = _validar_reviewer(dados.get("reviewer"))
    rubrica = _validar_rubrica(dados.get("rubric_version"))
    respostas = dados.get("answers")
    if not isinstance(respostas, list) or not respostas:
        raise ValueError("Revisao sem answers: {}".format(caminho))
    por_id = {}
    for resposta in respostas:
        if novo:
            _validar_resposta(resposta, estrita=True)
            revisada = dt.datetime.fromisoformat(
                resposta["reviewed_at"].replace("Z", "+00:00"))
            exportada = dt.datetime.fromisoformat(
                dados["exported_at"].replace("Z", "+00:00"))
            if revisada > exportada:
                raise ValueError("reviewed_at posterior a exported_at")
        elif gabarito:
            _validar_resposta(resposta, estrita=False)
        sample_id = resposta.get("sample_id")
        if not sample_id or sample_id in por_id:
            raise ValueError("sample_id ausente ou repetido em {}".format(caminho))
        ausentes = [campo for campo in CAMPOS_HUMANOS if campo not in resposta]
        if ausentes:
            raise ValueError("Campos ausentes em {}: {}".format(
                sample_id, ", ".join(ausentes)))
        por_id[sample_id] = resposta
    identidades = [
        (resposta.get("imagem"), resposta.get("image_sha256"))
        for resposta in por_id.values()
        if resposta.get("imagem") is not None
    ]
    if novo or gabarito:
        if len(set(identidades)) != len(identidades):
            raise ValueError("Revisao repete a mesma imagem: {}".format(caminho))
    return {
        "contract": contrato,
        "batch_id": dados.get("batch_id"),
        "reviewer": reviewer,
        "rubric_version": rubrica,
        "answers": por_id,
    }


def _comparavel(campo, valor):
    if campo == "secondary_colors":
        return tuple(sorted(valor))
    return valor


def comparar_revisoes(revisoes):
    if len(revisoes) < 2:
        raise ValueError("A comparacao cega exige pelo menos dois revisores.")
    revisores = [_validar_reviewer(revisao.get("reviewer"))
                 for revisao in revisoes]
    if len({revisor.casefold() for revisor in revisores}) != len(revisores):
        raise ValueError("Cada revisao deve ter um revisor distinto.")
    lotes_recebidos = [revisao.get("batch_id") for revisao in revisoes]
    if (any(not isinstance(lote, str)
            or not re.fullmatch(r"[0-9a-f]{64}", lote)
            for lote in lotes_recebidos)
            or len(set(lotes_recebidos)) != 1):
        raise ValueError("Revisoes nao pertencem ao mesmo batch_id valido.")
    lotes = set(lotes_recebidos)
    for revisao in revisoes:
        if not isinstance(revisao.get("answers"), dict) or not revisao["answers"]:
            raise ValueError("Revisao carregada sem respostas.")
        for resposta in revisao["answers"].values():
            _validar_resposta(resposta, estrita=True)
    ids = set(revisoes[0]["answers"])
    rubrica = _validar_rubrica(revisoes[0].get("rubric_version"))
    for revisao in revisoes[1:]:
        if set(revisao["answers"]) != ids:
            raise ValueError("Revisores nao cobrem as mesmas amostras.")
        if revisao["rubric_version"] != rubrica:
            raise ValueError("Revisores usaram versoes diferentes da rubrica.")
    for sample_id in ids:
        identidades = {
            (revisao["answers"][sample_id].get("imagem"),
             revisao["answers"][sample_id].get("image_sha256"))
            for revisao in revisoes
        }
        if (len(identidades) != 1 or None in next(iter(identidades))):
            raise ValueError(
                "Identidade da imagem diverge em {}.".format(sample_id))

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
        "batch_id": next(iter(lotes)),
        "rubric_version": rubrica,
        "reviewers": revisores,
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
    if not isinstance(adjudicacao.get("answers"), dict):
        raise ValueError("Adjudicacao sem respostas.")
    for resposta in adjudicacao["answers"].values():
        _validar_resposta(resposta, estrita=True)
    ids_adjudicados = set(adjudicacao["answers"])
    if ids_adjudicados != ids_divergentes:
        faltam = sorted(ids_divergentes - ids_adjudicados)
        sobram = sorted(ids_adjudicados - ids_divergentes)
        raise ValueError(
            "Adjudicacao deve cobrir apenas divergencias: faltam={}, sobram={}".format(
                faltam, sobram))
    if adjudicacao["rubric_version"] != comparacao["rubric_version"]:
        raise ValueError("Adjudicacao usou outra versao da rubrica.")
    if adjudicacao.get("batch_id") != comparacao["batch_id"]:
        raise ValueError("Adjudicacao pertence a outro batch_id.")
    adjudicador = _validar_reviewer(adjudicacao.get("reviewer"))
    if adjudicador.casefold() in {
            revisor.casefold() for revisor in comparacao["reviewers"]}:
        raise ValueError("O adjudicador deve ser terceiro revisor independente.")
    for sample_id in ids_divergentes:
        origem = revisoes[0]["answers"][sample_id]
        voto = adjudicacao["answers"][sample_id]
        if (voto.get("imagem"), voto.get("image_sha256")) != (
                origem.get("imagem"), origem.get("image_sha256")):
            raise ValueError(
                "Adjudicacao trouxe outra imagem em {}.".format(sample_id))

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
        if sample_id in ids_adjudicados:
            voto = adjudicacao["answers"][sample_id]
            final["adjudication_basis"] = voto.get("adjudication_basis", "")
            final["original_selection"] = voto.get("original_selection", {})
        respostas.append(final)
    return {
        "contract": CONTRATO_GABARITO,
        "batch_id": comparacao["batch_id"],
        "reviewer": "ADJUDICADO: {}".format(adjudicador),
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


def _previsao(resultado):
    """O que a rodada respondeu para uma imagem, incluindo o caso de nao ter.

    O avaliador guarda a imagem que falhou em vez de derrubar a rodada inteira:
    ela conta como erro no portao e fica auditavel. Duas rodadas pagas de 19/08
    morreram antes disso existir. Aqui a mesma linha chega com `analysis: null`,
    e ela precisa de um valor proprio por dois motivos.

    O primeiro e que nao responder nao e abster. Se a ausencia virasse
    `not_visible`, uma falha de contrato casaria com o gabarito das fotos cujo
    alvo e mesmo indeterminavel: erro premiado como acerto, e justamente no
    numero que autoriza gastar dinheiro.

    O segundo e mais simples: `None` puro derrubava a matriz de confusao na
    ordenacao, comparando `str` com `NoneType`. A rodada v7 de 20/08 foi a
    primeira a trazer uma linha assim, e o script morreu com os dados ja pagos
    na mao.
    """
    analise = resultado.get("analysis")
    if not analise:
        return {campo: SEM_RESPOSTA
                for campo in ("category", "primary_color", "target_clarity")}
    cores = analise.get("colors") or []
    return {
        "category": analise.get("category") or SEM_RESPOSTA,
        # Lista vazia com analise presente E abstencao: o modelo respondeu que
        # nao da para nomear a cor. Isso pode casar com o gabarito.
        "primary_color": cores[0] if cores else "not_visible",
        "target_clarity": analise.get("target_clarity") or SEM_RESPOSTA,
    }


def matriz_de_confusao(linhas, campo):
    contagens = {}
    for linha in linhas:
        if campo == "primary_color":
            ouro = "/".join(linha["accepted_primary_colors"])
        else:
            ouro = linha["gold"][campo]
        chave = (ouro, linha["predicted"][campo])
        contagens[chave] = contagens.get(chave, 0) + 1
    return [
        {"gold": ouro, "predicted": previsto, "count": quantidade}
        for (ouro, previsto), quantidade in sorted(contagens.items())
    ]


def _alinhar_por_imagem(respostas, resultados):
    """Casa gabarito e resultados pela IMAGEM, nao pela posicao.

    O `sample_id` e posicional: ele e atribuido por ordem de enumeracao da
    amostra, e a ordem muda entre execucoes. Medido em 19/08/2026: `S01` era
    `134.jpg` na rodada de 13/08 e `3011.jpg` na de hoje, com o MESMO conjunto
    de 24 imagens.

    A checagem antiga comparava apenas os CONJUNTOS de ids -- S01..S24 dos dois
    lados -- e passava. Depois comparava par a par por id, ou seja, comparava a
    resposta humana de uma foto com a leitura da Luna de outra. Gerou um portao
    dizendo 8,3% de acerto onde o numero real era 83,3%, e `passed: false`.

    Um portao errado e pior que portao nenhum: ele autoriza ou barra gasto de
    dinheiro com base em ruido. Entao aqui a regra e recusar, nunca adivinhar.
    """
    def imagens(colecao):
        return {chave: valor.get("imagem") for chave, valor in colecao.items()}

    das_respostas = imagens(respostas)
    dos_resultados = imagens(resultados)

    if any(v is None for v in dos_resultados.values()):
        raise ValueError(
            "Resultados sem `imagem`: nao da para garantir alinhamento.")
    if any(v is None for v in das_respostas.values()):
        raise ValueError(
            "Gabarito sem `imagem` por resposta. Sem isso o alinhamento "
            "dependeria do sample_id, que e posicional e muda entre execucoes.")

    por_imagem_resultado = {}
    for chave, imagem in dos_resultados.items():
        if imagem in por_imagem_resultado:
            raise ValueError("Imagem repetida nos resultados: {}".format(imagem))
        por_imagem_resultado[imagem] = resultados[chave]

    alinhado_respostas, alinhado_resultados = {}, {}
    faltam = []
    for chave, imagem in das_respostas.items():
        alvo = por_imagem_resultado.pop(imagem, None)
        if alvo is None:
            faltam.append(imagem)
            continue
        alinhado_respostas[imagem] = respostas[chave]
        alinhado_resultados[imagem] = alvo
    if faltam or por_imagem_resultado:
        raise ValueError(
            "Gabarito e resultados divergem por imagem: faltam={}, sobram={}"
            .format(sorted(faltam), sorted(por_imagem_resultado)))
    return alinhado_respostas, alinhado_resultados


def avaliar_contra_gabarito(gabarito, resultados):
    respostas = gabarito["answers"]
    # Coerencia dos resultados PRIMEIRO: e propriedade deles sozinhos, e uma
    # rodada com dois prompts misturados nao vale nem se estiver bem alinhada.
    versoes = {resultado.get("prompt_version") for resultado in resultados.values()}
    if len(versoes) != 1 or None in versoes:
        raise ValueError("Resultados nao registram uma unica prompt_version.")
    hashes = {resultado.get("prompt_sha256") for resultado in resultados.values()}
    if len(hashes) != 1 or None in hashes:
        raise ValueError("Resultados nao registram um unico prompt_sha256.")
    # So entao o pareamento, que envolve os dois lados.
    respostas, resultados = _alinhar_por_imagem(respostas, resultados)

    contagens = {
        "category": 0,
        "primary_color": 0,
        "target_clarity": 0,
    }
    linhas = []
    for sample_id in sorted(respostas):
        ouro = respostas[sample_id]
        previsto = _previsao(resultados[sample_id])
        cores_aceitas = ouro.get("acceptable_primary_colors") or [
            ouro["primary_color"]]
        if ouro["primary_color"] not in cores_aceitas:
            raise ValueError(
                "Cor primaria canonica ausente das alternativas em {}".format(
                    sample_id))
        correto = {
            campo: (
                previsto[campo] in cores_aceitas
                if campo == "primary_color"
                else previsto[campo] == ouro[campo]
            )
            for campo in contagens
        }
        for campo, acertou in correto.items():
            contagens[campo] += int(acertou)
        linhas.append({
            "sample_id": sample_id,
            "gold": {campo: ouro[campo] for campo in contagens},
            "accepted_primary_colors": cores_aceitas,
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
        "prompt_sha256": next(iter(hashes)),
        "rubric_version": gabarito["rubric_version"],
        "gold_reviewer": gabarito["reviewer"],
        "sample_size": total,
        "metrics": metricas,
        "passed": passou,
        "rows": linhas,
        "confusion_matrices": {
            "category": matriz_de_confusao(linhas, "category"),
            "primary_color": matriz_de_confusao(linhas, "primary_color"),
        },
    }


def combinar_avaliacoes(avaliacoes):
    """Junta rodadas do MESMO prompt numa medida só.

    POR QUE UMA RODADA NAO BASTA
    ============================

    A v7 foi medida tres vezes em 20/08/2026, sem mudar uma virgula do prompt,
    das 24 imagens ou do segmentador:

        rodada A   19/24 categoria   19/24 cor   -> FECHADO
        rodada B   20/24 categoria   21/24 cor   -> ABERTO
        rodada C   20/24 categoria   20/24 cor   -> ABERTO

    O portao corta em 80% e a amostra tem 24 itens: **uma imagem vale 4,2
    pontos**. `12550.jpg` sozinha deu tres respostas diferentes em quatro
    rodadas de prompts quase identicos. Ou seja, o veredito estava sendo
    decidido por sorteio tanto quanto por qualidade -- e um portao assim
    autoriza ou barra gasto de dinheiro por ruido.

    Somar as rodadas nao deixa a medida mais generosa, deixa mais estavel: o
    intervalo de confianca encolhe porque ha mais observacoes, e uma imagem
    instavel deixa de mover o resultado sozinha.

    Exige o mesmo `prompt_sha256` nos dois lados. Rodadas de prompts diferentes
    somadas dariam um numero que nao descreve prompt nenhum.
    """
    if not avaliacoes:
        raise ValueError("Nenhuma avaliacao para combinar.")
    if len(avaliacoes) == 1:
        return avaliacoes[0]

    hashes = {a["prompt_sha256"] for a in avaliacoes}
    if len(hashes) != 1:
        raise ValueError(
            "Rodadas de prompts diferentes nao se somam: {}".format(
                sorted(h[:8] for h in hashes)))
    rubricas = {a["rubric_version"] for a in avaliacoes}
    if len(rubricas) != 1:
        raise ValueError("Rodadas medidas contra rubricas diferentes.")

    campos = list(avaliacoes[0]["metrics"])
    metricas = {}
    for campo in campos:
        acertos = sum(a["metrics"][campo]["correct"] for a in avaliacoes)
        total = sum(a["metrics"][campo]["total"] for a in avaliacoes)
        metricas[campo] = {
            "correct": acertos,
            "total": total,
            "accuracy": acertos / total,
            "wilson_95": list(intervalo_wilson(acertos, total)),
        }

    combinada = dict(avaliacoes[0])
    combinada["metrics"] = metricas
    combinada["sample_size"] = sum(a["sample_size"] for a in avaliacoes)
    combinada["runs"] = len(avaliacoes)
    combinada["passed"] = (metricas["category"]["accuracy"] >= 0.80
                           and metricas["primary_color"]["accuracy"] >= 0.80)
    # As rodadas continuam visiveis uma a uma. Esconder a dispersao atras da
    # media seria trocar um numero enganoso por outro.
    combinada["por_rodada"] = [
        {campo: {"correct": a["metrics"][campo]["correct"],
                 "total": a["metrics"][campo]["total"]}
         for campo in campos}
        for a in avaliacoes
    ]
    # Matriz e divergencias vem das rodadas empilhadas, para nenhuma sumir.
    combinada["rows"] = [linha for a in avaliacoes for linha in a["rows"]]
    combinada["confusion_matrices"] = {
        campo: matriz_de_confusao(combinada["rows"], campo)
        for campo in ("category", "primary_color")
    }
    return combinada


def relatorio_markdown(comparacao=None, avaliacao=None, ouro_adjudicado=None):
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

    if ouro_adjudicado:
        linhas += [
            "## Adjudicação concluída",
            "",
            "O comentário descritivo prevalece sobre clique contraditório. "
            "Cores pertencem somente à peça-alvo; fundo e outras roupas não entram.",
            "",
        ]
        for resposta in ouro_adjudicado["answers"]:
            base = resposta.get("adjudication_basis")
            if not base:
                continue
            linhas.append("- **{} — {} · {}:** {}".format(
                resposta["sample_id"], resposta["category"],
                resposta["primary_color"], base))
        linhas.append("")

    if avaliacao:
        linhas += [
            "## Prompt contra gabarito adjudicado",
            "",
            "Prompt: `{}`. Amostra: **{}**{}. Portao: **{}**.".format(
                avaliacao["prompt_version"], avaliacao["sample_size"],
                (" em {} rodadas".format(avaliacao["runs"])
                 if avaliacao.get("runs") else ""),
                "ABERTO" if avaliacao["passed"] else "FECHADO"),
            "SHA-256 do prompt: `{}`.".format(avaliacao["prompt_sha256"]),
            "",
            "| medida | acertos | resultado | IC 95% Wilson |",
            "|---|---:|---:|---:|",
        ]
        for campo, metrica in avaliacao["metrics"].items():
            inferior, superior = metrica["wilson_95"]
            linhas.append("| {} | {}/{} | {:.1%} | {:.1%}–{:.1%} |".format(
                campo, metrica["correct"], metrica["total"],
                metrica["accuracy"], inferior, superior))
        # A dispersao entre rodadas fica a vista. Foi ela que fechou e abriu o
        # portao no mesmo dia, com o mesmo prompt.
        if avaliacao.get("por_rodada"):
            campos = list(avaliacao["metrics"])
            linhas += [
                "",
                "### Rodada a rodada, mesmo prompt",
                "",
                "| rodada | " + " | ".join(campos) + " |",
                "|---" * (len(campos) + 1) + "|",
            ]
            for indice, rodada in enumerate(avaliacao["por_rodada"], 1):
                celulas = ["{}/{} ({:.1%})".format(
                    rodada[c]["correct"], rodada[c]["total"],
                    rodada[c]["correct"] / rodada[c]["total"])
                    for c in campos]
                linhas.append("| {} | {} |".format(indice, " | ".join(celulas)))
        for campo in ("category", "primary_color"):
            linhas += [
                "",
                "### Matriz de confusão — {}".format(campo),
                "",
                "| ouro | Luna | n |",
                "|---|---|---:|",
            ]
            for celula in avaliacao["confusion_matrices"][campo]:
                linhas.append("| {} | {} | {} |".format(
                    celula["gold"], celula["predicted"], celula["count"]))
        divergentes = [
            linha for linha in avaliacao["rows"]
            if not all(linha["correct"].values())
        ]
        linhas += ["", "### Divergencias", ""]
        rodadas = avaliacao.get("runs") or 1
        if rodadas > 1:
            linhas.append(
                "Em quantas das {} rodadas cada imagem divergiu. Imagem que "
                "erra em todas e limitacao de prompt; imagem que erra em "
                "algumas e a amostra sorteando.".format(rodadas))
            linhas.append("")
        if not divergentes:
            linhas.append("Nenhuma divergencia.")
        vistos = {}
        for linha in divergentes:
            detalhes = []
            for campo, certo in linha["correct"].items():
                if certo:
                    continue
                ouro = ("/".join(linha["accepted_primary_colors"])
                        if campo == "primary_color"
                        else linha["gold"][campo])
                detalhes.append("{}: {} → {}".format(
                    campo, ouro, linha["predicted"][campo]))
            vistos.setdefault(linha["sample_id"], []).append("; ".join(detalhes))
        for imagem in sorted(vistos):
            ocorrencias = vistos[imagem]
            if rodadas > 1:
                sufixo = " *({}/{} rodadas)*".format(len(ocorrencias), rodadas)
            else:
                sufixo = ""
            # Divergencias identicas nas varias rodadas viram uma linha só.
            unicas = sorted(set(ocorrencias))
            linhas.append("- **{}**{}: {}".format(
                imagem, sufixo, " · ".join(unicas)))
        linhas.append("")
    return "\n".join(linhas)


def argumentos():
    parser = argparse.ArgumentParser()
    parser.add_argument("--revisoes", nargs="*", type=Path, default=[])
    parser.add_argument("--gabarito", type=Path)
    # Varios JSONL do MESMO prompt entram juntos. Ver `combinar_avaliacoes`.
    parser.add_argument("--resultados", nargs="*", type=Path, default=[])
    parser.add_argument("--adjudicacao", type=Path)
    parser.add_argument("--gabarito-saida", type=Path)
    parser.add_argument("--relatorio", type=Path, required=True)
    parser.add_argument("--portao", type=Path)
    return parser.parse_args()


def main():
    args = argumentos()
    comparacao = None
    avaliacao = None
    ouro_adjudicado = None
    if args.revisoes:
        revisoes = [carregar_revisao(caminho) for caminho in args.revisoes]
        comparacao = comparar_revisoes(revisoes)
        if bool(args.adjudicacao) != bool(args.gabarito_saida):
            raise SystemExit(
                "--adjudicacao e --gabarito-saida devem ser usados juntos")
        if args.adjudicacao:
            ouro_adjudicado = adjudicar_revisoes(
                revisoes, carregar_revisao(args.adjudicacao))
            args.gabarito_saida.write_text(
                json.dumps(ouro_adjudicado, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8")
    elif args.adjudicacao or args.gabarito_saida:
        raise SystemExit("Adjudicacao exige --revisoes")
    if bool(args.gabarito) != bool(args.resultados):
        raise SystemExit("--gabarito e --resultados devem ser usados juntos")
    if args.gabarito:
        ouro = carregar_revisao(args.gabarito, permitir_legado=True)
        avaliacao = combinar_avaliacoes([
            avaliar_contra_gabarito(ouro, carregar_resultados(caminho))
            for caminho in args.resultados
        ])
    if not comparacao and not avaliacao:
        raise SystemExit("Informe revisoes ou gabarito+resultados")
    args.relatorio.write_text(
        relatorio_markdown(comparacao, avaliacao, ouro_adjudicado).rstrip() + "\n",
        encoding="utf-8")
    if args.portao:
        if not avaliacao:
            raise SystemExit("--portao exige gabarito+resultados")
        portao = {
            "prompt_version": avaliacao["prompt_version"],
            "prompt_sha256": avaliacao["prompt_sha256"],
            "rubric_version": avaliacao["rubric_version"],
            "runs": avaliacao.get("runs", 1),
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
