"""Testa o recorte autocontido para adjudicar divergencias humanas."""

import base64
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "ferramentas"))
CAMINHO = RAIZ / "ferramentas" / "preparar_adjudicacao_luna.py"
SPEC = importlib.util.spec_from_file_location("preparar_adjudicacao_luna", CAMINHO)
MODULO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULO)
BATCH_ID = "a" * 64
IMAGE_SHA = hashlib.sha256(b"imagem").hexdigest()


def resposta(sample_id, categoria):
    return {
        "sample_id": sample_id,
        "imagem": "{}.jpg".format(sample_id),
        "image_sha256": IMAGE_SHA,
        "target_clarity": "clear",
        "category": categoria,
        "structure": "upper_shirt_construction" if categoria == "camisa" else "upper_other",
        "primary_color": "azul",
        "secondary_colors": [],
        "notes": "",
        "reviewed_at": "2026-08-11T00:00:00Z",
    }


def main():
    imagem = "data:image/jpeg;base64," + base64.b64encode(b"imagem").decode("ascii")
    amostras = [
        {"sample_id": "S01", "imagem": "S01.jpg",
         "image_sha256": IMAGE_SHA, "image": imagem},
        {"sample_id": "S02", "imagem": "S02.jpg",
         "image_sha256": IMAGE_SHA, "image": imagem},
    ]
    html = (RAIZ / "ferramentas" / "revisao_luna.html").read_text(encoding="utf-8")
    html = html.replace("__CANARIO_SAMPLES_JSON__", json.dumps(amostras))
    html = html.replace("__CANARIO_BATCH_ID_JSON__", json.dumps(BATCH_ID))
    revisoes = [
        {"reviewer": "A", "batch_id": BATCH_ID,
         "rubric_version": "categoria-cor-v2",
         "answers": {"S01": resposta("S01", "camisa"), "S02": resposta("S02", "camisa")}},
        {"reviewer": "B", "batch_id": BATCH_ID,
         "rubric_version": "categoria-cor-v2",
         "answers": {"S01": resposta("S01", "camisa"), "S02": resposta("S02", "blusa_top")}},
    ]
    with tempfile.TemporaryDirectory() as temporaria:
        pasta = Path(temporaria)
        origem = pasta / "revisao.html"
        saida = pasta / "adjudicacao.html"
        origem.write_text(html, encoding="utf-8")
        _, selecionadas = MODULO.preparar(revisoes, origem, saida)
        gerado = saida.read_text(encoding="utf-8")
        embutidas = json.loads(MODULO.PADRAO_AMOSTRAS.search(gerado).group(1))
        assert [a["sample_id"] for a in selecionadas] == ["S02"]
        assert [a["sample_id"] for a in embutidas] == ["S02"]
        assert embutidas[0]["image"].startswith("data:image/jpeg;base64,")
        assert 'const reviewMode = "adjudication"' in gerado
        assert "Adjudicação cega" in gerado
        assert "Fadul" not in gerado and "Bianca" not in gerado

        for campo, valor in (
                ("imagem", "outra.jpg"), ("image_sha256", "f" * 64),
                ("image", "data:image/jpeg;base64,b3V0cmE=")):
            adulteradas = copy.deepcopy(amostras)
            adulteradas[1][campo] = valor
            adulterado = MODULO.PADRAO_AMOSTRAS.sub(
                lambda _: "const samples = {};\n".format(json.dumps(adulteradas)), html)
            origem.write_text(adulterado, encoding="utf-8")
            invalida = pasta / ("invalida-" + campo + ".html")
            try:
                MODULO.preparar(revisoes, origem, invalida)
            except ValueError:
                pass
            else:
                raise AssertionError("Adjudicacao aceitou imagem adulterada: " + campo)
            assert not invalida.exists()
        origem.write_text(html, encoding="utf-8")

        sem_divergencia = [revisoes[0], {
            "reviewer": "C", "batch_id": BATCH_ID,
            "rubric_version": "categoria-cor-v2",
            "answers": {
                "S01": resposta("S01", "camisa"),
                "S02": resposta("S02", "camisa"),
            },
        }]
        nao_criar = pasta / "nao-criar.html"
        _, vazias = MODULO.preparar(sem_divergencia, origem, nao_criar)
        assert vazias == []
        assert not nao_criar.exists()
    print("Adjudicacao: somente divergencias, imagem embutida, 0 falhas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
