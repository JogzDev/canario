"""Testa o pacote cego de revisão sem rede e sem OpenAI."""

import csv
import importlib.util
import json
from pathlib import Path
import re
import shutil
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
        assert "__CANARIO_BATCH_ID_JSON__" not in html
        assert "categoria_catalogo" not in html
        assert "categoria_luna" not in html
        assert html.count("data:image/jpeg;base64,") == 24
        assert '"image":"images/' not in html
        assert "imagem: sample.imagem" in html
        assert "image_sha256: sample.image_sha256" in html
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
        assert manifesto["contract"] == MODULO.CONTRATO_LOTE
        assert re.fullmatch(r"[0-9a-f]{64}", manifesto["batch_id"])
        assert manifesto["rubric_version"] == MODULO.VERSAO_RUBRICA
        assert manifesto["quantity"] == 24
        assert all(
            item["image"].startswith("images/")
            for item in manifesto["samples"]
        )
        assert all(re.fullmatch(r"[0-9a-f]{64}", item["image_sha256"])
                   for item in manifesto["samples"])
        assert {item["imagem"] for item in manifesto["samples"]} == {
            item["imagem_original"] for item in recuperadas
        }
        assert 'const batchId = "{}"'.format(manifesto["batch_id"]) in html
        assert "${batchId}:${reviewMode}:${rubricVersion}" in html
        with open(saida / "predicoes-recuperadas.csv", encoding="utf-8") as arquivo:
            linhas = list(csv.DictReader(arquivo))
        assert len(linhas) == 24
        assert {linha["batch_id"] for linha in linhas} == {manifesto["batch_id"]}
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
        "canario_luna_review_submission_v1", "__CANARIO_BATCH_ID_JSON__",
        "imagem: sample.imagem", "image_sha256: sample.image_sha256",
    ]
    for trecho in exigencias:
        assert trecho in html, trecho


def testar_workflow_aceita_holdout_de_300():
    workflow = (RAIZ / ".github" / "workflows" / "revisar-luna.yml").read_text()
    assert "options: ['24', '300']" in workflow
    fonte = CAMINHO.read_text()
    assert "selecionar_amostra_de_avaliacao" in fonte


def testar_falha_nao_deixa_diretorio_parcial():
    with tempfile.TemporaryDirectory() as temporaria:
        raiz = Path(temporaria)
        cache, logs = criar_cache_e_log(raiz)
        saida = raiz / "saida"
        original = MODULO._imagem_embutida

        def falhar(_):
            raise RuntimeError("falha injetada")

        MODULO._imagem_embutida = falhar
        try:
            try:
                MODULO.preparar(
                    cache, RAIZ / "anexos" / "taxonomia.csv", logs,
                    RAIZ / "ferramentas" / "revisao_luna.html", saida,
                    24, 7, "123",
                )
            except RuntimeError as erro:
                assert "injetada" in str(erro)
            else:
                raise AssertionError("falha injetada deveria interromper o preparo")
        finally:
            MODULO._imagem_embutida = original
        assert not saida.exists()
        assert not list(raiz.glob("saida.*.tmp"))


def testar_json_embutido_preserva_dados_sem_abrir_marcacao():
    dados = [{"imagem": "</script><script>alert(1)</script>&\u2028\u2029.jpg"}]
    embutido = MODULO._json_para_script(dados)
    assert "<" not in embutido and ">" not in embutido and "&" not in embutido
    assert "\u2028" not in embutido and "\u2029" not in embutido
    assert json.loads(embutido) == dados


def testar_imagem_alterada_durante_preparo_nao_publica_lote():
    with tempfile.TemporaryDirectory() as temporaria:
        raiz = Path(temporaria)
        cache, logs = criar_cache_e_log(raiz)
        saida = raiz / "saida"
        copiar = MODULO.shutil.copy2

        def trocar_conteudo(origem, destino):
            copiar(origem, destino)
            destino.write_bytes(b"conteudo-diferente-do-hash")

        MODULO.shutil.copy2 = trocar_conteudo
        try:
            try:
                MODULO.preparar(
                    cache, RAIZ / "anexos" / "taxonomia.csv", logs,
                    RAIZ / "ferramentas" / "revisao_luna.html", saida,
                    24, 7, "123")
            except ValueError as erro:
                assert "Imagem mudou" in str(erro)
            else:
                raise AssertionError("lote com imagem trocada foi publicado")
        finally:
            MODULO.shutil.copy2 = copiar
        assert not saida.exists()
        assert not list(raiz.glob("saida.*.tmp"))


