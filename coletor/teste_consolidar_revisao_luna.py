"""Testes sem rede da consolidacao humana do Luna."""

import importlib.util
import csv
import json
from pathlib import Path
import tempfile
import copy


RAIZ = Path(__file__).resolve().parents[1]
CAMINHO = RAIZ / "ferramentas" / "consolidar_revisao_luna.py"
SPEC = importlib.util.spec_from_file_location("consolidar_revisao_luna", CAMINHO)
MODULO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULO)
BATCH_ID = "a" * 64
IMAGE_SHA = "b" * 64


def resposta(sample_id, categoria="camisa", cor="branco_cru", imagem=None):
    estruturas = {
        "camisa": "upper_shirt_construction",
        "blusa_top": "upper_other",
        "not_visible": "target_not_determinable",
    }
    ambiguo = categoria == "not_visible"
    return {
        "sample_id": sample_id,
        # O gabarito carrega a IMAGEM desde 19/08: o sample_id e posicional e
        # muda entre execucoes, e casar por ele comparava a resposta humana de
        # uma foto com a leitura da Luna de outra.
        "imagem": imagem or "{}.jpg".format(sample_id),
        "image_sha256": IMAGE_SHA,
        "target_clarity": "ambiguous_target" if ambiguo else "clear",
        "category": categoria,
        "structure": estruturas[categoria],
        "primary_color": "not_visible" if ambiguo else cor,
        "secondary_colors": [] if ambiguo else ["vermelho_rosa", "azul"],
        "notes": "",
        "reviewed_at": "2026-08-11T00:00:00Z",
    }


def escrever_revisao(caminho, nome, respostas):
    caminho.write_text(json.dumps({
        "contract": MODULO.CONTRATO_REVISAO,
        "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "reviewer": nome,
        "exported_at": "2026-08-11T01:00:00Z",
        "answers": respostas,
    }), encoding="utf-8")


def testar_comparacao_independente():
    with tempfile.TemporaryDirectory() as temporaria:
        pasta = Path(temporaria)
        a = [resposta("S01"), resposta("S02")]
        b = [resposta("S01"), resposta("S02", categoria="blusa_top")]
        b[0]["secondary_colors"] = ["azul", "vermelho_rosa"]
        escrever_revisao(pasta / "a.json", "A", a)
        escrever_revisao(pasta / "b.json", "B", b)
        revisoes = [
            MODULO.carregar_revisao(pasta / "a.json"),
            MODULO.carregar_revisao(pasta / "b.json"),
        ]
        comparacao = MODULO.comparar_revisoes(revisoes)
        assert comparacao["agreements"]["category"] == 1
        assert comparacao["agreements"]["secondary_colors"] == 2
        assert comparacao["disagreements"] == [{
            "sample_id": "S02",
            "fields": {
                "category": {"A": "camisa", "B": "blusa_top"},
                "structure": {
                    "A": "upper_shirt_construction", "B": "upper_other",
                },
            },
        }]


def testar_csv_preserva_comentario_e_normaliza_cores():
    with tempfile.TemporaryDirectory() as temporaria:
        caminho = Path(temporaria) / "jp.csv"
        with caminho.open("w", encoding="utf-8", newline="") as arquivo:
            escritor = csv.DictWriter(arquivo, fieldnames=[
                "contract", "batch_id", "rubric_version", "reviewer",
                "exported_at", "sample_id", "imagem", "image_sha256",
                "target_clarity", "category", "structure", "primary_color",
                "secondary_colors", "notes", "reviewed_at",
            ])
            escritor.writeheader()
            escritor.writerow({
                "contract": MODULO.CONTRATO_REVISAO,
                "batch_id": BATCH_ID,
                "rubric_version": "categoria-cor-v2",
                "reviewer": "JP",
                "exported_at": "2026-08-12T01:00:00Z",
                "sample_id": "S14",
                "imagem": "14.jpg",
                "image_sha256": IMAGE_SHA,
                "target_clarity": "clear",
                "category": "camisa",
                "structure": "upper_shirt_construction",
                "primary_color": "preto",
                "secondary_colors": "branco_cru|verde",
                "notes": "O verde pertence ao fundo; a peça parece um conjunto.",
                "reviewed_at": "2026-08-12T00:00:00Z",
            })
        revisao = MODULO.carregar_revisao(caminho)
        resposta_lida = revisao["answers"]["S14"]
        assert revisao["reviewer"] == "JP"
        assert resposta_lida["secondary_colors"] == ["branco_cru", "verde"]
        assert resposta_lida["notes"] == (
            "O verde pertence ao fundo; a peça parece um conjunto.")


