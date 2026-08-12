"""Testes sem rede do contrato de avaliacao do Luna."""

import importlib.util
import json
from pathlib import Path
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
CAMINHO = RAIZ / "ferramentas" / "avaliar_luna.py"
SPEC = importlib.util.spec_from_file_location("avaliar_luna", CAMINHO)
MODULO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULO)


def testar_taxonomia_e_schema():
    taxonomia = MODULO.carregar_taxonomia(RAIZ / "anexos" / "taxonomia.csv")
    assert MODULO.ids(taxonomia, "categoria") == [
        "vestido", "saia", "blusa_top", "camisa", "calca", "short",
        "casaco_jaqueta", "macacao",
    ]
    assert sum(len(itens) for itens in taxonomia.values()) == 41
    schema = MODULO.montar_schema(taxonomia)
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == set(schema["properties"])
    assert "category" not in schema["properties"]
    assert schema["properties"]["target_clarity"]["enum"][-1] == "ambiguous_target"
    assert schema["properties"]["garment_structure"]["enum"][-1] == "target_not_determinable"
    assert schema["properties"]["colors"]["items"]["enum"][-1] == "outras_cores"
    assert "uniqueItems" not in schema["properties"]["colors"]
    assert schema["properties"]["colors"]["maxItems"] == 3

    prompt = " ".join(MODULO.instrucoes(taxonomia).split())
    assert "Do not simply choose the most colorful garment" in prompt
    assert "A tie-front shirt remains a shirt" in prompt
    assert "Decorative buttons alone are insufficient" in prompt
    assert "Sleeve length is never evidence for shorts" in prompt
    assert "label only the exterior construction actually visible" in prompt
    assert "A coordinated matching set is still multiple garments" in prompt
    assert "visible gap, separate waistband, overlapping hem" in prompt
    assert "sleeveless collared, button-front, or tie-front dress" in prompt
    assert "cropped length or deep neckline does not turn a blazer" in prompt
    assert "surface area on the target garment only" in prompt
    assert "metallic gold, silver, bronze, or copper" in prompt


def testar_amostra_balanceada_e_deterministica():
    categorias = ["a", "b", "c", "d", "e", "f", "g", "h"]
    with tempfile.TemporaryDirectory() as temporaria:
        raiz = Path(temporaria)
        for categoria in categorias:
            pasta = raiz / categoria
            pasta.mkdir()
            for numero in range(50):
                (pasta / "{}.jpg".format(numero)).touch()
        a = MODULO.selecionar_imagens(raiz, categorias, 24, 7)
        b = MODULO.selecionar_imagens(raiz, categorias, 24, 7)
        assert a == b
        assert len(a) == 24
        assert {c: sum(cat == c for cat, _ in a) for c in categorias} == {
            c: 3 for c in categorias
        }

        calibracao = MODULO.selecionar_amostra_de_avaliacao(
            raiz, categorias, 24, 7)
        holdout = MODULO.selecionar_amostra_de_avaliacao(
            raiz, categorias, 300, 7)
        assert len(holdout) == 300
        assert not ({p for _, p in calibracao} & {p for _, p in holdout})


def analise_valida(**mudancas):
    analise = {
        "target_clarity": "clear",
        "garment_structure": "upper_shirt_construction",
        "pattern": "liso",
        "fabrics": [],
        "length": "not_visible",
        "silhouette": "not_visible",
        "waist": "not_visible",
        "aesthetics": [],
        "colors": ["branco_cru"],
        "additional_visual_attributes": ["shirt collar", "front placket"],
    }
    analise.update(mudancas)
    return analise


def testar_categoria_derivada_e_abstencao():
    taxonomia = MODULO.carregar_taxonomia(RAIZ / "anexos" / "taxonomia.csv")
    normalizada = MODULO.normalizar_analise(analise_valida(), taxonomia)
    assert normalizada["category"] == "camisa"
    assert "category" not in analise_valida()

    ambigua = analise_valida(
        target_clarity="ambiguous_target",
        garment_structure="target_not_determinable",
        pattern="not_visible",
        fabrics=[],
        length="not_visible",
        silhouette="not_visible",
        waist="not_visible",
        aesthetics=[],
        colors=[],
        additional_visual_attributes=[],
    )
    assert MODULO.normalizar_analise(ambigua, taxonomia)["category"] == "not_visible"

    invalida = dict(ambigua, colors=["preto"])
    try:
        MODULO.normalizar_analise(invalida, taxonomia)
    except MODULO.ErroDaOpenAI as erro:
        assert "listas vazias" in str(erro)
    else:
        raise AssertionError("Alvo ambiguo com cor deveria ser recusado")


def testar_extracao_e_custo():
    analise = analise_valida()
    resposta = {
        "status": "completed",
        "output": [{
            "type": "message",
            "content": [{"type": "output_text", "text": json.dumps(analise)}],
        }],
    }
    assert json.loads(MODULO.extrair_texto(resposta)) == analise
    custo = MODULO.custo_estimado({
        "input_tokens": 1000,
        "input_tokens_details": {"cached_tokens": 200},
        "output_tokens": 100,
    })
    assert abs(custo - 0.00142) < 1e-12
    custo_com_escrita = MODULO.custo_estimado({
        "input_tokens": 1000,
        "input_tokens_details": {
            "cached_tokens": 200,
            "cache_write_tokens": 300,
        },
        "output_tokens": 100,
    })
    assert abs(custo_com_escrita - 0.001495) < 1e-12


def testar_portao_pago_e_explicito():
    with tempfile.TemporaryDirectory() as temporaria:
        caminho = Path(temporaria) / "portao.json"
        try:
            MODULO.validar_portao_24(caminho)
        except ValueError as erro:
            assert "ausente" in str(erro)
        else:
            raise AssertionError("Benchmark abriu sem portao")

        caminho.write_text(json.dumps({
            "prompt_version": MODULO.VERSAO_DO_PROMPT,
            "sample_size": 24,
            "category_accuracy": 20 / 24,
            "primary_color_accuracy": 19 / 24,
            "passed": False,
        }))
        try:
            MODULO.validar_portao_24(caminho)
        except ValueError as erro:
            assert "80%" in str(erro)
        else:
            raise AssertionError("Benchmark abriu com cor abaixo do piso")

        caminho.write_text(json.dumps({
            "prompt_version": MODULO.VERSAO_DO_PROMPT,
            "sample_size": 24,
            "category_accuracy": 20 / 24,
            "primary_color_accuracy": 20 / 24,
            "passed": True,
        }))
        assert MODULO.validar_portao_24(caminho)["passed"] is True


def main():
    testes = [
        testar_taxonomia_e_schema,
        testar_amostra_balanceada_e_deterministica,
        testar_categoria_derivada_e_abstencao,
        testar_extracao_e_custo,
        testar_portao_pago_e_explicito,
    ]
    for teste in testes:
        teste()
    print("{} testes do avaliador Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
