#!/usr/bin/env python3
"""Contrato offline do upload restrito, sem token real e sem acesso à rede."""

import copy
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.parse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ferramentas"))
import enviar_snapshot_luna as uploader


class GitHubFake:
    def __init__(self):
        self.repo = {"full_name": uploader.REPOSITORIO, "private": True}
        self.release = {
            "id": uploader.RELEASE_ID, "draft": True, "prerelease": True,
            "tag_name": uploader.TAG, "target_commitish": uploader.REFERENCIA,
            "upload_url": ("https://uploads.github.com/repos/{}/releases/{}/assets"
                           "{{?name,label}}".format(uploader.REPOSITORIO,
                                                   uploader.RELEASE_ID)),
            "assets": [],
        }
        self.calls = []
        self.uploads = []
        self.response_override = {}

    def __call__(self, token, host, method, path, body=None, tamanho=None):
        if token != "fake-local-token":
            raise AssertionError("Somente credencial fictícia permitida no teste")
        self.calls.append((host, method, path))
        prefix = "/repos/" + uploader.REPOSITORIO
        if (host, method, path) == ("api.github.com", "GET", prefix):
            return copy.deepcopy(self.repo)
        release_path = prefix + "/releases/" + str(uploader.RELEASE_ID)
        if (host, method, path) == ("api.github.com", "GET", release_path):
            return copy.deepcopy(self.release)
        parsed = urllib.parse.urlsplit(path)
        if (host, method, parsed.path) != ("uploads.github.com", "POST", release_path + "/assets"):
            raise AssertionError("Operação fora do destino e métodos permitidos")
        query = urllib.parse.parse_qs(parsed.query, strict_parsing=True)
        if set(query) != {"name"} or len(query["name"]) != 1:
            raise AssertionError("Query inesperada")
        content = body.read()
        if tamanho != len(content):
            raise AssertionError("Content-Length divergente")
        name = query["name"][0]
        self.uploads.append((name, content))
        response = {"id": 100 + len(self.uploads), "state": "uploaded", "name": name,
                    "size": len(content),
                    "digest": "sha256:" + hashlib.sha256(content).hexdigest()}
        response.update(self.response_override)
        return response


class EnviarSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="luna-upload-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.content = {"luna-cache.tar": b"snapshot-test-only", "receipt.json": b'{"test":true}\n'}
        for name, content in self.content.items():
            (self.root / name).write_bytes(content)
        self.github = GitHubFake()

    def send(self):
        return uploader.enviar(self.root, "123", "2", "fake-local-token",
                               requisicao=self.github)

    def test_envia_exatamente_dois_assets_com_nomes_fixos_hash_e_destino_privado(self):
        (self.root / "secret-unrelated.txt").write_bytes(b"never-upload")
        result = self.send()
        self.assertEqual(self.github.uploads, [
            ("luna-i7-123-2-luna-cache.tar", self.content["luna-cache.tar"]),
            ("luna-i7-123-2-receipt.json", self.content["receipt.json"]),
        ])
        self.assertEqual([method for _, method, _ in self.github.calls],
                         ["GET", "GET", "POST", "POST"])
        self.assertEqual(result["repository"], uploader.REPOSITORIO)
        self.assertEqual(result["release_id"], uploader.RELEASE_ID)
        self.assertTrue(result["draft"])
        self.assertFalse(result["restauracao_verificada"])
        for asset, (_, content) in zip(result["assets"], self.github.uploads):
            self.assertEqual(asset["sha256"], hashlib.sha256(content).hexdigest())
            self.assertEqual(asset["size"], len(content))

    def test_repositorio_publico_ou_diferente_impede_todo_upload(self):
        for change in ({"private": False}, {"private": 1}, {"full_name": "Other/project"}):
            with self.subTest(change=change):
                self.github = GitHubFake()
                self.github.repo.update(change)
                with self.assertRaises(uploader.FalhaSnapshot):
                    self.send()
                self.assertFalse(self.github.uploads)

    def test_release_publicada_tag_referencia_id_ou_upload_host_divergentes_sao_rejeitados(self):
        changes = [{"draft": False}, {"prerelease": False},
                   {"draft": 1}, {"prerelease": 1},
                   {"id": uploader.RELEASE_ID + 1}, {"tag_name": "other-tag"},
                   {"target_commitish": "main"},
                   {"upload_url": "https://example.com/upload"}]
        for change in changes:
            with self.subTest(change=change):
                self.github = GitHubFake()
                self.github.release.update(change)
                with self.assertRaises(uploader.FalhaSnapshot):
                    self.send()
                self.assertFalse(self.github.uploads)

    def test_duplicata_em_qualquer_dos_dois_assets_impede_upload_e_sobrescrita(self):
        for name in self.content:
            with self.subTest(name=name):
                self.github = GitHubFake()
                self.github.release["assets"] = [{"name": "luna-i7-123-2-" + name}]
                with self.assertRaises(uploader.FalhaSnapshot):
                    self.send()
                self.assertFalse(self.github.uploads,
                                 "Preflight deve verificar ambos os nomes antes do primeiro POST")

    def test_hash_tamanho_estado_ou_nome_remoto_divergente_nao_confirmam_upload(self):
        changes = [{"digest": "sha256:" + "0" * 64}, {"digest": None},
                   {"size": 999}, {"state": "new"}, {"name": "unexpected.tar"}]
        for change in changes:
            with self.subTest(change=change):
                self.github = GitHubFake()
                self.github.response_override = change
                with self.assertRaises(uploader.FalhaSnapshot):
                    self.send()
                self.assertEqual(len(self.github.uploads), 1)

    def test_identidade_de_execucao_nao_pode_injetar_caminho_ou_nome(self):
        for run_id, attempt in [("../123", "2"), ("123", "2?other=x"), ("", "2")]:
            with self.subTest(run_id=run_id, attempt=attempt):
                with self.assertRaises(uploader.FalhaSnapshot):
                    uploader.enviar(self.root, run_id, attempt, "fake-local-token",
                                    requisicao=self.github)
                self.assertFalse(self.github.calls)

    def test_recibo_local_ausente_impede_envio_do_tar(self):
        (self.root / "receipt.json").unlink()
        with self.assertRaises(OSError):
            self.send()
        self.assertFalse(self.github.uploads,
                         "Preflight deve abrir ambos os arquivos antes do primeiro POST")

    def test_symlink_local_e_recusado_sem_upload(self):
        archive = self.root / "luna-cache.tar"
        archive.unlink()
        archive.symlink_to(self.root / "receipt.json")
        with self.assertRaises(OSError):
            self.send()
        self.assertFalse(self.github.uploads)

    def test_fifo_local_e_recusado_sem_bloquear(self):
        archive = self.root / "luna-cache.tar"
        archive.unlink()
        os.mkfifo(archive)
        # Subprocesso impõe limite real; sem O_NONBLOCK abrir FIFO aguardaria
        # indefinidamente. O fake nunca acessa rede, inclusive neste processo.
        code = (
            "import sys; sys.path.insert(0, sys.argv[1]); "
            "from teste_enviar_snapshot_luna import GitHubFake, uploader; "
            "uploader.enviar(sys.argv[2], '123', '2', 'fake-local-token', requisicao=GitHubFake())"
        )
        try:
            result = subprocess.run([sys.executable, "-c", code,
                                     str(Path(__file__).resolve().parent), str(self.root)],
                                    capture_output=True, timeout=2,
                                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        except subprocess.TimeoutExpired:
            self.fail("FIFO bloqueou a abertura; uploader precisa de O_NONBLOCK")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"FalhaSnapshot", result.stderr)


if __name__ == "__main__":
    unittest.main()