def testar_revisao_nova_falha_fechada_em_campos_e_semantica():
    base = {
        "contract": MODULO.CONTRATO_REVISAO,
        "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "reviewer": "R1",
        "exported_at": "2026-08-11T01:00:00Z",
        "answers": [resposta("S01")],
    }

    def alterar_reviewer(v):
        v["reviewer"] = ""

    def alterar_rubrica(v):
        v["rubric_version"] = "categoria-cor-v999"

    def alterar_enum(v):
        v["answers"][0]["target_clarity"] = "talvez"

    def alterar_categoria(v):
        v["answers"][0]["category"] = "blusa_top"

    def alterar_cores(v):
        v["answers"][0]["secondary_colors"] = ["azul", "azul"]

    def alterar_timestamp(v):
        v["answers"][0]["reviewed_at"] = "2026-08-11T00:00:00"

    def alterar_cronologia(v):
        v["answers"][0]["reviewed_at"] = "2026-08-11T02:00:00Z"

    def adicionar_campo(v):
        v["answers"][0]["surpresa"] = True

    with tempfile.TemporaryDirectory() as temporaria:
        pasta = Path(temporaria)
        for indice, mutacao in enumerate((
                alterar_reviewer, alterar_rubrica, alterar_enum,
                alterar_categoria, alterar_cores, alterar_timestamp,
                alterar_cronologia, adicionar_campo)):
            dados = copy.deepcopy(base)
            mutacao(dados)
            caminho = pasta / "invalida-{}.json".format(indice)
            caminho.write_text(json.dumps(dados), encoding="utf-8")
            try:
                MODULO.carregar_revisao(caminho)
            except ValueError:
                pass
            else:
                raise AssertionError("revisao malformada foi aceita: {}".format(
                    mutacao.__name__))


def testar_comparacao_exige_lote_e_revisores_distintos():
    primeira = {
        "reviewer": "R1", "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "answers": {"S01": resposta("S01")},
    }
    repetida = copy.deepcopy(primeira)
    try:
        MODULO.comparar_revisoes([primeira, repetida])
    except ValueError as erro:
        assert "distinto" in str(erro).lower()
    else:
        raise AssertionError("mesmo revisor contou duas vezes")

    segunda = copy.deepcopy(primeira)
    segunda["reviewer"] = "R2"
    segunda["batch_id"] = "c" * 64
    try:
        MODULO.comparar_revisoes([primeira, segunda])
    except ValueError as erro:
        assert "batch_id" in str(erro)
    else:
        raise AssertionError("lotes diferentes foram comparados")


def testar_adjudicacao_parcial_fecha_ouro():
    revisao_a = {
        "reviewer": "A", "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "answers": {"S01": resposta("S01"), "S02": resposta("S02")},
    }
    revisao_b = {
        "reviewer": "B", "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "answers": {
            "S01": resposta("S01"),
            "S02": resposta("S02", categoria="blusa_top"),
        },
    }
    revisao_b["answers"]["S02"]["structure"] = "upper_other"
    voto = resposta("S02", categoria="blusa_top")
    voto["structure"] = "upper_other"
    voto["notes"] = "Blusa residual, sem construção de camisaria."
    voto["adjudication_basis"] = "A descrição visual resolve o clique."
    adjudicacao = {
        "reviewer": "JP", "batch_id": BATCH_ID,
        "rubric_version": "categoria-cor-v2",
        "answers": {"S02": voto},
    }
    ouro = MODULO.adjudicar_revisoes(
        [revisao_a, revisao_b], adjudicacao)
    assert ouro["contract"] == MODULO.CONTRATO_GABARITO
    assert ouro["batch_id"] == BATCH_ID
    assert len(ouro["answers"]) == 2
    assert ouro["answers"][0]["category"] == "camisa"
    assert ouro["answers"][1]["category"] == "blusa_top"
    assert ouro["answers"][1]["structure"] == "upper_other"
    assert ouro["answers"][1]["notes"] == (
        "Blusa residual, sem construção de camisaria.")
    assert ouro["answers"][1]["adjudication_basis"] == (
        "A descrição visual resolve o clique.")
    with tempfile.TemporaryDirectory() as temporaria:
        caminho_ouro = Path(temporaria) / "ouro.json"
        caminho_ouro.write_text(json.dumps(ouro), encoding="utf-8")
        recarregado = MODULO.carregar_revisao(caminho_ouro)
        assert recarregado["batch_id"] == BATCH_ID
        assert set(recarregado["answers"]) == {"S01", "S02"}

    adjudicacao_repetida = copy.deepcopy(adjudicacao)
    adjudicacao_repetida["reviewer"] = "A"
    try:
        MODULO.adjudicar_revisoes(
            [revisao_a, revisao_b], adjudicacao_repetida)
    except ValueError as erro:
        assert "terceiro" in str(erro).lower()
    else:
        raise AssertionError("um dos revisores foi aceito como adjudicador")


