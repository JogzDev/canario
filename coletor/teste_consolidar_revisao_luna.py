"""Testes sem rede da consolidacao humana do Luna."""

import importlib.util
import csv
import json
from pathlib import Path
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
CAMINHO = RAIZ / "ferramentas" / "consolidar_revisao_luna.py"
SPEC = importlib.util.spec_from_file_location("consolidar_revisao_luna", CAMINHO)
MODULO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULO)


def resposta(sample_id, categoria="camisa", cor="branco_cru"):
    return {
        "sample_id": sample_id,
        "target_clarity": "clear",
        "category": categoria,
        "structure": "upper_shirt_construction",
        "primary_color": cor,
        "secondary_colors": ["vermelho_rosa", "azul"],
        "notes": "",
        "reviewed_at": "2026-08-11T00:00:00Z",
    }


def escrever_revisao(caminho, nome, respostas):
    caminho.write_text(json.dumps({
        "rubric_version": "categoria-cor-v2",
        "reviewer": nome,
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
            "fields": {"category": {"A": "camisa", "B": "blusa_top"}},
        }]


def testar_csv_preserva_comentario_e_normaliza_cores():
    with tempfile.TemporaryDirectory() as temporaria:
        caminho = Path(temporaria) / "jp.csv"
        with caminho.open("w", encoding="utf-8", newline="") as arquivo:
            escritor = csv.DictWriter(arquivo, fieldnames=[
                "rubric_version", "reviewer", "sample_id", "target_clarity",
                "category", "structure", "primary_color", "secondary_colors",
                "notes", "reviewed_at",
            ])
            escritor.writeheader()
            escritor.writerow({
                "rubric_version": "categoria-cor-v2",
                "reviewer": "JP",
                "sample_id": "S14",
                "target_clarity": "ambiguous_target",
                "category": "not_visible",
                "structure": "target_not_determinable",
                "primary_color": "not_visible",
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


def testar_adjudicacao_parcial_fecha_ouro():
    revisao_a = {
        "reviewer": "A", "rubric_version": "categoria-cor-v2",
        "answers": {"S01": resposta("S01"), "S02": resposta("S02")},
    }
    revisao_b = {
        "reviewer": "B", "rubric_version": "categoria-cor-v2",
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
        "reviewer": "JP", "rubric_version": "categoria-cor-v2",
        "answers": {"S02": voto},
    }
    ouro = MODULO.adjudicar_revisoes(
        [revisao_a, revisao_b], adjudicacao)
    assert len(ouro["answers"]) == 2
    assert ouro["answers"][0]["category"] == "camisa"
    assert ouro["answers"][1]["category"] == "blusa_top"
    assert ouro["answers"][1]["structure"] == "upper_other"
    assert ouro["answers"][1]["notes"] == (
        "Blusa residual, sem construção de camisaria.")
    assert ouro["answers"][1]["adjudication_basis"] == (
        "A descrição visual resolve o clique.")


def montar_avaliacao(acertos_categoria=20, acertos_cor=20):
    respostas = {}
    resultados = {}
    for numero in range(1, 25):
        sample_id = "S{:02d}".format(numero)
        respostas[sample_id] = resposta(sample_id)
        resultados[sample_id] = {
            "sample_id": sample_id,
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


def main():
    testes = [
        testar_comparacao_independente,
        testar_csv_preserva_comentario_e_normaliza_cores,
        testar_adjudicacao_parcial_fecha_ouro,
        testar_portao_exige_categoria_e_cor,
        testar_cor_primaria_empatada_aceita_as_duas_sem_esconder_a_matriz,
        testar_prompt_misto_e_recusado,
    ]
    for teste in testes:
        teste()
    print("{} testes da consolidacao Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
