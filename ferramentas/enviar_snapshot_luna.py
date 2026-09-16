#!/usr/bin/env python3
"""Envia somente um snapshot Luna para o rascunho privado já autorizado.

O rascunho é criado previamente pelo proprietário; este programa não cria,
publica, edita ou apaga releases. O token do job vive apenas no ambiente.
"""

import argparse
from contextlib import ExitStack
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import stat
import sys
import urllib.parse

REPOSITORIO = "JogzDev/canario"
RELEASE_ID = 390176961
TAG = "snapshot-luna-i7-2026-09-16-23024bc"
REFERENCIA = "23024bc9a1178cd1030846137c64ecbcd747a215"
MAX_ASSET = 2 * 1024 ** 3
MAX_JSON = 1024 * 1024
NOMES_ASSETS = ("luna-cache.tar", "receipt.json")


class FalhaSnapshot(Exception):
    pass


def _headers(token):
    return {
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "DataDrobe-snapshot-preservation",
    }


def _requisicao(token, host, metodo, caminho, body=None, tamanho=None):
    conexao = http.client.HTTPSConnection(host, timeout=120)
    headers = _headers(token)
    if tamanho is not None:
        headers["Content-Length"] = str(tamanho)
        headers["Content-Type"] = "application/octet-stream"
    try:
        conexao.request(metodo, caminho, body=body, headers=headers)
        resposta = conexao.getresponse()
        dados = resposta.read(MAX_JSON + 1)
        if resposta.status not in {200, 201}:
            raise FalhaSnapshot("GitHub respondeu HTTP {}".format(resposta.status))
        if len(dados) > MAX_JSON:
            raise FalhaSnapshot("resposta de controle acima do limite")
        return json.loads(dados)
    finally:
        conexao.close()


def _validar_destino(repo, release):
    if repo.get("full_name") != REPOSITORIO or repo.get("private") is not True:
        raise FalhaSnapshot("destino precisa continuar sendo o repositório privado")
    esperado = {
        "id": RELEASE_ID, "draft": True, "prerelease": True,
        "tag_name": TAG, "target_commitish": REFERENCIA,
    }
    if any(type(release.get(chave)) is not type(valor) or release.get(chave) != valor
           for chave, valor in esperado.items()):
        raise FalhaSnapshot("rascunho diverge do destino autorizado")
    upload_esperado = ("https://uploads.github.com/repos/{}/releases/{}/assets"
                       "{{?name,label}}".format(REPOSITORIO, RELEASE_ID))
    if release.get("upload_url") != upload_esperado:
        raise FalhaSnapshot("origem de upload inesperada")


def _medir_aberto(arquivo):
    anterior = os.fstat(arquivo.fileno())
    if not stat.S_ISREG(anterior.st_mode) or not 0 < anterior.st_size < MAX_ASSET:
        raise FalhaSnapshot("asset ausente, não regular ou fora do limite de 2 GiB")
    hash_arquivo = hashlib.sha256()
    lidos = 0
    for bloco in iter(lambda: arquivo.read(1024 * 1024), b""):
        lidos += len(bloco)
        if lidos > anterior.st_size:
            raise FalhaSnapshot("asset cresceu durante cálculo de integridade")
        hash_arquivo.update(bloco)
    posterior = os.fstat(arquivo.fileno())
    if _identidade(anterior) != _identidade(posterior):
        raise FalhaSnapshot("asset mudou durante cálculo de integridade")
    arquivo.seek(0)
    return anterior, hash_arquivo.hexdigest()


def _identidade(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def enviar(pasta, run_id, tentativa, token, requisicao=_requisicao):
    if not re.fullmatch(r"[0-9]+", run_id) or not re.fullmatch(r"[0-9]+", tentativa):
        raise FalhaSnapshot("identidade de execução inválida")
    prefixo = "/repos/" + REPOSITORIO
    repo = requisicao(token, "api.github.com", "GET", prefixo)
    release = requisicao(token, "api.github.com", "GET",
                         prefixo + "/releases/" + str(RELEASE_ID))
    _validar_destino(repo, release)
    assets_existentes = {asset.get("name") for asset in release.get("assets", [])}
    nomes_remotos = {nome: "luna-i7-{}-{}-{}".format(run_id, tentativa, nome)
                     for nome in NOMES_ASSETS}
    if assets_existentes.intersection(nomes_remotos.values()):
        raise FalhaSnapshot("asset já existe; sobrescrita não é permitida")
    enviados = []
    with ExitStack() as abertos:
        preparados = []
        # Valida os dois assets antes de enviar qualquer um. Descritores ficam
        # abertos até o fim para não reabrir caminhos que possam ter sido trocados.
        for nome in NOMES_ASSETS:
            caminho_local = Path(pasta) / nome
            fd = os.open(str(caminho_local), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            arquivo = abertos.enter_context(os.fdopen(fd, "rb"))
            info, digest = _medir_aberto(arquivo)
            preparados.append((nomes_remotos[nome], arquivo, info, digest))
        for nome_remoto, arquivo, info, digest in preparados:
            if _identidade(info) != _identidade(os.fstat(arquivo.fileno())):
                raise FalhaSnapshot("asset mudou antes do upload")
            caminho_upload = (prefixo + "/releases/" + str(RELEASE_ID) +
                               "/assets?" + urllib.parse.urlencode({"name": nome_remoto}))
            resposta = requisicao(token, "uploads.github.com", "POST", caminho_upload,
                                   body=arquivo, tamanho=info.st_size)
            if _identidade(info) != _identidade(os.fstat(arquivo.fileno())):
                raise FalhaSnapshot("asset mudou durante upload; restauração obrigatória")
            if (resposta.get("state") != "uploaded" or
                    resposta.get("name") != nome_remoto or
                    resposta.get("size") != info.st_size or
                    resposta.get("digest") != "sha256:" + digest):
                raise FalhaSnapshot("GitHub não confirmou tamanho e hash do asset")
            enviados.append({"id": resposta["id"], "name": nome_remoto,
                             "size": info.st_size, "sha256": digest})
    return {"schema": "datadrobe_luna_snapshot_upload_v1", "repository": REPOSITORIO,
            "release_id": RELEASE_ID, "draft": True, "assets": enviados,
            "restauracao_verificada": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args(argv)
    token = os.environ.get("GH_TOKEN")
    if not token:
        print("Token efêmero do job ausente.", file=sys.stderr)
        return 2
    try:
        dados = enviar(args.output_dir, args.run_id, args.attempt, token)
        with open(args.receipt, "x", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo, indent=2, sort_keys=True)
            arquivo.write("\n")
    except (FalhaSnapshot, OSError, ValueError, http.client.HTTPException):
        print("Upload não confirmado. Conferir rascunho e execução; "
              "nenhum asset é sobrescrito automaticamente.", file=sys.stderr)
        return 1
    print("Dois assets privados confirmados por tamanho e SHA-256. "
          "Restauração ainda obrigatória.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
