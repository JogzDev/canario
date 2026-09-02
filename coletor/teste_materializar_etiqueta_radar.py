#!/usr/bin/env python3
"""Regressões do primeiro pacote factual privado da Etiqueta 1.3."""

import copy
import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


RAIZ = Path(__file__).resolve().parents[1]
MODULO = RAIZ / "ferramentas" / "materializar_etiqueta_radar.py"
MIGRATION = (
    RAIZ / "supabase" / "migrations" /
    "20260901170000_a52_exportacao_privada_da_etiqueta_13.sql"
)
FONTES = RAIZ / "anexos" / "fontes_radar.csv"

ESPEC = importlib.util.spec_from_file_location("materializador_etiqueta", MODULO)
materializador = importlib.util.module_from_spec(ESPEC)
ESPEC.loader.exec_module(materializador)


CORTE = dt.date(2026, 9, 1)
GERADO = dt.datetime(2026, 9, 1, 18, 0, tzinfo=dt.timezone.utc)


def linha(produto_id, marca_id, composicao, dias=0):
    data = CORTE - dt.timedelta(days=dias)
    return {
        "produto_id": produto_id,
        "marca_id": marca_id,
        "segmento": materializador.SEGMENTO,
        "ofertavel": True,
        "ultimo_avistamento_em": data.isoformat(),
        "snapshot_data": data.isoformat() if composicao is not None else None,
        "composicao": composicao,
    }


def contrato():
    return materializador.carregar_contrato_da_fonte(FONTES, CORTE)


