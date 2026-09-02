#!/usr/bin/env python3
"""Regressões do contrato humano dos fatos privados da Etiqueta."""

import copy
import datetime as dt
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "ferramentas"))


def carregar_modulo(nome, caminho):
    spec = importlib.util.spec_from_file_location(nome, caminho)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


materializador = carregar_modulo(
    "materializador_revisao_etiqueta",
    RAIZ / "ferramentas" / "materializar_etiqueta_radar.py")
preparador = carregar_modulo(
    "preparador_revisao_etiqueta",
    RAIZ / "ferramentas" / "preparar_revisao_etiqueta_radar.py")
consolidador = carregar_modulo(
    "consolidador_revisao_etiqueta",
    RAIZ / "ferramentas" / "consolidar_revisao_etiqueta_radar.py")

CORTE = dt.date(2026, 9, 1)
GERADO = dt.datetime(2026, 9, 1, 18, 0, tzinfo=dt.timezone.utc)
AGORA = dt.datetime(2026, 9, 2, 12, 0, tzinfo=dt.timezone.utc)


def linha(produto_id, marca_id, composicao):
    return {
        "produto_id": produto_id,
        "marca_id": marca_id,
        "segmento": materializador.SEGMENTO,
        "ofertavel": True,
        "ultimo_avistamento_em": CORTE.isoformat(),
        "snapshot_data": CORTE.isoformat(),
        "composicao": composicao,
    }


def pacote_real():
    contrato = materializador.carregar_contrato_da_fonte(
        RAIZ / "anexos" / "fontes_radar.csv", CORTE)
    return materializador.materializar([
        linha(101, 10, "80% algodão, 20% poliéster em malha"),
        linha(102, 10, "100% algodão em sarja estonada"),
        linha(103, 11, "95% viscose, 5% elastano em tricô"),
        linha(104, 12, "100% algodão em sarja estonada"),
    ], CORTE, contrato, gerado_em=GERADO)


def submissao(lote, alias, escolhas=None):
    escolhas = escolhas or {}
    decisoes = []
    for sujeito in lote["subjects"]:
        escolha = escolhas.get(sujeito["subject_id"], "supported_candidate")
        if escolha == "supported_candidate":
            motivo, nota = None, ""
        elif escolha == "rejected_candidate":
            motivo, nota = "not_supported_by_excerpt", ""
        else:
            motivo, nota = "excerpt_ambiguous", ""
        decisoes.append({
            "subject_id": sujeito["subject_id"],
            "decision": escolha,
            "reason_code": motivo,
            "note": nota,
            "reviewed_at": "2026-09-01T18:30:00Z",
        })
    return {
        "contract": lote["submission_contract"],
        "batch_id": lote["batch_id"],
        "source_package_id": lote["source_package_id"],
        "rubric_version": lote["rubric"]["version"],
        "rubric_sha256": lote["rubric_sha256"],
        "reviewer_alias": alias,
        "state": "submitted",
        "submitted_at": "2026-09-01T19:00:00Z",
        "decisions": decisoes,
    }