def montar_avaliacao(acertos_categoria=20, acertos_cor=20):
    respostas = {}
    resultados = {}
    for numero in range(1, 25):
        sample_id = "S{:02d}".format(numero)
        respostas[sample_id] = resposta(sample_id)
        resultados[sample_id] = {
            "sample_id": sample_id,
            "imagem": "{}.jpg".format(sample_id),
            "prompt_version": "alvo-estrutura-v2",
            "prompt_sha256": "a" * 64,
            "analysis": {
                "category": "camisa" if numero <= acertos_categoria else "blusa_top",
                "colors": ["branco_cru" if numero <= acertos_cor else "preto"],
                "target_clarity": "clear",
            },
        }
    gabarito = {
        "reviewer": "ADJUDICADO",
        "rubric_version": "categoria-cor-v2",
        "answers": respostas,
    }
    return MODULO.avaliar_contra_gabarito(gabarito, resultados)


def testar_portao_exige_categoria_e_cor():
    passou = montar_avaliacao(20, 20)
    assert passou["passed"] is True
    assert passou["metrics"]["category"]["accuracy"] == 20 / 24
    assert passou["metrics"]["primary_color"]["accuracy"] == 20 / 24
    inferior, superior = passou["metrics"]["category"]["wilson_95"]
    assert 0 < inferior < 20 / 24 < superior < 1

    falhou = montar_avaliacao(20, 19)
    assert falhou["passed"] is False


def testar_cor_primaria_empatada_aceita_as_duas_sem_esconder_a_matriz():
    respostas = {"S01": resposta("S01", cor="branco_cru")}
    respostas["S01"]["acceptable_primary_colors"] = [
        "branco_cru", "preto"]
    gabarito = {
        "reviewer": "ADJUDICADO",
        "rubric_version": "categoria-cor-v3",
        "answers": respostas,
    }
    resultados = {
        "S01": {
            "sample_id": "S01",
            "imagem": "S01.jpg",
            "prompt_version": "alvo-estrutura-v4",
            "prompt_sha256": "b" * 64,
            "analysis": {
                "category": "camisa",
                "colors": ["preto", "branco_cru"],
                "target_clarity": "clear",
            },
        },
    }
    avaliacao = MODULO.avaliar_contra_gabarito(gabarito, resultados)
    assert avaliacao["metrics"]["primary_color"]["correct"] == 1
    assert avaliacao["rows"][0]["accepted_primary_colors"] == [
        "branco_cru", "preto"]
    assert avaliacao["confusion_matrices"]["primary_color"] == [{
        "gold": "branco_cru/preto", "predicted": "preto", "count": 1,
    }]


def testar_prompt_misto_e_recusado():
    respostas = {"S01": resposta("S01")}
    gabarito = {
        "reviewer": "ADJUDICADO",
        "rubric_version": "categoria-cor-v2",
        "answers": respostas,
    }
    resultados = {
        "S01": {
            "sample_id": "S01",
            "prompt_version": None,
            "prompt_sha256": None,
            "analysis": {"category": "camisa", "colors": ["branco_cru"]},
        },
    }
    try:
        MODULO.avaliar_contra_gabarito(gabarito, resultados)
    except ValueError as erro:
        assert "prompt_version" in str(erro)
    else:
        raise AssertionError("Resultado sem versao nao pode abrir portao")


