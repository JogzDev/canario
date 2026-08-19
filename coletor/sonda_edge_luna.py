#!/usr/bin/env python3
"""A rota paga de visão está DE PÉ? Pergunta ao servidor, sem gastar token.

POR QUE ESTA SONDA OLHA O SERVIDOR, E NÃO O ARQUIVO
===================================================

Entre 14 e 18/08/2026 a Edge Function respondeu `BOOT_ERROR` por quatro dias e
ninguém soube. O app não a chamava (`REMOTE_ANALYSIS_ENABLED` estava `NO`), e o
único teste que existia — `teste_edge_luna.py` — procura texto dentro do
`index.ts` do disco.

O detalhe que decide o desenho desta sonda: **o arquivo do disco estava
íntegro**. 288 linhas, chaves balanceadas, TypeScript válido, nada executando
no topo do módulo. Ele compilava. O que estava quebrado era o *artefato
publicado*, que tinha deixado de ser o arquivo do disco.

Ou seja: compilar a função no CI — que é como o item estava escrito na lista de
pendências, minha inclusive — **não teria pego este bug**. Nenhuma verificação
feita sobre o repositório pegaria, porque o repositório estava certo. A única
pergunta que separa "de pé" de "quebrada" é feita ao servidor.

Custo: zero. Um POST com corpo vazio nunca chega ao modelo; a função recusa
antes, e é justamente a forma da recusa que diz em que estado ela está.
"""

import json
import os
import sys
import urllib.error
import urllib.request


# Os três estados que a função consegue ter, e o que cada um significa para
# quem opera. A ordem importa: só o primeiro é pane.
ESTADOS = {
    "BOOT_ERROR": (
        "PANE",
        "a função NÃO sobe; o artefato publicado está quebrado. "
        "Republique do disco: supabase functions deploy analisar-peca --use-api"),
    "analysis_not_configured": (
        "ESPERADO",
        "sobe e recusa fechado por falta de OPENAI_API_KEY ou "
        "AI_RATE_LIMIT_SALT. É o estado correto enquanto a Luna não entra."),
    "invalid_image": (
        "PRONTA",
        "sobe e os secrets estão cadastrados; recusou só por não ter imagem."),
}


def classificar(codigo, dados):
    """Traduz a resposta em `(estado, gravidade, explicacao)`.

    Separado da rede para poder ser testado sem chamar nada. Resposta que não
    casa com nenhum estado conhecido é tratada como pane, não como "provavelmente
    ok": foi supondo que estava tudo bem que quatro dias passaram.
    """
    marca = ""
    if isinstance(dados, dict):
        marca = str(dados.get("code") or dados.get("error") or "")
    if marca in ESTADOS:
        gravidade, explicacao = ESTADOS[marca]
        return marca, gravidade, explicacao
    if codigo == 401 or codigo == 403:
        return marca or "sem_autorizacao", "PANE", (
            "a chave não foi aceita pelo gateway; a sonda não chegou a ver a "
            "função. Confira SUPABASE_URL e a chave usada.")
    return marca or "resposta_desconhecida", "PANE", (
        "resposta fora dos três estados conhecidos (HTTP {}): {}".format(
            codigo, json.dumps(dados, ensure_ascii=False)[:200]))


def perguntar(url, chave, timeout=45):
    pedido = urllib.request.Request(
        url.rstrip("/") + "/functions/v1/analisar-peca",
        data=b"{}",
        headers={"apikey": chave, "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(pedido, timeout=timeout) as resposta:
            return resposta.status, json.loads(resposta.read() or b"{}")
    except urllib.error.HTTPError as erro:
        bruto = erro.read().decode("utf-8", "ignore")
        try:
            return erro.code, json.loads(bruto)
        except json.JSONDecodeError:
            return erro.code, {"corpo": bruto[:300]}
    except (urllib.error.URLError, TimeoutError, OSError) as erro:
        return 0, {"corpo": "sem resposta: {}".format(erro)}


def main():
    url = os.environ.get("SUPABASE_URL", "").strip()
    # A publishable é a chave natural aqui, porque é a que o app usa. Quando ela
    # não está no ambiente a sonda cai na secreta: para a pergunta "a função
    # sobe?" qualquer chave válida serve, já que BOOT_ERROR acontece antes de a
    # função olhar quem chamou.
    chave = (os.environ.get("SUPABASE_PUBLISHABLE_KEY", "").strip()
             or os.environ.get("SUPABASE_SECRET_KEY", "").strip())
    if not url or not chave:
        print("ERRO: SUPABASE_URL e uma chave do projeto são necessárias.",
              file=sys.stderr)
        return 1
    if not url.startswith("http"):
        url = "https://" + url

    codigo, dados = perguntar(url, chave)
    estado, gravidade, explicacao = classificar(codigo, dados)
    mensagem = "Edge Function analisar-peca: {} — {}".format(estado, explicacao)

    if gravidade == "PANE":
        print("::error title=Rota paga de visão fora do ar::" + mensagem)
        print(mensagem, file=sys.stderr)
        return 1
    if gravidade == "ESPERADO":
        print("::notice title=Rota paga de visão::" + mensagem)
    else:
        print(mensagem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
