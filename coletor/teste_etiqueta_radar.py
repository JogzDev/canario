"""Regressoes do parser local de composicao/material do Etiqueta Radar."""

import ast
import json
import os
import re
import sys
import unittest


PASTA = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PASTA)

from etiqueta_radar import (  # noqa: E402
    LIMITE_CARACTERES,
    VERSAO_PARSER,
    analisar_etiqueta,
    parsear_etiqueta,
)


def fibras(resultado):
    return [(item["fibra_id"], item["percentual"])
            for item in resultado["composicao"]]


def construcoes(resultado):
    return [item["item_id"] for item in resultado["construcao"]]


def acabamentos(resultado):
    return [item["item_id"] for item in resultado["acabamento"]]


class ContratoTests(unittest.TestCase):
    def test_contrato_publico_e_json(self):
        resultado = analisar_etiqueta("100% algodão; sarja estonada")
        self.assertEqual(set(resultado), {
            "versao", "texto_normalizado", "composicao", "construcao",
            "acabamento", "abstencao", "motivos_abstencao",
            "campos_abstidos", "confianca", "explicacao_confianca", "avisos",
        })
        self.assertIsInstance(resultado["abstencao"], bool)
        self.assertIn(resultado["confianca"], {"alta", "media", "baixa", "nenhuma"})
        json.dumps(resultado, ensure_ascii=False)

    def test_ids_e_versao_sao_ascii_estaveis(self):
        resultado = analisar_etiqueta(
            "70% lã, 30% liocel; malha canelada; acabamento plissado")
        ids = ([item["fibra_id"] for item in resultado["composicao"]] +
               construcoes(resultado) + acabamentos(resultado))
        self.assertRegex(VERSAO_PARSER, r"^[a-z0-9-]+$")
        for item_id in ids:
            self.assertRegex(item_id, r"^[a-z0-9_]+$")

    def test_alias_chama_a_mesma_implementacao(self):
        self.assertIs(parsear_etiqueta, analisar_etiqueta)

    def test_deterministico_e_sem_estado_compartilhado(self):
        primeiro = analisar_etiqueta("100% algodão; sarja")
        segundo = analisar_etiqueta("100% algodão; sarja")
        self.assertEqual(primeiro, segundo)
        primeiro["composicao"].clear()
        self.assertEqual(fibras(analisar_etiqueta("100% algodão; sarja")),
                         [("algodao", 100)])

    def test_modulo_nao_importa_rede_modelo_ou_subprocesso(self):
        caminho = os.path.join(PASTA, "etiqueta_radar.py")
        with open(caminho, encoding="utf-8") as arquivo:
            arvore = ast.parse(arquivo.read())
        importados = set()
        for no in ast.walk(arvore):
            if isinstance(no, ast.Import):
                importados.update(alias.name.split(".")[0] for alias in no.names)
            elif isinstance(no, ast.ImportFrom) and no.module:
                importados.add(no.module.split(".")[0])
        self.assertTrue(importados.isdisjoint({
            "urllib", "requests", "httpx", "socket", "openai", "anthropic",
            "subprocess", "supabase",
        }), importados)