def testar_ordem_trocada_nao_gera_portao_errado():
    """O bug de 19/08: `sample_id` e posicional e trocou de ordem entre rodadas.

    S01 era `134.jpg` em 13/08 e `3011.jpg` em 19/08, com o MESMO conjunto de 24
    imagens. A checagem antiga so comparava os CONJUNTOS de ids, passava, e
    depois comparava par a par por id -- resposta humana de uma foto contra
    leitura da Luna de outra. Gerou um portao dizendo 8,3% onde o real era
    83,3%, com `passed: false`.

    Portao errado e pior que portao nenhum: ele libera ou barra gasto de
    dinheiro com base em ruido.
    """
    respostas, resultados = {}, {}
    for numero in range(1, 25):
        sid = "S{:02d}".format(numero)
        imagem = "foto{:02d}.jpg".format(numero)
        respostas[sid] = resposta(sid, imagem=imagem)
        # A rodada nova enumerou a MESMA amostra em outra ordem: o id S01 caiu
        # numa imagem diferente. Todo o resto e identico.
        outro = "S{:02d}".format(25 - numero)
        resultados[outro] = {
            "sample_id": outro,
            "imagem": imagem,
            "prompt_version": "alvo-estrutura-v6",
            "prompt_sha256": "c" * 64,
            "analysis": {
                "category": "camisa",
                "colors": ["branco_cru"],
                "target_clarity": "clear",
            },
        }
    gabarito = {
        "reviewer": "ADJUDICADO",
        "rubric_version": "categoria-cor-v3",
        "answers": respostas,
    }
    avaliacao = MODULO.avaliar_contra_gabarito(gabarito, resultados)
    assert avaliacao["metrics"]["category"]["accuracy"] == 1.0, (
        "casou por posicao em vez de por imagem: {}".format(
            avaliacao["metrics"]["category"]["accuracy"]))
    assert avaliacao["passed"] is True


def testar_resultado_sem_imagem_e_recusado():
    """Sem imagem nos dois lados o alinhamento seria adivinhacao. Recusa."""
    respostas = {"S01": resposta("S01", imagem="a.jpg")}
    gabarito = {"reviewer": "ADJUDICADO", "rubric_version": "categoria-cor-v3",
                "answers": respostas}
    resultados = {"S01": {"sample_id": "S01", "prompt_version": "v6",
                          "prompt_sha256": "d" * 64, "analysis": {}}}
    try:
        MODULO.avaliar_contra_gabarito(gabarito, resultados)
    except ValueError as erro:
        assert "imagem" in str(erro).lower()
    else:
        raise AssertionError("resultado sem imagem nao pode gerar portao")


def testar_imagem_sem_analise_conta_como_erro_e_nao_derruba_o_relatorio():
    """Imagem que voltou sem analise: erro, nunca abstencao premiada.

    A rodada v7 de 20/08 trouxe `1040.jpg` com `analysis: null` -- o modelo
    marcou alvo ambiguo e mesmo assim preencheu `pattern`, e o validador do
    avaliador recusou. O avaliador guarda a linha de proposito, para a falha
    contar no portao sem levar junto as outras 23 medidas ja pagas.

    Aqui isso quebrava de duas formas. A ordenacao da matriz de confusao
    comparava `str` com `None` e o script morria com os dados pagos na mao. E a
    cor caia em `not_visible`, que e resposta legitima quando o alvo e mesmo
    indeterminavel -- entao uma falha de contrato casaria com o gabarito dessas
    fotos, virando acerto.
    """
    respostas = {
        "S01": resposta("S01", imagem="ok.jpg"),
        "S02": resposta("S02", categoria="not_visible", cor="not_visible",
                        imagem="falhou.jpg"),
    }
    gabarito = {"reviewer": "ADJUDICADO", "rubric_version": "categoria-cor-v3",
                "answers": respostas}
    resultados = {
        "S01": {
            "sample_id": "S01", "imagem": "ok.jpg",
            "prompt_version": "alvo-estrutura-v7", "prompt_sha256": "e" * 64,
            "analysis": {"category": "camisa", "colors": ["branco_cru"],
                         "target_clarity": "clear"},
        },
        # O gabarito desta foto e abster em tudo. Se a ausencia de resposta
        # virasse `not_visible`, esta linha marcaria 2/2.
        "S02": {
            "sample_id": "S02", "imagem": "falhou.jpg",
            "prompt_version": "alvo-estrutura-v7", "prompt_sha256": "e" * 64,
            "analysis": None,
            "validation_error": "Alvo ambiguo precisa abster nos escalares",
        },
    }
    avaliacao = MODULO.avaliar_contra_gabarito(gabarito, resultados)
    assert avaliacao["metrics"]["category"]["accuracy"] == 0.5
    assert avaliacao["metrics"]["primary_color"]["accuracy"] == 0.5, (
        "falha de contrato foi premiada como abstencao correta")
    assert avaliacao["metrics"]["target_clarity"]["accuracy"] == 0.5

    for campo in ("category", "primary_color"):
        previstos = {linha["predicted"]
                     for linha in avaliacao["confusion_matrices"][campo]}
        assert MODULO.SEM_RESPOSTA in previstos, (
            "a matriz de {} esconde a imagem sem resposta".format(campo))

    # E o relatorio inteiro precisa sair: era aqui que o script morria.
    texto = MODULO.relatorio_markdown(avaliacao=avaliacao)
    assert MODULO.SEM_RESPOSTA in texto
    assert "falhou.jpg" in texto


