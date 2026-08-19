#!/usr/bin/env python3
"""A sonda da rota paga classifica os estados certos, sem tocar na rede."""

import sys

from sonda_edge_luna import classificar


def main():
    # Pane real de 14 a 18/08/2026: a função não subia e ninguém soube.
    estado, gravidade, _ = classificar(500, {"code": "BOOT_ERROR"})
    if estado != "BOOT_ERROR" or gravidade != "PANE":
        print("FALHOU: BOOT_ERROR nao foi tratado como pane")
        return 1

    # Estado correto enquanto a Luna não entra: de pé e recusando fechado.
    estado, gravidade, _ = classificar(503, {"code": "analysis_not_configured"})
    if estado != "analysis_not_configured" or gravidade != "ESPERADO":
        print("FALHOU: recusa fechada virou pane e vai gerar alarme falso")
        return 1

    # De pé com secrets cadastrados.
    _, gravidade, _ = classificar(400, {"code": "invalid_image"})
    if gravidade != "PRONTA":
        print("FALHOU: funcao saudavel nao foi reconhecida")
        return 1

    # O ponto do desenho: desconhecido é PANE, nunca "provavelmente ok".
    # Supor que estava tudo bem foi o que deixou quatro dias passarem.
    for codigo, corpo in ((200, {"ok": True}), (0, {"corpo": "sem resposta"}),
                          (502, {}), (500, {"corpo": "<html>502</html>"})):
        _, gravidade, _ = classificar(codigo, corpo)
        if gravidade != "PANE":
            print("FALHOU: resposta desconhecida ({}, {}) passou como sadia"
                  .format(codigo, corpo))
            return 1

    # Chave recusada não é "função quebrada", mas também não pode passar calada:
    # a sonda não chegou a ver a função, então não sabe nada.
    estado, gravidade, texto = classificar(401, {"message": "Invalid API key"})
    if gravidade != "PANE" or "gateway" not in texto:
        print("FALHOU: chave recusada nao foi distinguida")
        return 1

    # Resposta que não é dicionário não pode derrubar a sonda.
    _, gravidade, _ = classificar(500, None)
    if gravidade != "PANE":
        print("FALHOU: corpo nao-dicionario quebrou a classificacao")
        return 1

    print("Sonda da Edge Function: pane, recusa fechada, pronta e desconhecido")
    return 0


if __name__ == "__main__":
    sys.exit(main())
