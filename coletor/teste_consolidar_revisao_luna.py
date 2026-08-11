"""Testes sem rede da consolidacao humana do Luna."""

import importlib.util
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


def montar_avaliacao(acertos_categoria=20, acertos_cor=20):
    respostas = {}
    resultados = {}
    for numero in range(1, 25):
        sample_id = "S{:02d}".format(numero)
        respostas[sample_id] = resposta(sample_id)
        resultados[sample_id] = {
            "sample_id": sample_id,
            "prompt_version": "alvo-estrutura-v2",
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
        testar_portao_exige_categoria_e_cor,
        testar_prompt_misto_e_recusado,
    ]
    for teste in testes:
        teste()
    print("{} testes da consolidacao Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
