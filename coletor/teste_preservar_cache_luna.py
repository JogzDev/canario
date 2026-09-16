#!/usr/bin/env python3
"""Prova offline de preservação, integridade e extração confinada do cache."""

import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ferramentas"))
import preservar_cache_luna as backup


class PreservarCacheTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="luna-backup-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        (self.cache / "marca").mkdir()
        (self.cache / "vazia").mkdir()
        self.contents = {"a.jpg": b"\xff\xd8first-image\xff\xd9",
                         "marca/b.jpg": b"\xff\xd8second-image\xff\xd9"}
        for relative, content in self.contents.items():
            (self.cache / relative).write_bytes(content)
        self.count = len(self.contents)
        self.size = sum(map(len, self.contents.values()))
        self.output = self.root / "snapshot"
        self.destination = self.root / "restored"
        self.verification = self.root / "verified.json"

    def create(self):
        return backup.create(self.cache, self.output, self.count, self.size)

    def restore(self):
        return backup.restore(self.output / "luna-cache.tar",
                              self.output / "receipt.json", self.destination,
                              self.verification, self.count, self.size)

    def rewrite_archive(self, mutate):
        """Cria corrupção com hash de transporte válido para testar o manifesto."""
        archive = self.output / "luna-cache.tar"
        with tarfile.open(archive, "r:") as bundle:
            entries = [(info, bundle.extractfile(info).read() if info.isfile() else None)
                       for info in bundle]
        mutate(entries)
        with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as bundle:
            for info, content in entries:
                if content is not None:
                    info.size = len(content)
                bundle.addfile(info, io.BytesIO(content) if content is not None else None)
        receipt_path = self.output / "receipt.json"
        receipt = json.loads(receipt_path.read_text())
        payload = archive.read_bytes()
        receipt.update(archive_sha256=hashlib.sha256(payload).hexdigest(),
                       archive_bytes=len(payload))
        receipt_path.write_text(json.dumps(receipt))

    def test_round_trip_preserva_bytes_diretorios_e_verifica_cada_imagem(self):
        receipt = self.create()
        result = self.restore()
        self.assertTrue(result["verified"])
        self.assertEqual(result["archive_sha256"], receipt["archive_sha256"])
        self.assertEqual(result["count"], self.count)
        self.assertEqual(result["bytes"], self.size)
        self.assertEqual(result["directories"], 3)
        self.assertTrue((self.destination / "vazia").is_dir())
        for relative, content in self.contents.items():
            self.assertEqual((self.destination / relative).read_bytes(), content)
        self.assertEqual(json.loads(self.verification.read_text()), result)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.verification.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.output / "luna-cache.tar").stat().st_mode & 0o777, 0o600)

    def test_inventario_divergente_e_limites_nao_criam_recibo(self):
        for count, size in [(0, self.size), (True, self.size),
                            (backup.MAX_FILES + 1, self.size),
                            (self.count, backup.MAX_BYTES + 1),
                            (self.count + 1, self.size),
                            (self.count, self.size + 1)]:
            with self.subTest(count=count, size=size):
                with self.assertRaises(backup.BackupError):
                    backup.create(self.cache, self.output, count, size)
                self.assertFalse(self.output.exists())
        with mock.patch.object(backup, "MAX_DIRS", 2):
            with self.assertRaises(backup.BackupError):
                self.create()

    def test_nomes_absolutos_traversal_vazios_e_profundidade_sao_rejeitados(self):
        invalid = ["/outside.jpg", "../outside.jpg", "a/../b.jpg", "a//b.jpg",
                   "a/./b.jpg", "a\\b.jpg", "a\x00b.jpg", "", "x" * 241,
                   "/".join(["a"] * 17)]
        for relative in invalid:
            with self.subTest(relative=relative):
                with self.assertRaises(backup.BackupError):
                    backup._relative(relative)

    def test_saida_existente_ou_dentro_da_origem_e_preservada(self):
        for destination in [self.cache / "snapshot", self.cache]:
            with self.assertRaises(backup.BackupError):
                backup.create(self.cache, destination, self.count, self.size)
        self.output.mkdir()
        sentinel = self.output / "existing.txt"
        sentinel.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            self.create()
        self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_links_hardlinks_fifo_nao_jpg_e_imagem_vazia_falham_fechado(self):
        extra = self.cache / "unexpected.jpg"
        outside = self.root / "outside.jpg"
        outside.write_bytes(b"external")
        cases = [lambda: extra.symlink_to(outside),
                 lambda: extra.symlink_to(self.root, target_is_directory=True),
                 lambda: os.link(self.cache / "a.jpg", extra),
                 lambda: os.mkfifo(extra), lambda: extra.write_bytes(b"")]
        for make in cases:
            make()
            try:
                with self.assertRaises(backup.BackupError):
                    self.create()
                self.assertFalse(self.output.exists())
            finally:
                extra.unlink()
        extra = self.cache / "secret.json"
        extra.write_bytes(b"not-image")
        with self.assertRaises(backup.BackupError):
            self.create()
        self.assertFalse(self.output.exists())
        self.assertEqual(outside.read_bytes(), b"external")

    def test_raiz_link_e_troca_da_raiz_durante_backup_nao_geram_recibo(self):
        link = self.root / "cache-link"
        link.symlink_to(self.cache, target_is_directory=True)
        with self.assertRaises(backup.BackupError):
            backup.create(link, self.output, self.count, self.size)
        original_scan = backup._scan
        calls = 0

        def swap_after_scan(*args, **kwargs):
            nonlocal calls
            result = original_scan(*args, **kwargs)
            calls += 1
            if calls == 2:
                self.cache.rename(self.root / "original-cache")
                self.cache.mkdir()
            return result

        with mock.patch.object(backup, "_scan", side_effect=swap_after_scan):
            with self.assertRaises(backup.BackupError):
                self.create()
        self.assertFalse((self.output / "receipt.json").exists())
        self.assertEqual((self.root / "original-cache/a.jpg").read_bytes(),
                         self.contents["a.jpg"])

    def test_modificacao_de_imagem_durante_backup_impede_recibo(self):
        original_addfile = backup.tarfile.TarFile.addfile
        altered = False

        def mutate_after_read(bundle, info, fileobj=None):
            nonlocal altered
            result = original_addfile(bundle, info, fileobj)
            if info.name == "cache/a.jpg" and not altered:
                altered = True
                (self.cache / "a.jpg").write_bytes(b"changed")
            return result

        with mock.patch.object(backup.tarfile.TarFile, "addfile", new=mutate_after_read):
            with self.assertRaises(backup.BackupError):
                self.create()
        self.assertTrue(altered)
        self.assertFalse((self.output / "receipt.json").exists())

    def test_hash_de_transporte_e_truncamento_impedem_extracao(self):
        self.create()
        archive = self.output / "luna-cache.tar"
        original = archive.read_bytes()
        for damaged in [original[:-1], b"X" + original[1:]]:
            with self.subTest(length=len(damaged)):
                archive.write_bytes(damaged)
                with self.assertRaises(backup.BackupError):
                    self.restore()
                self.assertFalse(self.destination.exists())
                self.assertFalse(self.verification.exists())

    def test_limite_do_tar_interrompe_escrita_sem_recibo_de_sucesso(self):
        with mock.patch.object(backup, "MAX_ARCHIVE", 1024):
            with self.assertRaisesRegex(backup.BackupError, "transporte"):
                self.create()
        self.assertFalse((self.output / "receipt.json").exists())
        self.assertLessEqual((self.output / "luna-cache.tar").stat().st_size, 1024)

    def test_troca_da_raiz_restaurada_impede_verificacao_de_sucesso(self):
        self.create()
        original_scan = backup._scan

        def swap_after_scan(*args, **kwargs):
            result = original_scan(*args, **kwargs)
            self.destination.rename(self.root / "restored-original")
            self.destination.mkdir()
            return result

        with mock.patch.object(backup, "_scan", side_effect=swap_after_scan):
            with self.assertRaisesRegex(backup.BackupError, "Destino foi trocado"):
                self.restore()
        self.assertFalse(self.verification.exists())
        self.assertEqual((self.root / "restored-original/a.jpg").read_bytes(),
                         self.contents["a.jpg"])

    def test_hash_individual_detecta_imagem_corrompida_mesmo_com_recibo_atualizado(self):
        self.create()

        def corrupt(entries):
            for index, (info, content) in enumerate(entries):
                if info.name == "cache/a.jpg":
                    entries[index] = (info, b"X" + content[1:])

        self.rewrite_archive(corrupt)
        with self.assertRaisesRegex(backup.BackupError, "manifesto"):
            self.restore()
        self.assertFalse(self.verification.exists())

    def test_arquivo_trocado_entre_hash_e_abertura_e_rejeitado(self):
        self.create()
        original_hash = backup._hash_file

        def replace_after_hash(path, *args, **kwargs):
            result = original_hash(path, *args, **kwargs)
            archive = Path(path)
            data = archive.read_bytes()
            archive.write_bytes(b"X" + data[1:])
            return result

        with mock.patch.object(backup, "_hash_file", side_effect=replace_after_hash):
            with self.assertRaisesRegex(backup.BackupError, "trocado"):
                self.restore()
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.verification.exists())

    def test_entradas_tar_traversal_symlink_duplicada_ou_nao_declarada_sao_rejeitadas(self):
        cases = [("../escaped.jpg", tarfile.REGTYPE),
                 ("/escaped.jpg", tarfile.REGTYPE),
                 ("cache/linked.jpg", tarfile.SYMTYPE),
                 ("cache/hard.jpg", tarfile.LNKTYPE),
                 ("cache/a.jpg", tarfile.REGTYPE),
                 ("cache/undeclared.jpg", tarfile.REGTYPE)]
        self.create()
        original_archive = (self.output / "luna-cache.tar").read_bytes()
        original_receipt = (self.output / "receipt.json").read_bytes()
        for name, kind in cases:
            with self.subTest(name=name, kind=kind):
                (self.output / "luna-cache.tar").write_bytes(original_archive)
                (self.output / "receipt.json").write_bytes(original_receipt)

                def append_entry(entries):
                    info = tarfile.TarInfo(name)
                    info.type = kind
                    info.linkname = "../../outside.jpg" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
                    entries.append((info, b"x" if kind == tarfile.REGTYPE else None))

                self.rewrite_archive(append_entry)
                with self.assertRaises(backup.BackupError):
                    self.restore()
                self.assertFalse(self.destination.exists())
                self.assertFalse(self.verification.exists())
                self.assertFalse((self.root / "escaped.jpg").exists())

    def test_destino_e_recibo_de_verificacao_existentes_nunca_sao_sobrescritos(self):
        self.create()
        self.destination.mkdir()
        sentinel = self.destination / "existing"
        sentinel.write_bytes(b"keep")
        with self.assertRaises(backup.BackupError):
            self.restore()
        self.assertEqual(sentinel.read_bytes(), b"keep")
        self.destination = self.root / "another-destination"
        self.verification.write_bytes(b"previous")
        with self.assertRaises(backup.BackupError):
            self.restore()
        self.assertEqual(self.verification.read_bytes(), b"previous")
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
