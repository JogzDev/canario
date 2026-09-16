#!/usr/bin/env python3
"""Inventário agregado de um cache legado antes de devolver o computador.

O artefato é intencionalmente incapaz de listar nomes, caminhos internos,
conteúdo, hashes individuais, configurações ou credenciais. Links simbólicos
nunca são seguidos. Assim ele mede o que precisa ser preservado sem transformar
o inventário em uma cópia acidental do host ou do dataset.
"""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time


MAX_ENTRADAS = 1_000_000
MAX_SEGUNDOS = 10 * 60
EXTENSOES_DE_IMAGEM = frozenset({
    ".avif", ".gif", ".heic", ".jpeg", ".jpg", ".png", ".webp",
})


def _iso(timestamp):
    return dt.datetime.fromtimestamp(
        timestamp, tz=dt.timezone.utc).isoformat()


def inventariar(cache, clock=None, max_entradas=MAX_ENTRADAS,
                max_segundos=MAX_SEGUNDOS):
    """Devolve medidas agregadas usando descritores e sem seguir links."""
    clock = clock or time.monotonic
    iniciado = clock()
    raiz = Path(cache)
    resultado = {
        "estado": "ausente",
        "completo": False,
        "motivo_incompleto": "cache_ausente",
        "arquivos_regulares": 0,
        "diretorios": 0,
        "bytes_regulares": 0,
        "links_ignorados": 0,
        "montagens_ignoradas": 0,
        "entradas_especiais_ignoradas": 0,
        "erros_de_leitura": 0,
        "extensoes": {},
        "arquivo_mais_antigo_em": None,
        "arquivo_mais_recente_em": None,
    }
    try:
        estado_raiz = raiz.lstat()
    except FileNotFoundError:
        return resultado
    except OSError:
        resultado["estado"] = "inacessivel"
        resultado["motivo_incompleto"] = "raiz_inacessivel"
        resultado["erros_de_leitura"] = 1
        return resultado

    if stat.S_ISLNK(estado_raiz.st_mode):
        resultado["estado"] = "link_ignorado"
        resultado["motivo_incompleto"] = "raiz_link_simbolico"
        resultado["links_ignorados"] = 1
        return resultado
    if not stat.S_ISDIR(estado_raiz.st_mode):
        resultado["estado"] = "nao_e_diretorio"
        resultado["motivo_incompleto"] = "raiz_nao_e_diretorio"
        return resultado

    flags = os.O_RDONLY
    flags |= getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descritor_raiz = os.open(str(raiz), flags)
    except OSError:
        resultado["estado"] = "inacessivel"
        resultado["motivo_incompleto"] = "raiz_inacessivel_ou_trocada"
        resultado["erros_de_leitura"] = 1
        return resultado

    resultado["estado"] = "diretorio"
    resultado["motivo_incompleto"] = None
    extensoes = {}
    mais_antigo = mais_recente = None
    entradas_vistas = 0
    interromper = False

    def falha_de_leitura(_erro):
        resultado["erros_de_leitura"] += 1
        resultado["motivo_incompleto"] = "erro_de_leitura"

    try:
        raiz_aberta = os.fstat(descritor_raiz)
        if (not stat.S_ISDIR(raiz_aberta.st_mode) or
                (raiz_aberta.st_dev, raiz_aberta.st_ino) !=
                (estado_raiz.st_dev, estado_raiz.st_ino)):
            # O_NOFOLLOW impede um link no último componente, mas não a troca
            # por outro diretório regular entre lstat e open.
            resultado["estado"] = "inacessivel"
            resultado["motivo_incompleto"] = "raiz_trocada"
            resultado["erros_de_leitura"] = 1
            return resultado
        dispositivo_da_raiz = raiz_aberta.st_dev
        for _caminho, diretorios, arquivos, dirfd in os.fwalk(
                ".", topdown=True, onerror=falha_de_leitura,
                follow_symlinks=False, dir_fd=descritor_raiz):
            resultado["diretorios"] += 1
            for nome in list(diretorios):
                entradas_vistas += 1
                if entradas_vistas > max_entradas:
                    resultado["motivo_incompleto"] = "limite_de_entradas"
                    diretorios[:] = []
                    interromper = True
                    break
                if clock() - iniciado > max_segundos:
                    resultado["motivo_incompleto"] = "limite_de_tempo"
                    diretorios[:] = []
                    interromper = True
                    break
                try:
                    metadado = os.stat(
                        nome, dir_fd=dirfd, follow_symlinks=False)
                except OSError:
                    resultado["erros_de_leitura"] += 1
                    resultado["motivo_incompleto"] = "erro_de_leitura"
                    diretorios.remove(nome)
                    continue
                if stat.S_ISLNK(metadado.st_mode):
                    resultado["links_ignorados"] += 1
                    diretorios.remove(nome)
                elif not stat.S_ISDIR(metadado.st_mode):
                    resultado["entradas_especiais_ignoradas"] += 1
                    diretorios.remove(nome)
                elif metadado.st_dev != dispositivo_da_raiz:
                    resultado["montagens_ignoradas"] += 1
                    diretorios.remove(nome)
            if interromper:
                break

            for nome in arquivos:
                entradas_vistas += 1
                if entradas_vistas > max_entradas:
                    resultado["motivo_incompleto"] = "limite_de_entradas"
                    diretorios[:] = []
                    interromper = True
                    break
                if clock() - iniciado > max_segundos:
                    resultado["motivo_incompleto"] = "limite_de_tempo"
                    diretorios[:] = []
                    interromper = True
                    break
                try:
                    metadado = os.stat(
                        nome, dir_fd=dirfd, follow_symlinks=False)
                except OSError:
                    resultado["erros_de_leitura"] += 1
                    resultado["motivo_incompleto"] = "erro_de_leitura"
                    continue
                modo = metadado.st_mode
                if stat.S_ISLNK(modo):
                    resultado["links_ignorados"] += 1
                elif stat.S_ISREG(modo):
                    resultado["arquivos_regulares"] += 1
                    resultado["bytes_regulares"] += metadado.st_size
                    extensao = Path(nome).suffix.lower()
                    if not extensao:
                        extensao = "[sem_extensao]"
                    elif extensao not in EXTENSOES_DE_IMAGEM:
                        extensao = "[outra]"
                    extensoes[extensao] = extensoes.get(extensao, 0) + 1
                    mais_antigo = (metadado.st_mtime if mais_antigo is None else
                                    min(mais_antigo, metadado.st_mtime))
                    mais_recente = (metadado.st_mtime if mais_recente is None else
                                    max(mais_recente, metadado.st_mtime))
                else:
                    resultado["entradas_especiais_ignoradas"] += 1
            if interromper:
                break
    except OSError:
        resultado["erros_de_leitura"] += 1
        resultado["motivo_incompleto"] = "erro_de_varredura"
    finally:
        os.close(descritor_raiz)

    resultado["extensoes"] = dict(sorted(extensoes.items()))
    if mais_antigo is not None:
        try:
            resultado["arquivo_mais_antigo_em"] = _iso(mais_antigo)
            resultado["arquivo_mais_recente_em"] = _iso(mais_recente)
        except (OSError, OverflowError, ValueError):
            resultado["erros_de_leitura"] += 1
            resultado["motivo_incompleto"] = "timestamp_invalido"
    if not interromper and resultado["erros_de_leitura"] == 0:
        resultado["completo"] = True
        resultado["motivo_incompleto"] = None
    return resultado


