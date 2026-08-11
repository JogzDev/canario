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
    assert schema["properties"]["category"]["enum"][0] == "not_visible"
    assert schema["properties"]["colors"]["items"]["enum"][-1] == "outras_cores"


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


def testar_extracao_e_custo():
    analise = {"category": "vestido", "colors": ["preto"]}
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
    assert abs(custo - 0.000284) < 1e-12


def main():
    testes = [
        testar_taxonomia_e_schema,
        testar_amostra_balanceada_e_deterministica,
        testar_extracao_e_custo,
    ]
    for teste in testes:
        teste()
    print("{} testes do avaliador Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
