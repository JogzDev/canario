"""Testa o recorte autocontido para adjudicar divergencias humanas."""

import base64
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


def resposta(sample_id, categoria):
    return {
        "sample_id": sample_id,
        "target_clarity": "clear",
        "category": categoria,
        "structure": "upper_shirt_construction" if categoria == "camisa" else "upper_other",
        "primary_color": "azul",
        "secondary_colors": [],
    }


def main():
    imagem = "data:image/jpeg;base64," + base64.b64encode(b"imagem").decode("ascii")
    amostras = [
        {"sample_id": "S01", "image": imagem},
        {"sample_id": "S02", "image": imagem},
    ]
    html = (RAIZ / "ferramentas" / "revisao_luna.html").read_text(encoding="utf-8")
    html = html.replace("__CANARIO_SAMPLES_JSON__", json.dumps(amostras))
    revisoes = [
        {"reviewer": "A", "rubric_version": "categoria-cor-v2",
         "answers": {"S01": resposta("S01", "camisa"), "S02": resposta("S02", "camisa")}},
        {"reviewer": "B", "rubric_version": "categoria-cor-v2",
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
        assert "canario-luna-adjudicacao:" in gerado
        assert "Adjudicação cega" in gerado
    print("Adjudicacao: somente divergencias, imagem embutida, 0 falhas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
