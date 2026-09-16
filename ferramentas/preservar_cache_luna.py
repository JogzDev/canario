#!/usr/bin/env python3
"""Preserva e restaura somente o cache JPG da Luna, sem rede nem credenciais.

Saídas são exclusivas: uma falha pode deixar arquivos parciais, mas nunca um
recibo de sucesso. O arquivo TAR é privado, sem compressão nem criptografia.
O hash agregado protege o transporte; o manifesto verifica cada imagem.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile


MAX_FILES = 10_000
MAX_DIRS = 512
MAX_BYTES = 2_050_000_000
MAX_ARCHIVE = 2 ** 31 - 1
MAX_MANIFEST = 4 * 1024 * 1024
CHUNK = 1024 * 1024
SCHEMA = "datadrobe_luna_cache_v1"
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK


class BackupError(ValueError):
    pass


def _fail(message):
    raise BackupError(message)


def _expected(count, size):
    if (type(count) is not int or not 0 < count <= MAX_FILES or
            type(size) is not int or not 0 < size <= MAX_BYTES):
        _fail("Totais esperados fora dos limites.")


def _signature(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode,
            metadata.st_nlink, metadata.st_size, metadata.st_mtime_ns,
            metadata.st_ctime_ns)


def _relative(value):
    if (not isinstance(value, str) or not value or "\\" in value or
            "\x00" in value or len(value.encode("utf-8")) > 240):
        _fail("Nome relativo inválido.")
    parts = value.split("/")
    if len(parts) > 16 or any(p in ("", ".", "..") for p in parts):
        _fail("Caminho fora do cache.")
    if PurePosixPath(value).is_absolute():
        _fail("Caminho absoluto recusado.")
    return value


def _open_root(path):
    before = os.lstat(path)
    if not stat.S_ISDIR(before.st_mode):
        _fail("A raiz deve ser diretório real.")
    fd = os.open(path, DIR_FLAGS)
    try:
        if _signature(before) != _signature(os.fstat(fd)):
            _fail("A raiz mudou durante a abertura.")
    except BaseException:
        os.close(fd)
        raise
    return fd, before


def _scan(rootfd, expected_count, expected_bytes):
    device = os.fstat(rootfd).st_dev
    files, directories = {}, {}
    total = 0

    def visit(fd, prefix):
        nonlocal total
        before = os.fstat(fd)
        if before.st_dev != device:
            _fail("Montagem externa recusada.")
        if len(directories) >= MAX_DIRS:
            _fail("Limite de diretórios excedido.")
        directories[prefix] = _signature(before)
        names = os.listdir(fd)
        if len(names) > MAX_FILES + MAX_DIRS:
            _fail("Limite de entradas excedido.")
        for name in sorted(names):
            relative = _relative(prefix + "/" + name if prefix else name)
            metadata = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if metadata.st_dev != device:
                _fail("Montagem externa recusada.")
            if stat.S_ISDIR(metadata.st_mode):
                child = os.open(name, DIR_FLAGS, dir_fd=fd)
                try:
                    if _signature(metadata) != _signature(os.fstat(child)):
                        _fail("Diretório alterado durante a abertura.")
                    visit(child, relative)
                finally:
                    os.close(child)
            elif stat.S_ISREG(metadata.st_mode):
                if metadata.st_nlink != 1 or not name.endswith(".jpg"):
                    _fail("Somente JPG regulares sem hardlinks são permitidos.")
                if metadata.st_size <= 0:
                    _fail("Imagem vazia recusada.")
                total += metadata.st_size
                files[relative] = _signature(metadata)
                if len(files) > expected_count or total > expected_bytes:
                    _fail("Cache maior que o inventário aprovado.")
            else:
                _fail("Link ou entrada especial recusado.")
        if _signature(before) != _signature(os.fstat(fd)):
            _fail("Diretório alterado durante a leitura.")

    visit(rootfd, "")
    if len(files) != expected_count or total != expected_bytes:
        _fail("Cache diverge do inventário aprovado.")
    return files, directories


def _parent_fd(rootfd, relative):
    parts = _relative(relative).split("/")
    current = os.dup(rootfd)
    try:
        for part in parts[:-1]:
            nextfd = os.open(part, DIR_FLAGS, dir_fd=current)
            os.close(current)
            current = nextfd
        return current, parts[-1]
    except BaseException:
        os.close(current)
        raise


class _HashReader:
    def __init__(self, source):
        self.source = source
        self.digest = hashlib.sha256()
        self.size = 0

    def read(self, size):
        data = self.source.read(size)
        self.digest.update(data)
        self.size += len(data)
        return data


class _BoundedWriter:
    def __init__(self, output):
        self.output = output
        self.size = 0

    def write(self, data):
        if self.size + len(data) > MAX_ARCHIVE:
            _fail("Arquivo excederia o limite de transporte.")
        written = self.output.write(data)
        self.size += written
        return written


def _json_bytes(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True,
                       separators=(",", ":")) + "\n").encode("utf-8")


def _new_json(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(_json_bytes(value))
        output.flush()
        os.fsync(output.fileno())


def _hash_file(path, limit=MAX_ARCHIVE):
    fd = os.open(path, FILE_FLAGS)
    with os.fdopen(fd, "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= limit:
            _fail("Arquivo de entrada inválido ou excessivo.")
        reader = _HashReader(source)
        while reader.read(CHUNK):
            if reader.size > limit:
                _fail("Arquivo de entrada cresceu além do limite.")
        if _signature(before) != _signature(os.fstat(source.fileno())):
            _fail("Arquivo alterado durante a verificação.")
        return reader.digest.hexdigest(), reader.size


def create(cache, output_dir, expected_count, expected_bytes):
    _expected(expected_count, expected_bytes)
    cache = os.path.abspath(cache)
    output_dir = os.path.abspath(output_dir)
    # Impede que a própria saída passe a fazer parte da árvore de origem.
    if os.path.commonpath([os.path.realpath(cache), os.path.realpath(output_dir)]) == os.path.realpath(cache):
        _fail("A saída deve ficar fora do cache.")
    rootfd, original_root = _open_root(cache)
    try:
        files, directories = _scan(rootfd, expected_count, expected_bytes)
        os.mkdir(output_dir, 0o700)
        archive = os.path.join(output_dir, "luna-cache.tar")
        manifest = {"schema": SCHEMA, "count": expected_count,
                    "bytes": expected_bytes,
                    "directories": sorted(p for p in directories if p),
                    "files": []}
        archivefd = os.open(archive, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(archivefd, "wb") as output:
            with tarfile.open(fileobj=_BoundedWriter(output), mode="w|", format=tarfile.USTAR_FORMAT) as bundle:
                for relative in sorted(directories):
                    info = tarfile.TarInfo("cache/" + relative)
                    info.type, info.mode = tarfile.DIRTYPE, 0o700
                    bundle.addfile(info)
                for relative in sorted(files):
                    parentfd, name = _parent_fd(rootfd, relative)
                    try:
                        fd = os.open(name, FILE_FLAGS, dir_fd=parentfd)
                    finally:
                        os.close(parentfd)
                    with os.fdopen(fd, "rb") as source:
                        before = os.fstat(source.fileno())
                        if _signature(before) != files[relative]:
                            _fail("Imagem alterada antes do backup.")
                        reader = _HashReader(source)
                        info = tarfile.TarInfo("cache/" + relative)
                        info.size, info.mode = before.st_size, 0o600
                        bundle.addfile(info, reader)
                        if (reader.size != before.st_size or
                                _signature(before) != _signature(os.fstat(source.fileno()))):
                            _fail("Imagem alterada durante o backup.")
                        manifest["files"].append({"path": relative, "size": reader.size,
                                                   "sha256": reader.digest.hexdigest()})
                if (files, directories) != _scan(rootfd, expected_count, expected_bytes):
                    _fail("Cache alterado durante o backup.")
                if _signature(os.lstat(cache)) != _signature(original_root):
                    _fail("Raiz alterada durante o backup.")
                payload = _json_bytes(manifest)
                if len(payload) > MAX_MANIFEST:
                    _fail("Manifesto excede limite.")
                info = tarfile.TarInfo("manifest.json")
                info.size, info.mode = len(payload), 0o600
                bundle.addfile(info, io.BytesIO(payload))
            output.flush()
            os.fsync(output.fileno())
        digest, archive_size = _hash_file(archive)
        receipt = {"schema": SCHEMA, "count": expected_count,
                   "bytes": expected_bytes, "directories": len(directories),
                   "archive_bytes": archive_size, "archive_sha256": digest}
        _new_json(os.path.join(output_dir, "receipt.json"), receipt)
        return receipt
    finally:
        os.close(rootfd)


def _read_receipt(path, expected_count, expected_bytes):
    fd = os.open(path, FILE_FLAGS)
    with os.fdopen(fd, "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            _fail("Recibo deve ser arquivo regular.")
        data = source.read(16_385)
    if len(data) > 16_384:
        _fail("Recibo excede limite.")
    receipt = json.loads(data)
    if (not isinstance(receipt, dict) or receipt.get("schema") != SCHEMA or
            receipt.get("count") != expected_count or receipt.get("bytes") != expected_bytes or
            not re.fullmatch(r"[0-9a-f]{64}", str(receipt.get("archive_sha256", "")))):
        _fail("Recibo inválido ou divergente.")
    return receipt


def _validate_manifest(manifest, expected_count, expected_bytes):
    if (not isinstance(manifest, dict) or set(manifest) != {"schema", "count", "bytes", "directories", "files"} or
            manifest["schema"] != SCHEMA or manifest["count"] != expected_count or
            manifest["bytes"] != expected_bytes or not isinstance(manifest["files"], list) or
            len(manifest["files"]) != expected_count or not isinstance(manifest["directories"], list) or
            len(manifest["directories"]) >= MAX_DIRS):
        _fail("Manifesto inválido.")
    dirs = [_relative(p) for p in manifest["directories"]]
    if len(set(dirs)) != len(dirs):
        _fail("Diretórios duplicados.")
    files, total = {}, 0
    for item in manifest["files"]:
        if not isinstance(item, dict) or set(item) != {"path", "size", "sha256"}:
            _fail("Entrada inválida no manifesto.")
        relative = _relative(item["path"])
        if (not relative.endswith(".jpg") or relative in files or relative in dirs or
                type(item["size"]) is not int or item["size"] <= 0 or
                not re.fullmatch(r"[0-9a-f]{64}", str(item["sha256"]))):
            _fail("Entrada de imagem inválida.")
        files[relative] = item
        total += item["size"]
        if total > expected_bytes:
            _fail("Manifesto excede limite aprovado.")
    for path in list(files) + dirs:
        parents = list(PurePosixPath(path).parents)[:-1]
        if any(str(parent) not in dirs for parent in parents):
            _fail("Diretório pai ausente no manifesto.")
    if total != expected_bytes:
        _fail("Total do manifesto divergente.")
    return files, dirs


def restore(archive, receipt_path, destination, verification, expected_count, expected_bytes):
    _expected(expected_count, expected_bytes)
    if os.path.lexists(destination) or os.path.lexists(verification):
        _fail("Destino ou verificação já existe.")
    receipt = _read_receipt(receipt_path, expected_count, expected_bytes)
    digest, size = _hash_file(archive)
    if digest != receipt["archive_sha256"] or size != receipt.get("archive_bytes"):
        _fail("Hash ou tamanho do arquivo não confere.")
    fd = os.open(archive, FILE_FLAGS)
    with os.fdopen(fd, "rb") as source:
        original_archive = os.fstat(source.fileno())
        # A entrada pode ter sido trocada entre o hash e a abertura: recalcular
        # no mesmo descritor que será usado na extração fecha essa janela.
        reader = _HashReader(source)
        while reader.read(CHUNK):
            if reader.size > MAX_ARCHIVE:
                _fail("Arquivo excede limite.")
        if reader.digest.hexdigest() != digest or reader.size != size:
            _fail("Arquivo trocado depois da verificação.")
        source.seek(0)
        with tarfile.open(fileobj=source, mode="r:") as bundle:
            members = {}
            total = 0
            for member in bundle:
                if len(members) >= MAX_FILES + MAX_DIRS + 1:
                    _fail("TAR com entradas demais.")
                name = member.name
                if name != "cache":
                    _relative(name)
                if name in members or member.pax_headers or not (member.isfile() or member.isdir()):
                    _fail("Entrada TAR duplicada, estendida ou especial.")
                if member.isdir() and member.size != 0:
                    _fail("Diretório TAR com conteúdo.")
                if member.isfile():
                    total += member.size
                    if member.size < 0 or total > expected_bytes + MAX_MANIFEST:
                        _fail("TAR excede limite aprovado.")
                members[name] = member
            manifest_member = members.get("manifest.json")
            if not manifest_member or not manifest_member.isfile() or manifest_member.size > MAX_MANIFEST:
                _fail("Manifesto ausente ou excessivo.")
            manifest = json.loads(bundle.extractfile(manifest_member).read(MAX_MANIFEST + 1))
            files, dirs = _validate_manifest(manifest, expected_count, expected_bytes)
            expected_names = {"cache", "manifest.json"} | {"cache/" + p for p in files} | {"cache/" + p for p in dirs}
            if set(members) != expected_names or not members["cache"].isdir():
                _fail("TAR tem entrada ausente ou não declarada.")
            if any(not members["cache/" + p].isdir() for p in dirs):
                _fail("Tipo de diretório divergente.")
            if any(not members["cache/" + p].isfile() or members["cache/" + p].size != item["size"] for p, item in files.items()):
                _fail("Tipo ou tamanho da imagem divergente.")
            os.mkdir(destination, 0o700)
            rootfd, rootmeta = _open_root(destination)
            try:
                for directory in sorted(dirs, key=lambda p: (p.count("/"), p)):
                    parentfd, name = _parent_fd(rootfd, directory)
                    try:
                        os.mkdir(name, 0o700, dir_fd=parentfd)
                    finally:
                        os.close(parentfd)
                for relative, item in files.items():
                    parentfd, name = _parent_fd(rootfd, relative)
                    try:
                        outfd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parentfd)
                    finally:
                        os.close(parentfd)
                    with os.fdopen(outfd, "wb") as output:
                        reader = _HashReader(bundle.extractfile(members["cache/" + relative]))
                        while True:
                            data = reader.read(min(CHUNK, item["size"] - reader.size + 1))
                            if not data:
                                break
                            if reader.size > item["size"]:
                                _fail("Imagem ultrapassa tamanho declarado.")
                            output.write(data)
                        if reader.size != item["size"] or reader.digest.hexdigest() != item["sha256"]:
                            _fail("Imagem restaurada diverge do manifesto.")
                        output.flush()
                        os.fsync(output.fileno())
                restored, restored_dirs = _scan(rootfd, expected_count, expected_bytes)
                if set(restored) != set(files) or set(restored_dirs) != set(dirs) | {""}:
                    _fail("Árvore restaurada divergente.")
                if os.stat(destination, follow_symlinks=False).st_ino != rootmeta.st_ino:
                    _fail("Destino foi trocado durante a restauração.")
            finally:
                os.close(rootfd)
        if _signature(original_archive) != _signature(os.fstat(source.fileno())):
            _fail("Arquivo alterado durante a restauração.")
    result = {"schema": SCHEMA, "verified": True, "count": expected_count,
              "bytes": expected_bytes, "directories": len(dirs) + 1,
              "archive_sha256": digest}
    _new_json(verification, result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create_parser = commands.add_parser("create")
    create_parser.add_argument("--cache", required=True)
    create_parser.add_argument("--output-dir", required=True)
    restore_parser = commands.add_parser("restore")
    restore_parser.add_argument("--archive", required=True)
    restore_parser.add_argument("--receipt", required=True)
    restore_parser.add_argument("--destination", required=True)
    restore_parser.add_argument("--verification", required=True)
    for subparser in (create_parser, restore_parser):
        subparser.add_argument("--expected-count", type=int, required=True)
        subparser.add_argument("--expected-bytes", type=int, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "create":
            result = create(args.cache, args.output_dir, args.expected_count, args.expected_bytes)
        else:
            result = restore(args.archive, args.receipt, args.destination, args.verification, args.expected_count, args.expected_bytes)
    except (BackupError, OSError, tarfile.TarError, json.JSONDecodeError) as error:
        # Nunca registra caminhos de exceções do SO nem conteúdo da origem.
        print("Preservação falhou: " + (str(error) if isinstance(error, BackupError) else type(error).__name__), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
