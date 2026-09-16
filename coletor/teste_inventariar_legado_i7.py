#!/usr/bin/env python3
"""Contrato offline do inventário agregado para a retirada do i7."""

import datetime as dt
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "ferramentas"))

import inventariar_legado_i7 as inventario


class InventarioLegadoTests(unittest.TestCase):
    def test_cache_ausente_nao_e_erro_nem_vira_varredura_do_home(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            medida = inventario.inventariar(Path(pasta) / "nao-existe")
        self.assertEqual(medida["estado"], "ausente")
        self.assertEqual(medida["arquivos_regulares"], 0)
        self.assertEqual(medida["bytes_regulares"], 0)
        self.assertEqual(medida["extensoes"], {})
        self.assertFalse(medida["completo"])

    def test_agrega_sem_expor_nomes_ou_seguir_links(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            raiz = Path(pasta) / "cache"
            raiz.mkdir()
            subdiretorio = raiz / "sub"
            subdiretorio.mkdir()
            primeira = raiz / "produto-sensivel.jpg"
            segunda = subdiretorio / "resposta-confidencial.json"
            sem_extensao = subdiretorio / "sem-nome-publicavel"
            primeira.write_bytes(b"abc")
            segunda.write_bytes(b"12345")
            sem_extensao.write_bytes(b"x")
            os.utime(primeira, (1_700_000_000, 1_700_000_000))
            os.utime(segunda, (1_700_000_100, 1_700_000_100))
            os.utime(sem_extensao, (1_700_000_050, 1_700_000_050))
            fora = Path(pasta) / "fora.txt"
            fora.write_bytes(b"nao-entra")
            (raiz / "link-para-fora").symlink_to(fora)

            medida = inventario.inventariar(raiz)
            serializado = json.dumps(medida, ensure_ascii=False)

        self.assertEqual(medida["estado"], "diretorio")
        self.assertEqual(medida["diretorios"], 2)
        self.assertEqual(medida["arquivos_regulares"], 3)
        self.assertEqual(medida["bytes_regulares"], 9)
        self.assertEqual(medida["links_ignorados"], 1)
        self.assertEqual(medida["extensoes"], {
            ".jpg": 1, "[outra]": 1, "[sem_extensao]": 1,
        })
        self.assertTrue(medida["completo"])
        self.assertEqual(medida["arquivo_mais_antigo_em"],
                         "2023-11-14T22:13:20+00:00")
        self.assertEqual(medida["arquivo_mais_recente_em"],
                         "2023-11-14T22:15:00+00:00")
        for proibido in ("produto-sensivel", "resposta-confidencial",
                          "sem-nome-publicavel", "link-para-fora", "fora.txt"):
            self.assertNotIn(proibido, serializado)

    def test_raiz_link_ou_arquivo_nao_e_seguida(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)
            arquivo = pasta / "arquivo.jpg"
            arquivo.write_bytes(b"x")
            link = pasta / "cache-link"
            link.symlink_to(arquivo)
            self.assertEqual(inventario.inventariar(arquivo)["estado"],
                             "nao_e_diretorio")
            medida_link = inventario.inventariar(link)
        self.assertEqual(medida_link["estado"], "link_ignorado")
        self.assertEqual(medida_link["links_ignorados"], 1)

    def test_envelope_e_saida_sao_deterministicos_e_explicitos(self):
        momento = dt.datetime(2026, 9, 16, 15, 0, tzinfo=dt.timezone.utc)
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)
            cache = pasta / "cache"
            cache.mkdir()
            (cache / "a.png").write_bytes(b"123")
            dados = inventario.gerar(cache, "abc123", agora=momento)
            destino = pasta / "inventario.json"
            inventario._escrever_json(str(destino), dados)
            lido = json.loads(destino.read_text(encoding="utf-8"))
            self.assertEqual({p.name for p in pasta.iterdir()},
                             {"cache", "inventario.json"})
        self.assertEqual(lido["schema"], "datadrobe_legacy_cache_inventory_v1")
        self.assertEqual(lido["gerado_em"], "2026-09-16T15:00:00+00:00")
        self.assertEqual(lido["referencia_do_workflow"], "abc123")
        with self.assertRaises(ValueError):
            inventario._escrever_json("/diretorio-inexistente/inventario.json", dados)

    def test_troca_de_subdiretorio_por_link_nao_escapa_da_raiz(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)
            raiz = pasta / "cache"
            sub = raiz / "sub"
            sub.mkdir(parents=True)
            (raiz / "estavel.jpg").write_bytes(b"123")
            (sub / "interno.jpg").write_bytes(b"nao-importa")
            fora = pasta / "fora"
            fora.mkdir()
            (fora / "externo.jpg").write_bytes(b"x" * 777)
            sub_original = raiz / "sub-original"
            stat_original = inventario.os.stat
            trocado = False

            def stat_com_troca(nome, *args, **kwargs):
                nonlocal trocado
                if (nome == "sub" and kwargs.get("dir_fd") is not None and
                        kwargs.get("follow_symlinks") is False and not trocado):
                    trocado = True
                    sub.rename(sub_original)
                    sub.symlink_to(fora, target_is_directory=True)
                return stat_original(nome, *args, **kwargs)

            with mock.patch.object(inventario.os, "stat", side_effect=stat_com_troca):
                medida = inventario.inventariar(raiz)

        self.assertTrue(trocado)
        self.assertEqual(medida["bytes_regulares"], 3)
        self.assertNotEqual(medida["bytes_regulares"], 777)
        self.assertEqual(medida["links_ignorados"], 1)

    def test_troca_da_raiz_por_outro_diretorio_e_rejeitada_sem_varredura(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)
            raiz = pasta / "cache"
            raiz.mkdir()
            (raiz / "esperado.jpg").write_bytes(b"123")
            substituto = pasta / "substituto"
            substituto.mkdir()
            (substituto / "inesperado.jpg").write_bytes(b"x" * 777)
            open_original = inventario.os.open
            descritores = []

            def abrir_apos_troca(caminho, flags, *args, **kwargs):
                if str(caminho) == str(raiz) and not descritores:
                    raiz.rename(pasta / "cache-original")
                    substituto.rename(raiz)
                    descritor = open_original(caminho, flags, *args, **kwargs)
                    descritores.append(descritor)
                    return descritor
                return open_original(caminho, flags, *args, **kwargs)

            with mock.patch.object(inventario.os, "open", side_effect=abrir_apos_troca):
                medida = inventario.inventariar(raiz)

            self.assertEqual(len(descritores), 1)
            with self.assertRaises(OSError):
                os.fstat(descritores[0])

        self.assertEqual(medida["estado"], "inacessivel")
        self.assertFalse(medida["completo"])
        self.assertEqual(medida["motivo_incompleto"], "raiz_trocada")
        self.assertEqual(medida["erros_de_leitura"], 1)
        self.assertEqual(medida["diretorios"], 0)
        self.assertEqual(medida["arquivos_regulares"], 0)
        self.assertEqual(medida["bytes_regulares"], 0)

    def test_erro_de_stat_limites_e_fifo_falham_fechado(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            raiz = Path(pasta) / "cache"
            raiz.mkdir()
            (raiz / "a.jpg").write_bytes(b"a")
            (raiz / "b.jpg").write_bytes(b"b")

            limitado = inventario.inventariar(raiz, max_entradas=1)
            self.assertFalse(limitado["completo"])
            self.assertEqual(limitado["motivo_incompleto"], "limite_de_entradas")

            stat_original = inventario.os.stat

            def stat_com_erro(nome, *args, **kwargs):
                if nome == "a.jpg" and kwargs.get("dir_fd") is not None:
                    raise PermissionError("fixture")
                return stat_original(nome, *args, **kwargs)

            with mock.patch.object(inventario.os, "stat", side_effect=stat_com_erro):
                com_erro = inventario.inventariar(raiz)
            self.assertFalse(com_erro["completo"])
            self.assertGreater(com_erro["erros_de_leitura"], 0)

            if hasattr(os, "mkfifo"):
                os.mkfifo(raiz / "canal")
                com_fifo = inventario.inventariar(raiz)
                self.assertEqual(com_fifo["entradas_especiais_ignoradas"], 1)

    def test_escrita_atomica_preserva_destino_em_falha(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)
            destino = pasta / "inventario.json"
            destino.write_text('{"anterior":true}\n', encoding="utf-8")
            with mock.patch.object(
                    inventario.json, "dump", side_effect=RuntimeError("fixture")):
                with self.assertRaises(RuntimeError):
                    inventario._escrever_json(str(destino), {"novo": True})
            self.assertEqual(destino.read_text(encoding="utf-8"),
                             '{"anterior":true}\n')
            self.assertEqual({p.name for p in pasta.iterdir()}, {"inventario.json"})

    def test_main_tem_codigos_bloqueantes_e_sempre_gera_json(self):
        with tempfile.TemporaryDirectory(prefix="inventario-i7-") as pasta:
            pasta = Path(pasta)

            def executar(cache, nome):
                saida = pasta / nome
                with contextlib.redirect_stdout(io.StringIO()), \
                        contextlib.redirect_stderr(io.StringIO()):
                    codigo = inventario.main([
                        "--cache", str(cache), "--saida", str(saida),
                    ])
                return codigo, json.loads(saida.read_text(encoding="utf-8"))

            codigo, _ = executar(pasta / "ausente", "ausente.json")
            self.assertEqual(codigo, 2)

            vazio = pasta / "vazio"
            vazio.mkdir()
            codigo, _ = executar(vazio, "vazio.json")
            self.assertEqual(codigo, 3)

            normal = pasta / "normal"
            normal.mkdir()
            (normal / "imagem.jpg").write_bytes(b"ok")
            codigo, dados = executar(normal, "normal.json")
            self.assertEqual(codigo, 0)
            self.assertTrue(dados["cache"]["completo"])

            (normal / "atalho").symlink_to(pasta / "ausente")
            codigo, dados = executar(normal, "link.json")
            self.assertEqual(codigo, 4)
            self.assertEqual(dados["cache"]["links_ignorados"], 1)


if __name__ == "__main__":
    unittest.main()