class PreparacaoTests(unittest.TestCase):
    def setUp(self):
        self.pacote = pacote_real()
        self.lote = preparador.preparar_fila(self.pacote)

    def test_lote_e_deterministico_vinculado_e_realmente_cego(self):
        segundo = preparador.preparar_fila(copy.deepcopy(self.pacote))
        self.assertEqual(self.lote, segundo)
        self.assertEqual(
            self.lote["contract"], "datadrobe_fact_review_batch_v1")
        self.assertRegex(self.lote["batch_id"], r"^[0-9a-f]{64}$")
        self.assertEqual(
            self.lote["source_package_id"], self.pacote["package_id"])
        total_fatos = sum(len(item["facts"]) for item in self.pacote["items"])
        self.assertNotIn("candidate_fact_count", self.lote)
        self.assertLess(self.lote["subject_count"], total_fatos)
        for sujeito in self.lote["subjects"]:
            self.assertEqual(set(sujeito), {
                "subject_id", "family", "facet_id", "candidate_concept_id",
                "value", "source_excerpt",
            })
        serializado = json.dumps(self.lote["subjects"], ensure_ascii=False)
        for segredo in (
                '"product_id"', '"brand_id"', '"parser_confidence"',
                '"aggregates"', '"warnings"', '"observed_on"'):
            self.assertNotIn(segredo, serializado)

    def test_pacote_adulterado_em_fato_ou_agregado_e_rejeitado(self):
        fato = copy.deepcopy(self.pacote)
        fato["items"][0]["facts"][0]["value"] = {"percentage": 99.0}
        agregado = copy.deepcopy(self.pacote)
        agregado["aggregates"][0]["product_count"] += 1
        identidade = copy.deepcopy(self.pacote)
        identidade["package_id"] = "0" * 64
        governanca = copy.deepcopy(self.pacote)
        governanca["authorization_sha256"] = "0" * 64
        campos = copy.deepcopy(self.pacote)
        campos["surpresa"] = True
        derivado = copy.deepcopy(self.pacote)
        item = derivado["items"][0]
        candidato = item["facts"][0]
        id_antigo = candidato["id"]
        candidato["value"] = {"percentage": 77, "part_id": "principal"}
        candidato["id"] = preparador._id_fato(
            item["source_item_external_id"], candidato,
            derivado["parser_version"])
        for resumo in derivado["aggregates"]:
            resumo["supporting_fact_ids"] = sorted(
                candidato["id"] if fato_id == id_antigo else fato_id
                for fato_id in resumo["supporting_fact_ids"])
        payload = {chave: derivado[chave] for chave in (
            "population", "items", "aggregates")}
        derivado["payload_sha256"] = preparador._sha256(
            preparador._json_canonico(payload))
        # Mesmo com IDs derivados e payload internamente coerentes, o package_id
        # registrado no resumo imutável do Actions deixa de corresponder.
        self.assertEqual(derivado["package_id"], self.pacote["package_id"])
        for adulterado in (
                fato, agregado, identidade, governanca, campos, derivado):
            with self.subTest(chaves=adulterado.keys()), self.assertRaises(
                    preparador.ErroDePreparacao):
                preparador.preparar_fila(adulterado)

    def test_html_neutraliza_fechamento_de_script_e_javascript_e_offline(self):
        perigoso = preparador._json_seguro_para_script({
            "x": "</script><script>globalThis.pwned=true</script>&\u2028"})
        self.assertNotIn("</script>", perigoso)
        self.assertNotIn("<script>", perigoso)
        self.assertNotIn("&", perigoso)
        with tempfile.TemporaryDirectory() as pasta:
            html = preparador.renderizar_html(
                self.lote,
                RAIZ / "ferramentas" / "revisao_etiqueta_radar.html")
            self.assertNotIn(preparador.MARCADOR_HTML, html)
            self.assertNotRegex(html, r"https?://")
            scripts = re.findall(
                r"<script>(.*?)</script>", html, flags=re.DOTALL)
            self.assertEqual(len(scripts), 1)
            caminho = Path(pasta) / "revisao.js"
            caminho.write_text(scripts[0], encoding="utf-8")
            node_bin = shutil.which("node")
            if node_bin is None:
                self.skipTest("node indisponível")
            node = subprocess.run(
                [node_bin, "--check", str(caminho)], capture_output=True,
                text=True, check=False)
            self.assertEqual(node.returncode, 0, node.stderr)

    def test_lote_vazio_e_legivel_e_escala_impraticavel_falha_fechada(self):
        contrato = materializador.carregar_contrato_da_fonte(
            RAIZ / "anexos" / "fontes_radar.csv", CORTE)
        vazio = materializador.materializar(
            [], CORTE, contrato, gerado_em=GERADO)
        lote_vazio = preparador.preparar_fila(vazio)
        self.assertNotIn("candidate_fact_count", lote_vazio)
        self.assertEqual(lote_vazio["subject_count"], 0)
        html = preparador.renderizar_html(
            lote_vazio,
            RAIZ / "ferramentas" / "revisao_etiqueta_radar.html")
        self.assertIn("não contém fatos candidatos", html)

        origem = preparador.validar_pacote(self.pacote)
        base = origem["facts"][0]
        origem["facts"] = []
        for indice in range(preparador.MAXIMO_SUJEITOS_POR_LOTE + 1):
            copia = copy.deepcopy(base)
            copia["fact_id"] = "{:064x}".format(indice + 1)
            copia["subject"]["subject_id"] = "{:064x}".format(indice + 1)
            origem["facts"].append(copia)
        with self.assertRaises(preparador.ErroDePreparacao):
            preparador._preparar_fila_validada(origem)

    def test_storage_offline_tem_fallback_e_saidas_privadas_sao_ignoradas(self):
        html = (RAIZ / "ferramentas" /
                "revisao_etiqueta_radar.html").read_text(encoding="utf-8")
        self.assertIn("function storageGet", html)
        self.assertIn("function storageSet", html)
        self.assertIn("function storageRemove", html)
        self.assertIn("Rascunho apenas nesta sessão", html)
        self.assertEqual(html.count("window.localStorage"), 3)
        nomes = [
            "etiqueta-0123456789ab-R1.json",
            "radar-etiqueta-revisao.html",
            "radar-etiqueta-reviewed.json",
            "radar-etiqueta-reviewed-final.json",
            "radar-etiqueta-reviewed-adjudicacao.html",
        ]
        ignorados = subprocess.run(
            ["git", "check-ignore", "--stdin"], cwd=RAIZ,
            input="\n".join(nomes) + "\n", capture_output=True,
            text=True, check=False)
        self.assertEqual(ignorados.returncode, 0, ignorados.stderr)
        self.assertEqual(set(ignorados.stdout.splitlines()), set(nomes))

    def test_controlador_html_exporta_submissoes_validas_com_storage_adverso(self):
        node_bin = shutil.which("node")
        if node_bin is None:
            self.skipTest("node indisponível")
        html = preparador.renderizar_html(
            self.lote, RAIZ / "ferramentas" / "revisao_etiqueta_radar.html")
        script, = re.findall(r"<script>(.*?)</script>", html, flags=re.DOTALL)
        processo = subprocess.run(
            [node_bin, str(RAIZ / "coletor" / "teste_revisao_etiqueta_ui.js")],
            input=json.dumps({"script": script, "batch": self.lote}),
            text=True, capture_output=True, check=False)
        self.assertEqual(processo.returncode, 0, processo.stderr)
        exportados = json.loads(processo.stdout)["exported"]
        self.assertEqual(len(exportados), 4)
        for exportado in exportados:
            validado = consolidador.validar_submissao(exportado, self.lote)
            self.assertEqual(len(validado["decisions"]), self.lote["subject_count"])
        primeira = exportados[0]
        segunda = copy.deepcopy(primeira)
        segunda["reviewer_alias"] = "R2"
        resultado, adjudicacao = consolidador.consolidar(
            self.pacote, [primeira, segunda])
        self.assertIsNone(adjudicacao)
        self.assertEqual(resultado["counts"]["confirmed_candidate"],
                         sum(len(item["facts"]) for item in self.pacote["items"]))


