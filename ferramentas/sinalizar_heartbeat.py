#!/usr/bin/env python3
"""Confirma a um observador externo que o pipeline terminou de verdade.

O sinal só é enviado depois de publicação, capacidade e isolamento passarem.
Se o evento ``schedule`` nem nascer, este arquivo não roda e o observador
externo percebe a ausência. O URL é uma credencial: nunca é impresso.
"""

import os
import re
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit


HOST_PERMITIDO = "uptime.betterstack.com"
PREFIXO_PERMITIDO = "/api/v1/heartbeat/"
TOKEN = re.compile(r"^[A-Za-z0-9_-]{16,}$")


def validar_url(valor):
    """Aceita somente o endpoint de heartbeat escolhido, sempre por HTTPS."""
    valor = (valor or "").strip()
    partes = urlsplit(valor)
    token = partes.path.removeprefix(PREFIXO_PERMITIDO)
    if (partes.scheme != "https" or partes.hostname != HOST_PERMITIDO
            or partes.username or partes.password
            or partes.port not in (None, 443)
            or not partes.path.startswith(PREFIXO_PERMITIDO)
            or not TOKEN.fullmatch(token)
            or partes.query or partes.fragment):
        raise ValueError(
            "PIPELINE_HEARTBEAT_URL nao e um heartbeat HTTPS valido do "
            "Better Stack")
    return valor


def enviar(url, abrir=urllib.request.urlopen, tentativas=3, esperar=time.sleep):
    """Envia o sinal com retry curto sem jamais incluir o URL nos erros."""
    url = validar_url(url)
    pedido = urllib.request.Request(
        url,
        headers={"User-Agent": "datadrobe-pipeline-heartbeat/1.0"},
        method="GET")
    ultimo = "erro de rede"
    for tentativa in range(tentativas):
        try:
            with abrir(pedido, timeout=30) as resposta:
                status = getattr(resposta, "status", resposta.getcode())
                if 200 <= status < 300:
                    return status
                ultimo = "HTTP {}".format(status)
                if status not in (429,) and status < 500:
                    break
        except urllib.error.HTTPError as erro:
            ultimo = "HTTP {}".format(erro.code)
            if erro.code not in (429,) and erro.code < 500:
                break
        except (urllib.error.URLError, TimeoutError, OSError):
            ultimo = "erro de rede"
        if tentativa + 1 < tentativas:
            esperar(2 ** tentativa)
    raise RuntimeError(
        "heartbeat externo nao confirmou o recebimento ({})".format(ultimo))


def main():
    url = os.environ.get("PIPELINE_HEARTBEAT_URL", "")
    if not url.strip():
        print("ERRO: secret PIPELINE_HEARTBEAT_URL ausente.", file=sys.stderr)
        return 1
    try:
        status = enviar(url)
    except (ValueError, RuntimeError) as erro:
        print("ERRO: {}".format(erro), file=sys.stderr)
        return 1
    print("Heartbeat externo confirmado (HTTP {}).".format(status))
    return 0


if __name__ == "__main__":
    sys.exit(main())