class ComposicaoTests(unittest.TestCase):
    def test_percentual_antes_da_fibra(self):
        resultado = analisar_etiqueta("Composição: 95% Algodão + 5% Elastano")
        self.assertEqual(fibras(resultado), [("algodao", 95), ("elastano", 5)])
        self.assertEqual(resultado["confianca"], "alta")

    def test_percentual_depois_da_fibra_e_decimal_brasileiro(self):
        resultado = analisar_etiqueta("Viscose 96,5%; Elastano 3,5%")
        self.assertEqual(fibras(resultado), [("viscose", 96.5), ("elastano", 3.5)])

    def test_espaco_inseparavel_e_caixa(self):
        resultado = analisar_etiqueta("100\u00a0% POLIÉSTER")
        self.assertEqual(fibras(resultado), [("poliester", 100)])

    def test_aliases_canonicos(self):
        resultado = analisar_etiqueta(
            "25% Tencel, 25% nylon, 25% spandex, 25% cashmere")
        self.assertEqual(fibras(resultado), [
            ("liocel", 25), ("poliamida", 25),
            ("elastano", 25), ("caxemira", 25),
        ])

    def test_qualificador_fica_no_trecho_sem_mudar_id(self):
        antes = analisar_etiqueta("Algodão orgânico 100%")
        depois = analisar_etiqueta("100% poliéster reciclado")
        self.assertEqual(fibras(antes), [("algodao", 100)])
        self.assertEqual(antes["composicao"][0]["trecho_fonte"],
                         "Algodão orgânico 100%")
        self.assertEqual(fibras(depois), [("poliester", 100)])
        self.assertEqual(depois["composicao"][0]["trecho_fonte"],
                         "100% poliéster reciclado")

    def test_partes_nao_somam_uma_na_outra(self):
        resultado = analisar_etiqueta(
            "Corpo: 96% viscose, 4% elastano; Forro: 100% poliéster")
        self.assertEqual([item["parte_id"] for item in resultado["composicao"]],
                         ["corpo", "corpo", "forro"])
        self.assertFalse(any(aviso.startswith("soma_percentual_excedente")
                             for aviso in resultado["avisos"]))
        self.assertEqual(resultado["confianca"], "alta")

    def test_mencao_a_forro_em_frase_anterior_nao_vaza_para_composicao(self):
        resultado = analisar_etiqueta("Sem forro. Composição: 100% algodão")
        self.assertEqual(resultado["composicao"][0]["parte_id"], "principal")

    def test_material_nao_fibroso_declarado_e_preservado(self):
        resultado = analisar_etiqueta("70% couro natural e 30% poliuretano")
        self.assertEqual(fibras(resultado), [("couro", 70), ("poliuretano", 30)])

    def test_couro_sintetico_nao_vira_couro_natural(self):
        resultado = analisar_etiqueta("100% couro sintético")
        self.assertEqual(fibras(resultado), [("couro_sintetico", 100)])

    def test_fibras_sem_percentual_nao_ganham_numero(self):
        resultado = analisar_etiqueta("Mistura de algodão e linho")
        self.assertEqual(fibras(resultado), [("algodao", None), ("linho", None)])
        self.assertEqual(resultado["confianca"], "media")
        self.assertIn("fibra_sem_percentual", resultado["avisos"])

    def test_campo_bilingue_nao_duplica_fibra(self):
        resultado = analisar_etiqueta("100% algodão / cotton")
        self.assertEqual(fibras(resultado), [("algodao", 100)])

    def test_toque_de_seda_nao_e_composicao(self):
        resultado = analisar_etiqueta("Tecido premium com toque de seda")
        self.assertEqual(resultado["composicao"], [])
        self.assertTrue(resultado["abstencao"])

    def test_negacao_nao_vira_fibra(self):
        resultado = analisar_etiqueta("Sem lã e sem couro")
        self.assertEqual(resultado["composicao"], [])
        self.assertTrue(resultado["abstencao"])

    def test_percentual_desconhecido_rebaixa_sem_inventar(self):
        resultado = analisar_etiqueta("50% algodão, 50% fibra secreta")
        self.assertEqual(fibras(resultado), [("algodao", 50)])
        self.assertIn("percentual_sem_componente_reconhecido", resultado["avisos"])
        self.assertEqual(resultado["confianca"], "baixa")

    def test_soma_incompleta_e_excedente_sao_auditaveis(self):
        incompleta = analisar_etiqueta("80% algodão")
        excedente = analisar_etiqueta("80% algodão, 30% elastano")
        self.assertIn("soma_percentual_incompleta:principal", incompleta["avisos"])
        self.assertIn("soma_percentual_excedente:principal", excedente["avisos"])
        self.assertEqual(incompleta["confianca"], "baixa")
        self.assertEqual(excedente["confianca"], "baixa")

    def test_arredondamento_de_um_ponto_e_aceito(self):
        resultado = analisar_etiqueta("67% viscose e 32% linho")
        self.assertNotIn("soma_percentual_incompleta:principal", resultado["avisos"])
        self.assertEqual(resultado["confianca"], "alta")

    def test_percentual_impossivel_nao_e_recortado_como_numero_valido(self):
        resultado = analisar_etiqueta("120% algodão")
        self.assertEqual(fibras(resultado), [("algodao", None)])
        self.assertIn("percentual_sem_componente_reconhecido", resultado["avisos"])
        self.assertEqual(resultado["confianca"], "baixa")


class ConstrucaoTests(unittest.TestCase):
    def test_construcao_nao_vira_fibra(self):
        resultado = analisar_etiqueta("Material: 100% jeans")
        self.assertEqual(resultado["composicao"], [])
        self.assertEqual(construcoes(resultado), ["denim"])

    def test_especifico_suprime_generico_sobreposto(self):
        resultado = analisar_etiqueta("Tecido em malha canelada")
        self.assertEqual(construcoes(resultado), ["malha_canelada"])
        self.assertEqual(resultado["construcao"][0]["trecho_fonte"],
                         "malha canelada")

    def test_varias_construcoes_em_ordem_de_fonte(self):
        resultado = analisar_etiqueta("Corpo de tricô; detalhe em crochê e tule")
        self.assertEqual(construcoes(resultado), ["trico", "croche", "tule"])

    def test_construcoes_pt_br_e_ingles(self):
        resultado = analisar_etiqueta("Tecido plano / woven fabric, sarja twill")
        self.assertEqual(construcoes(resultado), ["tecido_plano", "sarja"])

    def test_renda_composta_suprime_renda_generica(self):
        resultado = analisar_etiqueta("Renda guipir com forro de tule")
        self.assertEqual(construcoes(resultado), ["renda", "tule"])
        self.assertEqual(resultado["construcao"][0]["trecho_fonte"], "Renda guipir")

    def test_substring_nao_casa(self):
        resultado = analisar_etiqueta("Serviço de malharia com acabamento sarjado")
        self.assertEqual(resultado["construcao"], [])

    def test_efeito_jeans_nao_afirma_construcao_denim(self):
        resultado = analisar_etiqueta("Malha com efeito jeans")
        self.assertEqual(construcoes(resultado), ["malha"])

    def test_microfibra_e_construcao_nao_fibra_inventada(self):
        resultado = analisar_etiqueta("Material: microfibra")
        self.assertEqual(resultado["composicao"], [])
        self.assertEqual(construcoes(resultado), ["microfibra"])