def gerar(cache, referencia_do_workflow=None, agora=None):
    agora = agora or dt.datetime.now(dt.timezone.utc)
    retorno = {
        "schema": "datadrobe_legacy_cache_inventory_v1",
        "gerado_em": agora.astimezone(dt.timezone.utc).isoformat(),
        "cache": inventariar(cache),
    }
    # O SHA liga o artefato à execução, mas não descreve o host nem o checkout.
    if referencia_do_workflow:
        retorno["referencia_do_workflow"] = referencia_do_workflow
    return retorno


def _escrever_json(caminho, dados):
    pasta = os.path.dirname(os.path.abspath(caminho))
    if not os.path.isdir(pasta):
        raise ValueError("diretório de saída inexistente")
    descritor, temporario = tempfile.mkstemp(
        prefix=".inventario-i7-", suffix=".tmp", dir=pasta, text=True)
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo, ensure_ascii=True, indent=2, sort_keys=True)
            arquivo.write("\n")
            arquivo.flush()
            os.fsync(arquivo.fileno())
        os.replace(temporario, caminho)
    except BaseException:
        try:
            os.unlink(temporario)
        except FileNotFoundError:
            pass
        raise


def main(argv=None):
    argumentos = argparse.ArgumentParser(
        description="Inventário agregado e sem conteúdo de cache legado.")
    argumentos.add_argument("--cache", required=True)
    argumentos.add_argument("--saida", required=True)
    argumentos.add_argument("--referencia-do-workflow")
    opcoes = argumentos.parse_args(argv)
    dados = gerar(opcoes.cache, opcoes.referencia_do_workflow)
    _escrever_json(opcoes.saida, dados)
    cache = dados["cache"]
    print("Inventário concluído: {} arquivos, {} bytes, estado {}.".format(
        cache["arquivos_regulares"], cache["bytes_regulares"], cache["estado"]))
    if cache["estado"] != "diretorio":
        print("Inventário bloqueante: cache esperado não é um diretório legível.",
              file=sys.stderr)
        return 2
    if cache["arquivos_regulares"] == 0:
        print("Inventário bloqueante: cache esperado está vazio.", file=sys.stderr)
        return 3
    if (not cache["completo"] or cache["erros_de_leitura"] or
            cache["links_ignorados"] or
            cache["montagens_ignoradas"] or
            cache["entradas_especiais_ignoradas"]):
        print("Inventário bloqueante: há entradas que não puderam ser preservadas "
              "pela leitura agregada.", file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