def testar_rodadas_do_mesmo_prompt_somam_em_vez_de_sortear():
    """Uma rodada de 24 nao decide um portao de 80%.

    A v7 foi medida tres vezes em 20/08, sem mudar nada: 79,2% / 83,3% / 83,3%
    em categoria. O portao fechou na primeira e abriu nas outras duas. Uma
    imagem vale 4,2 pontos numa amostra de 24, entao o veredito estava sendo
    sorteado. Somando as rodadas o denominador triplica e o intervalo encolhe.
    """
    a = montar_avaliacao(19, 19)
    b = montar_avaliacao(20, 21)
    c = montar_avaliacao(20, 20)
    assert a["passed"] is False, "a rodada azarada precisa reprovar sozinha"

    junto = MODULO.combinar_avaliacoes([a, b, c])
    assert junto["runs"] == 3
    assert junto["sample_size"] == 72
    assert junto["metrics"]["category"]["correct"] == 59
    assert junto["metrics"]["category"]["total"] == 72
    assert junto["passed"] is True

    # O intervalo tem de encolher: e a razao inteira de somar.
    largura = lambda m: m["wilson_95"][1] - m["wilson_95"][0]
    assert largura(junto["metrics"]["category"]) < largura(a["metrics"]["category"])

    # E a dispersao nao pode sumir atras da media.
    assert [r["category"]["correct"] for r in junto["por_rodada"]] == [19, 20, 20]

    texto = MODULO.relatorio_markdown(avaliacao=junto)
    assert "3 rodadas" in texto
    assert "Rodada a rodada" in texto


def testar_rodadas_de_prompts_diferentes_nao_se_somam():
    """Somar v6 com v7 daria um numero que nao descreve prompt nenhum."""
    a = montar_avaliacao(20, 20)
    b = montar_avaliacao(20, 20)
    b["prompt_sha256"] = "f" * 64
    try:
        MODULO.combinar_avaliacoes([a, b])
    except ValueError as erro:
        assert "prompt" in str(erro).lower()
    else:
        raise AssertionError("prompts diferentes nao podem virar um portao só")


def main():
    testes = [
        testar_comparacao_independente,
        testar_csv_preserva_comentario_e_normaliza_cores,
        testar_revisao_nova_falha_fechada_em_campos_e_semantica,
        testar_comparacao_exige_lote_e_revisores_distintos,
        testar_adjudicacao_parcial_fecha_ouro,
        testar_portao_exige_categoria_e_cor,
        testar_cor_primaria_empatada_aceita_as_duas_sem_esconder_a_matriz,
        testar_prompt_misto_e_recusado,
        testar_ordem_trocada_nao_gera_portao_errado,
        testar_resultado_sem_imagem_e_recusado,
        testar_imagem_sem_analise_conta_como_erro_e_nao_derruba_o_relatorio,
        testar_rodadas_do_mesmo_prompt_somam_em_vez_de_sortear,
        testar_rodadas_de_prompts_diferentes_nao_se_somam,
    ]
    for teste in testes:
        teste()
    print("{} testes da consolidacao Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