class AcabamentoTests(unittest.TestCase):
    def test_acabamentos_aparentes(self):
        resultado = analisar_etiqueta(
            "Denim com lavagem estonada, bordado e aplicação de paetês")
        self.assertEqual(acabamentos(resultado), ["estonado", "bordado", "paete"])

    def test_acabamentos_mantem_trecho_fonte(self):
        resultado = analisar_etiqueta("Acabamento METALIZADO e barra desfiada")
        self.assertEqual(resultado["acabamento"], [
            {"item_id": "metalizado", "trecho_fonte": "METALIZADO"},
            {"item_id": "desfiado", "trecho_fonte": "barra desfiada"},
        ])

    def test_negacao_de_acabamento(self):
        resultado = analisar_etiqueta("Sem acabamento resinado; tecido sarja")
        self.assertEqual(resultado["acabamento"], [])
        self.assertEqual(construcoes(resultado), ["sarja"])

    def test_instrucao_de_lavagem_nao_e_acabamento(self):
        resultado = analisar_etiqueta("Instruções de lavagem: lavar à mão")
        self.assertEqual(resultado["acabamento"], [])
        self.assertTrue(resultado["abstencao"])

    def test_reciclado_nao_e_acabamento(self):
        resultado = analisar_etiqueta("100% algodão reciclado")
        self.assertEqual(acabamentos(resultado), [])
        self.assertEqual(fibras(resultado), [("algodao", 100)])

    def test_acabamento_repetido_sai_uma_vez(self):
        resultado = analisar_etiqueta("Bordado frontal e costas bordadas")
        self.assertEqual(acabamentos(resultado), ["bordado"])


class AbstencaoTests(unittest.TestCase):
    def test_nulo_vazio_e_tipo_invalido(self):
        casos = [(None, "entrada_nula"), (" \n ", "entrada_vazia"),
                 (123, "tipo_invalido")]
        for entrada, motivo in casos:
            with self.subTest(entrada=entrada):
                resultado = analisar_etiqueta(entrada)
                self.assertTrue(resultado["abstencao"])
                self.assertEqual(resultado["confianca"], "nenhuma")
                self.assertEqual(resultado["motivos_abstencao"], [motivo])

    def test_texto_longo_demais_abstem_sem_processar(self):
        resultado = analisar_etiqueta("a" * (LIMITE_CARACTERES + 1))
        self.assertTrue(resultado["abstencao"])
        self.assertEqual(resultado["motivos_abstencao"], ["texto_excede_limite"])

    def test_declaracoes_sem_dado(self):
        for texto in (
            "Composição não informada", "Material indisponível",
            "Consulte a etiqueta", "Sem informações",
        ):
            with self.subTest(texto=texto):
                resultado = analisar_etiqueta(texto)
                self.assertTrue(resultado["abstencao"])
                self.assertEqual(resultado["motivos_abstencao"],
                                 ["declaracao_sem_dado"])

    def test_marketing_vago_abstem(self):
        resultado = analisar_etiqueta("Tecido premium, sustentável e muito macio")
        self.assertTrue(resultado["abstencao"])
        self.assertEqual(resultado["motivos_abstencao"],
                         ["nenhum_padrao_reconhecido"])

    def test_resultado_parcial_nao_e_abstencao_global(self):
        resultado = analisar_etiqueta(
            "Composição não informada. Construção: sarja estonada")
        self.assertFalse(resultado["abstencao"])
        self.assertEqual(construcoes(resultado), ["sarja"])
        self.assertEqual(acabamentos(resultado), ["estonado"])
        self.assertEqual(resultado["confianca"], "baixa")
        self.assertIn("composicao", resultado["campos_abstidos"])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    resultado = unittest.TextTestRunner(verbosity=2).run(suite)
    print("Etiqueta Radar: {} testes, {} falhas, {} erros".format(
        resultado.testsRun, len(resultado.failures), len(resultado.errors)))
    sys.exit(0 if resultado.wasSuccessful() else 1)