def testar_export_real_javascript_preserva_contrato_e_identidade():
    """Executa as funcoes de export em Node com DOM minimo, sem navegador/rede."""
    node = shutil.which("node")
    if not node:
        print("AVISO: `node` ausente; contrato JS do export nao executado.")
        return
    html = (RAIZ / "ferramentas" / "revisao_luna.html").read_text(encoding="utf-8")
    sample = {"sample_id": "S01", "imagem": "original.jpg",
              "image_sha256": "a" * 64, "image": "data:image/jpeg;base64,YQ=="}
    script = re.search(r"<script>(.*?)</script>", html, re.DOTALL).group(1)
    script = script.replace("__CANARIO_SAMPLES_JSON__", MODULO._json_para_script([sample]))
    script = script.replace("__CANARIO_BATCH_ID_JSON__", json.dumps("b" * 64))
    script = script.replace("  loadReviewer(reviewer);", """
  globalThis.hooks = { normalizeAnswer, isComplete, exportAnswers, writeStorage,
    setDraft(value) { reviewer = "R1"; answers = { S01: value }; } };
""")
    harness = r"""
const blobs = [];
const elements = new Map();
globalThis.document = {
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, { value: "", addEventListener() {}, focus() {},
      querySelector() { return null; }, querySelectorAll() { return []; } });
    return elements.get(id);
  },
  addEventListener() {}, body: { appendChild() {} },
  createElement() { return { click() {}, remove() {} }; }
};
globalThis.localStorage = {
  getItem() { throw new Error("storage blocked"); },
  setItem() { throw new Error("quota"); }
};
globalThis.Blob = class { constructor(parts) { blobs.push(parts.join("")); } };
globalThis.URL = { createObjectURL() { return "blob:unit-test"; }, revokeObjectURL() {} };
globalThis.setTimeout = () => {};
globalThis.alert = message => { throw new Error(message); };
"""
    assertions = r"""
const assert = require("node:assert/strict");
for (const corrupt of [null, [], false, "text", 5]) {
  assert.equal(hooks.isComplete(hooks.normalizeAnswer(corrupt)), false);
}
const answer = {
  sample_id: "S99", imagem: "wrong.jpg", image_sha256: "f".repeat(64), surprise: true,
  target_clarity: "clear", category: "camisa", structure: "upper_shirt_construction",
  primary_color: "azul", secondary_colors: [], notes: "nota, com aspas \"ok\"",
  reviewed_at: "2026-08-11T00:00:00Z"
};
assert.equal(hooks.isComplete(hooks.normalizeAnswer(answer)), true);
assert.equal(hooks.isComplete({ ...answer, secondary_colors: ["preto", "preto"] }), false);
assert.equal(hooks.isComplete({ ...answer, reviewed_at: "sem-data" }), false);
assert.equal(hooks.isComplete({ ...answer, primary_color: "invalida" }), false);
assert.equal(hooks.isComplete({ ...answer, target_clarity: "ambiguous_target" }), false);
hooks.writeStorage("test", "value");
hooks.setDraft(answer);
elements.get("clarity").querySelector = () => ({ value: "clear" });
elements.get("structure").value = "upper_shirt_construction";
elements.get("primary-color").value = "azul";
elements.get("notes").value = answer.notes;
hooks.exportAnswers();
assert.equal(blobs.length, 2);
const payload = JSON.parse(blobs[0]);
assert.equal(payload.answers[0].sample_id, "S01");
assert.equal(payload.answers[0].imagem, "original.jpg");
assert.equal(payload.answers[0].image_sha256, "a".repeat(64));
assert.equal(Object.hasOwn(payload.answers[0], "surprise"), false);
assert.match(elements.get("save-state").textContent, /apenas nesta sess/);
process.stdout.write(JSON.stringify(blobs));
"""
    resultado = subprocess.run([node, "-e", harness + script + assertions],
                               text=True, capture_output=True)
    assert resultado.returncode == 0, resultado.stderr
    from consolidar_revisao_luna import carregar_revisao
    with tempfile.TemporaryDirectory() as temporaria:
        pasta = Path(temporaria)
        json_exportado, csv_exportado = json.loads(resultado.stdout)
        (pasta / "r1.json").write_text(json_exportado, encoding="utf-8")
        (pasta / "r1.csv").write_text(csv_exportado, encoding="utf-8")
        assert carregar_revisao(pasta / "r1.json") == carregar_revisao(pasta / "r1.csv")


def main():
    testes = [
        testar_parser_e_pacote_cego,
        testar_template_tem_contrato_de_exportacao,
        testar_workflow_aceita_holdout_de_300,
        testar_falha_nao_deixa_diretorio_parcial,
        testar_json_embutido_preserva_dados_sem_abrir_marcacao,
        testar_imagem_alterada_durante_preparo_nao_publica_lote,
        testar_export_real_javascript_preserva_contrato_e_identidade,
    ]
    for teste in testes:
        teste()
    print("{} testes do pacote de revisao Luna, 0 falhas".format(len(testes)))


if __name__ == "__main__":
    main()
