#!/usr/bin/env python3
"""Portão estrutural da preparação do app para Xcode Cloud."""

import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest
from xml.etree import ElementTree


RAIZ = Path(__file__).resolve().parents[1]
SCHEME = RAIZ / "app/Canario.xcodeproj/xcshareddata/xcschemes/Canario.xcscheme"
SCRIPT = RAIZ / "app/ci_scripts/ci_post_clone.sh"
UI_TESTS = RAIZ / "app/CanarioUITests/CanarioUITests.swift"

ID_APP = "60FCB50722E3F1420F940980"
ID_UI = "309A40032FBF2290592E48A9"


class XcodeCloudContractTests(unittest.TestCase):
    def test_scheme_compartilhado_constroi_app_e_testa_ui_sem_paralelismo(self):
        raiz = ElementTree.parse(SCHEME).getroot()
        self.assertEqual(raiz.tag, "Scheme")

        entradas = raiz.findall("./BuildAction/BuildActionEntries/BuildActionEntry")
        self.assertEqual(len(entradas), 1)
        entrada = entradas[0]
        for atributo in (
                "buildForTesting", "buildForRunning", "buildForProfiling",
                "buildForArchiving", "buildForAnalyzing"):
            self.assertEqual(entrada.get(atributo), "YES")
        referencia_app = entrada.find("./BuildableReference")
        self.assertEqual(referencia_app.get("BlueprintIdentifier"), ID_APP)
        self.assertEqual(referencia_app.get("BuildableName"), "Canario.app")
        self.assertEqual(referencia_app.get("ReferencedContainer"),
                         "container:Canario.xcodeproj")

        test_action = raiz.find("./TestAction")
        self.assertEqual(test_action.get("buildConfiguration"), "Debug")
        testavel = test_action.find("./Testables/TestableReference")
        self.assertEqual(testavel.get("skipped"), "NO")
        self.assertEqual(testavel.get("parallelizable"), "NO")
        referencia_ui = testavel.find("./BuildableReference")
        self.assertEqual(referencia_ui.get("BlueprintIdentifier"), ID_UI)
        self.assertEqual(referencia_ui.get("BuildableName"), "CanarioUITests.xctest")
        self.assertEqual(
            test_action.find("./MacroExpansion/BuildableReference").get(
                "BlueprintIdentifier"), ID_APP)

        self.assertEqual(
            raiz.find("./LaunchAction").get("buildConfiguration"), "Debug")
        self.assertEqual(
            raiz.find("./ProfileAction").get("buildConfiguration"), "Release")
        self.assertEqual(
            raiz.find("./AnalyzeAction").get("buildConfiguration"), "Debug")
        self.assertEqual(
            raiz.find("./ArchiveAction").get("buildConfiguration"), "Release")

    def test_post_clone_e_minimo_executavel_e_nao_distribui(self):
        modo = SCRIPT.stat().st_mode
        self.assertTrue(modo & stat.S_IXUSR)
        texto = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('set -eu', texto)
        self.assertIn('REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:?', texto)
        self.assertIn(
            'cp "$REPO_ROOT/Config.xcconfig.example" "$REPO_ROOT/Config.xcconfig"',
            texto)
        self.assertIn('swift test --package-path "$REPO_ROOT/app"', texto)
        for proibido in (
                "curl ", "wget ", "secrets.", "SUPABASE_SECRET", "OPENAI_API_KEY",
                "xcodebuild archive", "testflight", "altool", "notarytool"):
            self.assertNotIn(proibido.lower(), texto.lower())

    def test_config_real_continua_ignorado_e_modelo_so_tem_placeholders(self):
        ignorado = subprocess.run(
            ["git", "check-ignore", "-q", "Config.xcconfig"],
            cwd=RAIZ, check=False)
        self.assertEqual(ignorado.returncode, 0)
        rastreado = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "Config.xcconfig"],
            cwd=RAIZ, check=False, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
        self.assertNotEqual(rastreado.returncode, 0)
        modelo = (RAIZ / "Config.xcconfig.example").read_text(encoding="utf-8")
        self.assertIn("https://SEU-PROJETO.supabase.co", modelo)
        self.assertIn("sb_publishable_COLE_A_SUA_AQUI", modelo)
        self.assertNotIn("sb_secret_", "\n".join(
            linha for linha in modelo.splitlines()
            if linha.strip() and not linha.lstrip().startswith("//")))

    def _executar_post_clone(self, acao, cloud="TRUE", retorno_swift=0,
                            incluir_raiz=True):
        with tempfile.TemporaryDirectory(prefix="xcode-cloud-") as pasta:
            pasta = Path(pasta)
            raiz = pasta / "repositorio com espacos"
            raiz.mkdir()
            (raiz / "app").mkdir()
            modelo = "// fixture publica\nSUPABASE_URL = exemplo\n"
            anterior = "// configuracao anterior deve sobreviver a recusas\n"
            (raiz / "Config.xcconfig.example").write_text(modelo, encoding="utf-8")
            configuracao = raiz / "Config.xcconfig"
            configuracao.write_text(anterior, encoding="utf-8")
            binarios = pasta / "bin"
            binarios.mkdir()
            swift = binarios / "swift"
            swift.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$@" > "$SWIFT_TEST_LOG"\n'
                'exit "$SWIFT_TEST_EXIT"\n', encoding="utf-8")
            swift.chmod(0o700)
            log = pasta / "swift-args.txt"
            ambiente = {
                "PATH": "{}:/usr/bin:/bin".format(binarios),
                "CI_XCODE_CLOUD": cloud,
                "SWIFT_TEST_LOG": str(log),
                "SWIFT_TEST_EXIT": str(retorno_swift),
            }
            if acao is not None:
                ambiente["CI_XCODEBUILD_ACTION"] = acao
            if incluir_raiz:
                ambiente["CI_PRIMARY_REPOSITORY_PATH"] = str(raiz)
            processo = subprocess.run(
                ["/bin/sh", str(SCRIPT)], cwd=pasta, env=ambiente,
                capture_output=True, text=True, check=False, timeout=10)
            argumentos = (log.read_text(encoding="utf-8").splitlines()
                          if log.exists() else None)
            return {
                "codigo": processo.returncode,
                "erro": processo.stderr,
                "configuracao": configuracao.read_text(encoding="utf-8"),
                "modelo": modelo,
                "anterior": anterior,
                "argumentos": argumentos,
                "pacote": str(raiz / "app"),
            }

    def test_post_clone_prepara_build_e_test_com_caminhos_com_espacos(self):
        for acao in ("build", "build-for-testing", "test-without-building"):
            with self.subTest(acao=acao):
                resultado = self._executar_post_clone(acao)
                self.assertEqual(resultado["codigo"], 0, resultado["erro"])
                self.assertEqual(resultado["configuracao"], resultado["modelo"])
                self.assertEqual(resultado["argumentos"], [
                    "test", "--package-path", resultado["pacote"],
                ])

    def test_post_clone_recusa_archive_e_contextos_invalidos_sem_escrever(self):
        cenarios = [
            {"acao": "archive"}, {"acao": "analyze"}, {"acao": "test"},
            {"acao": "desconhecida"}, {"acao": None}, {"acao": ""},
            {"acao": "build", "cloud": ""},
            {"acao": "build", "incluir_raiz": False},
        ]
        for cenario in cenarios:
            with self.subTest(**cenario):
                resultado = self._executar_post_clone(**cenario)
                self.assertNotEqual(resultado["codigo"], 0)
                self.assertTrue(resultado["erro"])
                self.assertEqual(resultado["configuracao"], resultado["anterior"])
                self.assertIsNone(resultado["argumentos"])

    def test_post_clone_propaga_falha_dos_testes_swift(self):
        resultado = self._executar_post_clone("build-for-testing", retorno_swift=23)
        self.assertEqual(resultado["codigo"], 23)
        self.assertIsNotNone(resultado["argumentos"])

    def test_dados_reais_da_ui_exigem_opt_in_em_qualquer_ambiente(self):
        texto = UI_TESTS.read_text(encoding="utf-8")
        self.assertNotIn('environment["CI"]', texto)
        self.assertEqual(texto.count('environment["CANARIO_REAL_DATA_UI_TESTS"]'), 3)
        for nome in (
                "testCompareNaoFicaReduzidoAUmAtributo",
                "testCompararEmPortuguesMostraDoisEixos",
                "testStripesMostraCurvaDeTamanhosReal"):
            encontrado = re.search(
                r"func {}\(\) throws \{{(?P<corpo>.*?)\n    \}}".format(nome),
                texto, re.DOTALL)
            self.assertIsNotNone(encontrado)
            corpo = encontrado.group("corpo")
            self.assertIn("XCTSkipUnless", corpo)
            self.assertIn("CANARIO_REAL_DATA_UI_TESTS", corpo)
            self.assertIn('== "1"', corpo)


if __name__ == "__main__":
    unittest.main()
