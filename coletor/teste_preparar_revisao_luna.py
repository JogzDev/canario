"""Testa o pacote cego de revisão sem rede e sem OpenAI."""

import csv
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
CAMINHO = RAIZ / "ferramentas" / "preparar_revisao_luna.py"
sys.path.insert(0, str(RAIZ / "ferramentas"))
SPEC = importlib.util.spec_from_file_location("preparar_revisao_luna", CAMINHO)
MODULO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULO)
CATEGORIAS = [
    "vestido", "saia", "blusa_top", "camisa", "calca", "short",
    "casaco_jaqueta", "macacao",
]


def criar_cache_e_log(raiz):
    cache = raiz / "cache"
    logs = raiz / "logs"
    logs.mkdir()
    linhas = []
    ordem = 0
    for categoria in CATEGORIAS:
        pasta = cache / categoria
        pasta.mkdir(parents=True)
        for numero in range(3):
            imagem = pasta / "orig-{}-{}.jpg".format(
                CATEGORIAS.index(categoria), numero)
            imagem.write_bytes(b"jpeg-falso-" + categoria.encode("ascii"))
    taxonomia = MODULO.carregar_taxonomia(RAIZ / "anexos" / "taxonomia.csv")
    amostra = MODULO.selecionar_amostra_de_avaliacao(
        cache, MODULO.ids(taxonomia, "categoria"), 24, 7)
    for categoria, imagem in amostra:
        ordem += 1
        prevista = "blusa_top" if ordem == 1 else categoria
        estado = "OK" if prevista == categoria else "DIVERGIU"
        linhas.append(
            "[{} / 24] ignorar".format(ordem))
        linhas.append(
            "[{}/24] catalogo={} Luna={} {} | 3.0s | in=1 out=1 | {}".format(
                ordem, categoria, prevista, estado, imagem.name))
    (logs / "job.txt").write_text("\n".join(linhas), encoding="utf-8")
    return cache, logs


def testar_parser_e_pacote_cego():
    with tempfile.TemporaryDirectory() as temporaria:
        raiz = Path(temporaria)
        cache, logs = criar_cache_e_log(raiz)
        saida = raiz / "saida"
        amostra, recuperadas = MODULO.preparar(
            cache,
            RAIZ / "anexos" / "taxonomia.csv",
            logs,
            RAIZ / "ferramentas" / "revisao_luna.html",
            saida,
            24,
            7,
            "123",
        )
        assert len(amostra) == 24
        assert len(recuperadas) == 24
        assert sum(not item["concordou"] for item in recuperadas) == 1
        assert len(list((saida / "images").glob("*.jpg"))) == 24
        html = (saida / "revisao.html").read_text(encoding="utf-8")
        assert "__CANARIO_SAMPLES_JSON__" not in html
        assert "categoria_catalogo" not in html
        assert "categoria_luna" not in html
        assert html.count("data:image/jpeg;base64,") == 24
        assert '"image":"images/' not in html
        for item in recuperadas:
            assert item["imagem_original"] not in html
        scripts = re.findall(r"<script>(.*?)</script>", html, flags=re.DOTALL)
        assert len(scripts) == 1
        javascript = raiz / "revisao-gerada.js"
        javascript.write_text(scripts[0], encoding="utf-8")
        # `node` confere a sintaxe do JS embutido. Ele nao existe no runner do
        # i7 e nao e dependencia do produto: o app nao roda JavaScript e a
        # pagina de revisao e ferramenta interna. Ausencia vira aviso alto, nao
        # falha -- teste vermelho por falta de ferramenta ensina a ignorar
        # vermelho. Onde `node` existe, a conferencia continua obrigatoria.
        try:
            sintaxe = subprocess.run(
                ["node", "--check", str(javascript)],
                capture_output=True,
                text=True,
            )
        except FileNotFoundError:
            print("AVISO: `node` ausente; sintaxe do JS da revisao nao conferida.")
        else:
            assert sintaxe.returncode == 0, sintaxe.stderr
        manifesto = json.loads((saida / "amostra-cega.json").read_text())
        assert manifesto["rubric_version"] == MODULO.VERSAO_RUBRICA
        assert manifesto["quantity"] == 24
        assert all(
            item["image"].startswith("images/")
            for item in manifesto["samples"]
        )
        with open(saida / "predicoes-recuperadas.csv", encoding="utf-8") as arquivo:
            linhas = list(csv.DictReader(arquivo))
        assert len(linhas) == 24
        assert {linha["sample_id"] for linha in linhas} == {
            "S{:02d}".format(i) for i in range(1, 25)
        }


def testar_template_tem_contrato_de_exportacao():
    html = (RAIZ / "ferramentas" / "revisao_luna.html").read_text(encoding="utf-8")
    exigencias = [
        "categoria-cor-v2", "target_clarity", "primary_color",
        "secondary_colors", "structure", "localStorage", "Exportar gabarito cego",
        "predicoes-recuperadas.csv", "categoryByStructure",
        "answer.category = categoryByStructure[answer.structure]",
        "Estrutura visual observada — escolha primeiro",
        "Categoria humana — calculada automaticamente",
        "Preenchida automaticamente pela estrutura escolhida",
    ]
    for trecho in exigencias:
        assert trecho in html, trecho


def testar_workflow_aceita_holdout_de_300():
    workflow = (RAIZ / ".github" / "workflows" / "revisar-luna.yml").read_text()
    assert "options: ['24', '300']" in workflow
    fonte = CAMINHO.read_text()
    assert "selecionar_amostra_de_avaliacao" in fonte


def main():
    testes = [
        testar_parser_e_pacote_cego,
        testar_template_tem_contrato_de_exportacao,
        testar_workflow_aceita_holdout_de_300,
    ]
    for teste in testes:
        teste()
    print("{} testes do pacote de revisao Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
