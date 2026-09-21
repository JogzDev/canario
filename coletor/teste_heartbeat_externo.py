#!/usr/bin/env python3
"""O watchdog externo não pode vazar o token nem aceitar exfiltração."""

import os
import sys
import urllib.error
from copy import deepcopy
from pathlib import Path

import yaml

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ferramentas"))

from sinalizar_heartbeat import enviar, validar_url  # noqa: E402
from teste_workflows import checar_heartbeat_externo  # noqa: E402


URL = "https://uptime.betterstack.com/api/v1/heartbeat/abcdefghijklmnop"


class Resposta:
    status = 204

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def getcode(self):
        return self.status


def main():
    if validar_url(URL) != URL:
        print("FALHOU: URL valida foi alterada")
        return 1

    ruins = [
        "http://uptime.betterstack.com/api/v1/heartbeat/abcdefghijklmnop",
        "https://exemplo.invalid/api/v1/heartbeat/abcdefghijklmnop",
        "https://uptime.betterstack.com/api/v1/heartbeat/curto",
        URL + "?token=vazado",
        "https://usuario:senha@uptime.betterstack.com/api/v1/heartbeat/abcdefghijklmnop",
    ]
    for ruim in ruins:
        try:
            validar_url(ruim)
        except ValueError:
            continue
        print("FALHOU: destino inseguro foi aceito")
        return 1

    chamadas = []

    def abrir_ok(pedido, timeout):
        chamadas.append((pedido.full_url, timeout))
        return Resposta()

    if enviar(URL, abrir=abrir_ok, esperar=lambda _: None) != 204:
        print("FALHOU: resposta 2xx nao confirmou o heartbeat")
        return 1
    if chamadas != [(URL, 30)]:
        print("FALHOU: envio nao foi unico ou perdeu timeout")
        return 1

    segredo = "segredo-que-nao-pode-aparecer"
    url_secreta = (
        "https://uptime.betterstack.com/api/v1/heartbeat/" + segredo)
    tentativas = []

    def abrir_falha(pedido, timeout):
        tentativas.append(timeout)
        raise urllib.error.HTTPError(
            pedido.full_url, 503, "temporario", {}, None)

    try:
        enviar(url_secreta, abrir=abrir_falha, tentativas=2,
               esperar=lambda _: None)
    except RuntimeError as erro:
        if segredo in str(erro) or len(tentativas) != 2:
            print("FALHOU: retry vazou a credencial ou nao repetiu")
            return 1
    else:
        print("FALHOU: HTTP 503 foi tratado como sucesso")
        return 1

    caminho = (Path(__file__).resolve().parents[1]
               / ".github/workflows/pipeline-diario.yml")
    original = yaml.safe_load(caminho.read_text(encoding="utf-8"))["jobs"]
    if checar_heartbeat_externo(original):
        print("FALHOU: contrato do workflow original e invalido")
        return 1

    def sinal(jobs):
        return next(p for p in jobs["heartbeat-externo"]["steps"]
                    if "sinalizar_heartbeat.py" in p.get("run", ""))

    def alerta(jobs):
        return next(p["env"] for p in jobs["alerta"]["steps"]
                    if "ESTADO_DO_PIPELINE" in p.get("env", {}))

    mutacoes = [
        lambda j: j.pop("heartbeat-externo"),
        lambda j: j["heartbeat-externo"].update(needs="publicacao"),
        lambda j: j["heartbeat-externo"].update({"if": "${{ success() }}"}),
        lambda j: sinal(j).update({"continue-on-error": True}),
        lambda j: sinal(j)["env"].update(PIPELINE_HEARTBEAT_URL="literal"),
        lambda j: j["alerta"]["needs"].remove("heartbeat-externo"),
        lambda j: alerta(j).update(ESTADO_DO_PIPELINE="verde"),
        lambda j: alerta(j).update(JOBS_QUE_FALHARAM="motor=success"),
    ]
    for indice, mutar in enumerate(mutacoes, 1):
        jobs = deepcopy(original)
        mutar(jobs)
        if not checar_heartbeat_externo(jobs):
            print("FALHOU: mutacao estrutural {} passou".format(indice))
            return 1

    print("Heartbeat externo: destino, token, schedule e ordem protegidos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