class ConsolidacaoTests(unittest.TestCase):
    def setUp(self):
        self.pacote = pacote_real()
        self.lote = preparador.preparar_fila(self.pacote)

    def test_consenso_recalcula_so_confirmados_sem_promover(self):
        alvo = self.lote["subjects"][0]["subject_id"]
        escolhas = {alvo: "rejected_candidate"}
        revisoes = [submissao(self.lote, "R1", escolhas),
                    submissao(self.lote, "R2", escolhas)]
        resultado, adjudicacao = consolidador.consolidar(
            self.pacote,
            revisoes,
            agora=AGORA,
        )
        invertido, _ = consolidador.consolidar(
            self.pacote, list(reversed(revisoes)), agora=AGORA)
        self.assertEqual(resultado, invertido)
        self.assertIsNone(adjudicacao)
        self.assertEqual(
            resultado["contract"],
            "datadrobe_label_reviewed_fact_pack_v1")
        fatos_do_alvo = [
            fato for fato in preparador.validar_pacote(self.pacote)["facts"]
            if fato["subject"]["subject_id"] == alvo
        ]
        self.assertEqual(
            resultado["counts"]["rejected_candidate"], len(fatos_do_alvo))
        self.assertEqual(
            resultado["counts"]["confirmed_candidate"],
            sum(len(item["facts"]) for item in self.pacote["items"]) - len(fatos_do_alvo))
        ids_rejeitados = {fato["fact_id"] for fato in fatos_do_alvo}
        for agregado in resultado["reviewed_aggregates"]:
            self.assertTrue(ids_rejeitados.isdisjoint(
                agregado["supporting_fact_ids"]))
        serializado = json.dumps(resultado, ensure_ascii=False)
        for proibido in ('"approved"', '"published"', '"evidence_status"'):
            self.assertNotIn(proibido, serializado)
        self.assertFalse(resultado["evidence_staging_allowed"])
        self.assertTrue(resultado["requires_concept_review"])
        for campo in (
                "reviewed_package_id", "counts_sha256",
                "reviewed_subjects_sha256", "reviewed_facts_sha256",
                "reviewed_aggregates_sha256"):
            self.assertRegex(resultado[campo], r"^[0-9a-f]{64}$")
        self.assertTrue(all(set(fato) == {
            "fact_id", "review_subject_id"
        } for fato in resultado["reviewed_facts"]))

    def test_divergencia_gera_lote_minimo_e_terceiro_independente_fecha(self):
        alvo = self.lote["subjects"][0]["subject_id"]
        primeira = submissao(self.lote, "R1")
        segunda = submissao(
            self.lote, "R2", {alvo: "rejected_candidate"})
        comparacao, lote_adjudicacao = consolidador.consolidar(
            self.pacote, [primeira, segunda], agora=AGORA)
        self.assertEqual(
            comparacao["state"], "needs_independent_adjudication")
        self.assertRegex(comparacao["comparison_id"], r"^[0-9a-f]{64}$")
        self.assertEqual(lote_adjudicacao["subject_count"], 1)
        self.assertEqual(
            lote_adjudicacao["subjects"][0]["subject_id"], alvo)
        serializado = json.dumps(lote_adjudicacao, ensure_ascii=False)
        self.assertNotIn("R1", serializado)
        self.assertNotIn("R2", serializado)
        self.assertNotIn("rejected_candidate", json.dumps(
            lote_adjudicacao["subjects"], ensure_ascii=False))

        voto = submissao(lote_adjudicacao, "A1")
        resultado, pendencia = consolidador.consolidar(
            self.pacote, [primeira, segunda], voto, agora=AGORA)
        self.assertIsNone(pendencia)
        final = next(
            sujeito for sujeito in resultado["reviewed_subjects"]
            if sujeito["subject_id"] == alvo)
        self.assertEqual(final["review_state"], "confirmed_candidate")
        self.assertEqual(final["decision_basis"], "independent_adjudication")
        self.assertEqual(resultado["adjudicator_alias"], "A1")

    def test_rejeita_campos_extras_ordem_incompleta_e_identidade_repetida(self):
        primeira = submissao(self.lote, "R1")
        segunda = submissao(self.lote, "R2")
        extra = copy.deepcopy(primeira)
        extra["surpresa"] = True
        incompleta = copy.deepcopy(primeira)
        incompleta["decisions"].pop()
        invertida = copy.deepcopy(primeira)
        invertida["decisions"].reverse()
        for invalida in (extra, incompleta, invertida):
            with self.subTest(caso=invalida.keys()), self.assertRaises(
                    consolidador.ErroDeConsolidacao):
                consolidador.validar_submissao(
                    invalida, self.lote, agora=AGORA)
        repetida = copy.deepcopy(segunda)
        repetida["reviewer_alias"] = "r1"
        with self.assertRaises(consolidador.ErroDeConsolidacao):
            consolidador.consolidar(
                self.pacote, [primeira, repetida], agora=AGORA)

    def test_rejeita_enum_motivo_nota_e_tempo_incoerentes(self):
        casos = []
        enum = submissao(self.lote, "R1")
        enum["decisions"][0]["decision"] = "maybe"
        casos.append(enum)
        for campo in ("decision", "reason_code"):
            invalida = submissao(self.lote, "R1")
            invalida["decisions"][0][campo] = []
            casos.append(invalida)
        motivo = submissao(self.lote, "R1")
        motivo["decisions"][0]["reason_code"] = "wrong_value"
        casos.append(motivo)
        nota = submissao(self.lote, "R1", {
            self.lote["subjects"][0]["subject_id"]: "rejected_candidate"})
        nota["decisions"][0]["reason_code"] = "other"
        casos.append(nota)
        tempo = submissao(self.lote, "R1")
        tempo["decisions"][0]["reviewed_at"] = "2026-09-01T20:00:00Z"
        casos.append(tempo)
        for invalida in casos:
            with self.subTest(decisao=invalida["decisions"][0]), \
                    self.assertRaises(consolidador.ErroDeConsolidacao):
                consolidador.validar_submissao(
                    invalida, self.lote, agora=AGORA)

    def test_timestamps_sao_normalizados_antes_do_maximo(self):
        revisao = submissao(self.lote, "R1")
        revisao["submitted_at"] = "2026-09-01T16:00:00-03:00"
        for decisao in revisao["decisions"]:
            decisao["reviewed_at"] = "2026-09-01T15:30:00-03:00"
        validada = consolidador.validar_submissao(
            revisao, self.lote, agora=AGORA)
        self.assertEqual(validada["submitted_at"], "2026-09-01T19:00:00+00:00")
        self.assertTrue(all(
            decisao["reviewed_at"] == "2026-09-01T18:30:00+00:00"
            for decisao in validada["decisions"].values()))

    def test_cli_nomeia_adjudicacao_automaticamente(self):
        alvo = self.lote["subjects"][0]["subject_id"]
        primeira = submissao(self.lote, "R1")
        segunda = submissao(
            self.lote, "R2", {alvo: "rejected_candidate"})
        agora = dt.datetime.now(dt.timezone.utc)
        revisado = (agora - dt.timedelta(minutes=10)).isoformat()
        enviado = (agora - dt.timedelta(minutes=5)).isoformat()
        for revisao in (primeira, segunda):
            revisao["submitted_at"] = enviado
            for decisao in revisao["decisions"]:
                decisao["reviewed_at"] = revisado
        with tempfile.TemporaryDirectory() as pasta:
            pasta = Path(pasta)
            caminhos = [pasta / "r1.json", pasta / "r2.json"]
            pacote_path = pasta / "facts.json"
            saida = pasta / "reviewed.json"
            pacote_path.write_text(
                json.dumps(self.pacote, ensure_ascii=False), encoding="utf-8")
            for caminho, revisao in zip(caminhos, (primeira, segunda)):
                caminho.write_text(
                    json.dumps(revisao, ensure_ascii=False), encoding="utf-8")
            processo = subprocess.run([
                sys.executable,
                str(RAIZ / "ferramentas" /
                    "consolidar_revisao_etiqueta_radar.py"),
                "--pacote", str(pacote_path),
                "--revisao", str(caminhos[0]),
                "--revisao", str(caminhos[1]),
                "--saida", str(saida),
            ], cwd=RAIZ, capture_output=True, text=True, check=False)
            self.assertEqual(processo.returncode, 0, processo.stderr)
            comparacao = json.loads(saida.read_text(encoding="utf-8"))
            self.assertEqual(
                comparacao["state"], "needs_independent_adjudication")
            html = pasta / "reviewed-adjudicacao.html"
            self.assertTrue(html.is_file())
            conteudo = html.read_text(encoding="utf-8")
            self.assertIn(alvo, conteudo)
            self.assertNotIn('"reviewer_aliases"', conteudo)

    def test_cli_nao_deixa_html_orfao_se_saida_json_falhar(self):
        alvo = self.lote["subjects"][0]["subject_id"]
        primeira = submissao(self.lote, "R1")
        segunda = submissao(self.lote, "R2", {alvo: "rejected_candidate"})
        with tempfile.TemporaryDirectory() as pasta:
            saida = Path(pasta) / "resultado.json"
            args = ["consolidar", "--pacote", "facts.json",
                    "--revisao", "R1.json", "--revisao", "R2.json",
                    "--saida", str(saida)]
            with mock.patch.object(sys, "argv", args), \
                    mock.patch.object(consolidador, "carregar_pacote", return_value=self.pacote), \
                    mock.patch.object(consolidador, "_carregar_json", side_effect=[primeira, segunda]), \
                    mock.patch.object(consolidador, "escrever_json_atomico", side_effect=OSError("disco cheio")), \
                    self.assertRaises(SystemExit):
                consolidador.main()
            self.assertFalse(saida.exists())
            self.assertFalse(saida.with_name("resultado-adjudicacao.html").exists())


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(
        __import__(__name__))
    resultado = unittest.TextTestRunner(verbosity=2).run(suite)
    print("Revisão Etiqueta: {} testes, {} falhas".format(
        resultado.testsRun, len(resultado.failures) + len(resultado.errors)))
    raise SystemExit(0 if resultado.wasSuccessful() else 1)