class PacoteTests(unittest.TestCase):
    def setUp(self):
        self.linhas = [
            linha(1, 10, "80% algodão, 20% poliéster em malha"),
            linha(2, 10, "100% algodão"),
            linha(3, 11, None),
            linha(4, 12, "toque de seda e caimento leve"),
        ]

    def pacote(self, linhas=None):
        return materializador.materializar(
            self.linhas if linhas is None else linhas,
            CORTE, contrato(), gerado_em=GERADO)

    def test_pacote_e_privado_minimizado_e_rastreavel(self):
        pacote = self.pacote()
        self.assertEqual(pacote["contract"], materializador.CONTRATO_SAIDA)
        self.assertEqual(pacote["publication_status"], "private_candidate_only")
        self.assertTrue(pacote["requires_human_review"])
        self.assertFalse(pacote["raw_content_persisted"])
        self.assertEqual(pacote["source_id"], materializador.FONTE_ID)
        self.assertRegex(pacote["package_id"], r"^[0-9a-f]{64}$")
        self.assertRegex(pacote["input_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(pacote["payload_sha256"], r"^[0-9a-f]{64}$")
        payload = {chave: pacote[chave] for chave in (
            "population", "items", "aggregates")}
        self.assertEqual(
            pacote["payload_sha256"],
            materializador._sha256(materializador._json_canonico(payload)))
        self.assertRegex(pacote["authorization_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(len(pacote["items"]), 2)
        self.assertNotIn(
            "80% algodão, 20% poliéster em malha",
            json.dumps(pacote, ensure_ascii=False),
        )
        for item in pacote["items"]:
            self.assertNotIn("composicao", item)
            self.assertNotIn("texto_normalizado", item)
            self.assertRegex(item["content_sha256"], r"^[0-9a-f]{64}$")
            for fato in item["facts"]:
                self.assertEqual(fato["status"], "candidate_fact")
                self.assertTrue(fato["requires_human_review"])
                self.assertLessEqual(len(fato["source_excerpt"]), 500)

    def test_denominador_e_cobertura_nao_usam_catalogo_total_em_silencio(self):
        pacote = self.pacote()
        pop = pacote["population"]
        self.assertEqual(pop["eligible_products"], 4)
        self.assertEqual(pop["products_with_source_label"], 3)
        self.assertEqual(pop["products_with_candidate_fact"], 2)
        self.assertEqual(pop["products_globally_abstained"], 2)
        fibra = pop["dimensions"]["fiber"]
        self.assertEqual(fibra["observed_products"], 2)
        self.assertEqual(fibra["abstained_products"], 2)
        self.assertEqual(fibra["coverage_of_eligible_pct"], 50.0)

        agregados = {
            (item["family"], item["facet_id"]): item
            for item in pacote["aggregates"]
        }
        algodao = agregados[("fiber", "algodao")]
        poliester = agregados[("fiber", "poliester")]
        self.assertEqual(algodao["product_count"], 2)
        self.assertEqual(algodao["denominator_products"], 2)
        self.assertEqual(algodao["share_among_dimension_observed_pct"], 100.0)
        self.assertEqual(poliester["share_among_dimension_observed_pct"], 50.0)
        self.assertEqual(algodao["brand_count"], 1)

    def test_ordem_da_entrada_nao_muda_identidade_nem_conteudo_factual(self):
        primeiro = self.pacote(self.linhas)
        segundo = self.pacote(list(reversed(self.linhas)))
        self.assertEqual(primeiro["package_id"], segundo["package_id"])
        self.assertEqual(primeiro["input_sha256"], segundo["input_sha256"])
        self.assertEqual(primeiro["items"], segundo["items"])
        self.assertEqual(primeiro["aggregates"], segundo["aggregates"])

    def test_conceito_e_evidencia_nao_sao_promovidos(self):
        serializado = json.dumps(self.pacote(), ensure_ascii=False)
        self.assertNotIn('"status": "approved"', serializado)
        self.assertNotIn('"status": "published"', serializado)
        self.assertNotIn('"evidence_status"', serializado)

    def test_populacao_vazia_nao_reutiliza_amostra_nem_inventa_cobertura(self):
        pacote = self.pacote([])
        self.assertEqual(pacote["population"]["eligible_products"], 0)
        self.assertEqual(pacote["items"], [])
        self.assertEqual(pacote["aggregates"], [])
        for dimensao in pacote["population"]["dimensions"].values():
            self.assertEqual(dimensao["observed_products"], 0)
            self.assertEqual(dimensao["abstained_products"], 0)
            self.assertIsNone(dimensao["coverage_of_eligible_pct"])


class EntradaTests(unittest.TestCase):
    def test_envelope_offline_valido(self):
        entrada = {
            "contract": materializador.CONTRATO_ENTRADA,
            "cutoff_date": CORTE.isoformat(),
            "rows": [linha(1, 2, "100% algodão")],
        }
        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "entrada.json"
            caminho.write_text(json.dumps(entrada), encoding="utf-8")
            linhas, corte = materializador.carregar_entrada(caminho)
        self.assertEqual(corte, CORTE)
        self.assertEqual(linhas[0]["produto_id"], 1)

    def test_rejeita_produto_duplicado_stale_fora_do_segmento_ou_sem_oferta(self):
        casos = []
        duplicadas = [linha(1, 1, None), linha(1, 2, None)]
        casos.append(duplicadas)
        stale = linha(2, 1, None, dias=8)
        casos.append([stale])
        segmento = linha(3, 1, None)
        segmento["segmento"] = "direcao_intl"
        casos.append([segmento])
        sem_oferta = linha(4, 1, None)
        sem_oferta["ofertavel"] = False
        casos.append([sem_oferta])
        for caso in casos:
            with self.subTest(caso=caso), self.assertRaises(
                    materializador.ErroDeMaterializacao):
                materializador.validar_linhas(caso, CORTE)

    def test_rejeita_snapshot_sem_composicao_ou_fora_da_janela(self):
        sem_texto = linha(1, 1, None)
        sem_texto["snapshot_data"] = CORTE.isoformat()
        antigo = linha(2, 1, "100% algodão")
        antigo["snapshot_data"] = (CORTE - dt.timedelta(days=22)).isoformat()
        for caso in ([sem_texto], [antigo]):
            with self.assertRaises(materializador.ErroDeMaterializacao):
                materializador.validar_linhas(caso, CORTE)

    def test_registro_interno_exige_hash_real_da_governanca(self):
        fonte = contrato()
        self.assertEqual(fonte["source_id"], materializador.FONTE_ID)
        self.assertEqual(
            fonte["authorization_sha256"],
            materializador._sha256(
                (RAIZ / "GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md").
                read_bytes()),
        )


class PaginacaoTests(unittest.TestCase):
    def test_rpc_e_paginada_ate_lote_curto(self):
        hoje = dt.datetime.now(materializador.FUSO_OPERACIONAL).date()

        def remota(produto_id):
            base = linha(produto_id, 10, None)
            base["ultimo_avistamento_em"] = hoje.isoformat()
            return {"data_corte": hoje.isoformat(), **base}

        respostas = [[remota(1), remota(2)], [remota(3)]]
        cursores = []

        def rpc(nome, parametros, tentativas):
            self.assertEqual(nome, "exportar_linhas_etiqueta_13")
            self.assertEqual(tentativas, 1)
            cursores.append(parametros["p_after_id"])
            return respostas.pop(0)

        with mock.patch.object(materializador.supabase_rest, "configurado",
                               return_value=True), \
                mock.patch.object(materializador.supabase_rest, "rpc",
                                  side_effect=rpc), \
                mock.patch.object(materializador, "PAGINA_SUPABASE", 2):
            linhas, corte = materializador.carregar_do_supabase()
        self.assertEqual(corte, hoje)
        self.assertEqual([item["produto_id"] for item in linhas], [1, 2, 3])
        self.assertEqual(cursores, [0, 2])

    def test_rpc_rejeita_cursor_que_nao_avanca(self):
        hoje = dt.datetime.now(materializador.FUSO_OPERACIONAL).date()
        base = linha(1, 10, None)
        base["ultimo_avistamento_em"] = hoje.isoformat()
        resposta = {"data_corte": hoje.isoformat(), **base}
        with mock.patch.object(materializador.supabase_rest, "configurado",
                               return_value=True), \
                mock.patch.object(materializador.supabase_rest, "rpc",
                                  side_effect=[[resposta], [resposta]]), \
                mock.patch.object(materializador, "PAGINA_SUPABASE", 1):
            with self.assertRaises(materializador.ErroDeMaterializacao):
                materializador.carregar_do_supabase()


class MigrationTests(unittest.TestCase):
    def test_rpc_e_privada_paginada_atual_e_somente_leitura(self):
        texto = MIGRATION.read_text(encoding="utf-8").lower()
        exigidos = (
            "create or replace function public.exportar_linhas_etiqueta_13(",
            "p_data_corte date",
            "p_after_id bigint default 0",
            "p_limit integer default 1000",
            "security definer",
            "set search_path = pg_catalog, public, pg_temp",
            "p_limit not between 1 and 1000",
            "p.id > p_after_id",
            "p.segmento = 'feminino_casual_br'",
            "ep.ofertavel is true",
            "ep.ultimo_avistamento_em between p_data_corte - 7",
            "s.data between p_data_corte - 21",
            "order by p.id",
            "limit p_limit",
            "revoke all on function public.exportar_linhas_etiqueta_13",
            "from public, anon, authenticated",
            "to service_role",
        )
        for trecho in exigidos:
            self.assertIn(trecho, texto)
        for proibido in (
                "insert into", "update public.", "delete from",
                "p.id_externo",
                "grant execute on function public.exportar_linhas_etiqueta_13"
                "(date, bigint, integer) to anon"):
            self.assertNotIn(proibido, texto)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(
        __import__(__name__))
    resultado = unittest.TextTestRunner(verbosity=2).run(suite)
    total = resultado.testsRun
    falhas = len(resultado.failures) + len(resultado.errors)
    print("Materializador Etiqueta: {} testes, {} falhas".format(
        total, falhas))
    raise SystemExit(0 if resultado.wasSuccessful() else 1)
