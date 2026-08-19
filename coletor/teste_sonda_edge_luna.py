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

    # Chave recusada NAO e "funcao quebrada", e a distincao custou uma execucao
    # vermelha de verdade: na primeira noite da sonda, em 19/08, a chave secreta
    # foi recusada pelo gateway e a mensagem original mandava procurar apagao na
    # funcao -- que estava de pe o tempo todo. Alarme que aponta para o lugar
    # errado e como se ensina a ignorar alarme.
    for codigo in (401, 403):
        estado, gravidade, texto = classificar(
            codigo, {"message": "Invalid API key"})
        if gravidade != "SONDA_SEM_CHAVE":
            print("FALHOU: chave recusada ({}) foi confundida com pane da "
                  "funcao".format(codigo))
            return 1
        if "NÃO chegou a ver" not in texto:
            print("FALHOU: mensagem nao deixa claro que a funcao nao foi vista")
            return 1
        if "SUPABASE_PUBLISHABLE_KEY" not in texto:
            print("FALHOU: mensagem nao diz o que fazer para consertar")
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
