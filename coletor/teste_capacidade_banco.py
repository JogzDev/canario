"""Regressoes offline: limiar estrito, diagnostico e falha fechada do RPC."""

import contextlib
import io
import json
import os
import tempfile
import unittest
from unittest.mock import patch

import verificar_capacidade_banco as capacidade


class CapacidadeTests(unittest.TestCase):
    def test_fronteiras_inclusivas(self):
        for usados, esperado in (
                (0, "ok"), (424_999_999, "ok"), (425_000_000, "aviso"),
                (479_999_999, "aviso"), (480_000_000, "critico"),
                (500_000_000, "critico"), (510_000_000, "critico")):
            with self.subTest(usados=usados):
                estado, fracao, livres = capacidade.avaliar_capacidade(usados)
                self.assertEqual(estado, esperado)
                self.assertEqual(fracao, usados / 500_000_000)
                self.assertEqual(livres, 500_000_000 - usados)

    def test_inteiros_invalidos_nao_viram_permissao(self):
        for valor in (-1, "500", None, True, False, 1.5):
            with self.subTest(valor=valor):
                with self.assertRaises(ValueError):
                    capacidade.avaliar_capacidade(valor)
        for limite in (0, -1, None, True, "500", 500.5):
            with self.subTest(limite=limite):
                with self.assertRaises(ValueError):
                    capacidade.avaliar_capacidade(0, limite)

    def test_folga_e_recuperacao_respeitam_um_byte_abaixo(self):
        d = capacidade.diagnosticar_capacidade(485_125_267)
        self.assertFalse(d["escrita_permitida"])
        self.assertEqual(d["bytes_livres"], 14_874_733)
        self.assertEqual(d["liberar_para_abaixo_critico_bytes"], 5_125_268)
        self.assertEqual(d["liberar_para_abaixo_aviso_bytes"], 60_125_268)
        self.assertEqual(d["folga_ate_critico_bytes"], 0)
        for chave, esperado in (("liberar_para_abaixo_critico_bytes", "aviso"),
                                ("liberar_para_abaixo_aviso_bytes", "ok")):
            self.assertEqual(capacidade.avaliar_capacidade(
                d["bytes_usados"] - d[chave])[0], esperado)
        self.assertEqual(capacidade.diagnosticar_capacidade(
            479_999_999)["folga_ate_critico_bytes"], 1)

    def test_limite_diferente_e_overflow(self):
        # A leitura usa o limite informado, nunca presume o plano Free.
        d = capacidade.diagnosticar_capacidade(960, 1000)
        self.assertEqual(d["critico_bytes"], 960)
        self.assertEqual(d["liberar_para_abaixo_critico_bytes"], 1)
        self.assertEqual(capacidade.diagnosticar_capacidade(
            510_000_000)["bytes_excedentes"], 10_000_000)
        for usados in range(8):
            d = capacidade.diagnosticar_capacidade(usados, 7)
            self.assertEqual(d["estado"] == "critico",
                             usados >= d["critico_bytes"])

    def test_contrato_rpc(self):
        self.assertEqual(capacidade.diagnosticar_leitura(
            {"bytes": "425000000"})["estado"], "aviso")
        for leitura in (None, [], {}, {"bytes": True}, {"bytes": 1.5},
                        {"bytes": "1.5"}, {"bytes": -1},
                        {"bytes": 1, "limite_bytes": None},
                        {"bytes": 1, "limite_bytes": 0},
                        {"bytes": 1, "limite_bytes": False}):
            with self.subTest(leitura=leitura):
                with self.assertRaises((KeyError, ValueError)):
                    capacidade.diagnosticar_leitura(leitura)

    def executar_cli(self, leitura=None, erro=None, configurado=True):
        stdout, stderr = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory(prefix="canario-capacidade-teste-") as pasta:
            destino = os.path.join(pasta, "outputs")
            with patch.object(capacidade.supabase_rest, "configurado",
                              return_value=configurado), \
                    patch.object(capacidade.supabase_rest, "rpc",
                                 return_value=leitura, side_effect=erro) as rpc, \
                    patch.dict(os.environ, {"GITHUB_OUTPUT": destino}), \
                    contextlib.redirect_stdout(stdout), \
                    contextlib.redirect_stderr(stderr):
                codigo = capacidade.main(["--json", "--github-output"])
            if not configurado:
                rpc.assert_not_called()
            with open(destino, encoding="utf-8") as saida:
                outputs = dict(linha.rstrip().split("=", 1) for linha in saida)
        return codigo, json.loads(stdout.getvalue()), outputs, stderr.getvalue()

    def test_cli_publica_json_e_output_sem_relaxar_exit_code(self):
        for usados, codigo, permitido in ((100, 0, "true"),
                                          (425_000_000, 0, "true"),
                                          (480_000_000, 1, "false")):
            with self.subTest(usados=usados):
                resultado, dados, outputs, _ = self.executar_cli({"bytes": usados})
                self.assertEqual(resultado, codigo)
                self.assertEqual(outputs["escrita_permitida"], permitido)
                self.assertEqual(outputs["estado"], dados["estado"])

    def test_cli_indisponivel_fecha_sem_inventar_tamanho(self):
        for argumentos, motivo in (
                ({"configurado": False}, "configuracao_ausente"),
                ({"leitura": {}}, "leitura_invalida"),
                ({"erro": capacidade.supabase_rest.SupabaseErro(
                    "corpo-remoto-sensivel")}, "consulta_falhou")):
            with self.subTest(motivo=motivo):
                codigo, dados, outputs, stderr = self.executar_cli(**argumentos)
                self.assertEqual(codigo, 1)
                self.assertEqual(dados["erro"], motivo)
                self.assertNotIn("bytes_usados", dados)
                self.assertEqual(outputs["escrita_permitida"], "false")
                self.assertNotIn("corpo-remoto-sensivel", stderr)

    def test_output_indisponivel_tambem_falha_fechado(self):
        with patch.object(capacidade.supabase_rest, "configurado", return_value=True), \
                patch.object(capacidade.supabase_rest, "rpc", return_value={"bytes": 0}), \
                patch.dict(os.environ, {}, clear=True), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(capacidade.main(["--github-output"]), 1)

    def test_cli_existente_preserva_anotacoes_e_exit_code(self):
        for usados, esperado, anotacao in (
                (0, 0, "Banco: 0.0%"),
                (425_000_000, 0, "::warning title=Capacidade do banco::"),
                (480_000_000, 1, "::error title=Capacidade critica::")):
            with self.subTest(usados=usados):
                stdout = io.StringIO()
                with patch.object(capacidade.supabase_rest, "configurado",
                                  return_value=True), \
                        patch.object(capacidade.supabase_rest, "rpc",
                                     return_value={"bytes": usados}), \
                        contextlib.redirect_stdout(stdout), \
                        contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(capacidade.main([]), esperado)
                self.assertIn(anotacao, stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
