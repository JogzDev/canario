#!/usr/bin/env python3
"""Abre, atualiza e fecha UMA issue por incidente do pipeline.

POR QUE ISSUE, E NAO E-MAIL OU SLACK
====================================

Entre 14 e 18/08/2026 o pipeline falhou cinco execucoes seguidas e a Edge
Function ficou quatro dias fora do ar. Ninguem soube de nenhum dos dois. Nao
havia canal: o unico lugar onde a falha aparecia era a lista de execucoes do
Actions, que so quem abre ve.

Issue do proprio repositorio resolve isso sem servico externo, sem secret novo e
sem custo: o GitHub ja notifica o dono do repositorio por e-mail e push. O token
do Actions basta.

O QUE FAZ ISTO SER ALERTA E NAO RUIDO
=====================================

Alarme que dispara todo dia deixa de ser lido em uma semana, e ai o projeto fica
pior do que sem alarme nenhum -- o proprio portao de saude ja aprendeu isso em
10/08, quando derrubava o pipeline inteiro porque uma loja teve um dia ruim.

Tres regras:

1. **Uma issue por incidente, nao por noite.** Se ja ha uma aberta, a falha de
   hoje vira comentario nela. Cinco noites vermelhas geram uma issue com cinco
   comentarios, nao cinco issues.
2. **Fecha sozinha quando volta o verde.** Isso e o que transforma a issue num
   indicador de estado: issue aberta significa "esta quebrado agora". Sem isso
   ela vira lixo que alguem fecha na mao meses depois.
3. **Verde sem incidente aberto nao faz nada.** Nenhuma notificacao por dia bom.
"""

import json
import os
import sys
import urllib.error
import urllib.request


ROTULO = "pipeline-vermelho"


def decidir(estado, issue_aberta):
    """Decide a acao sem tocar na rede, para poder ser testada.

    Devolve `"abrir"`, `"comentar"`, `"fechar"` ou `"nada"`.
    """
    if estado == "vermelho":
        return "comentar" if issue_aberta else "abrir"
    if estado == "verde":
        return "fechar" if issue_aberta else "nada"
    raise ValueError("estado deve ser 'vermelho' ou 'verde', veio {!r}".format(
        estado))


class Github:
    def __init__(self, repositorio, token):
        self.base = "https://api.github.com/repos/{}".format(repositorio)
        self.token = token

    def _pedir(self, metodo, caminho, corpo=None):
        pedido = urllib.request.Request(
            self.base + caminho,
            data=json.dumps(corpo).encode() if corpo is not None else None,
            headers={
                "Authorization": "Bearer {}".format(self.token),
                "Accept": "application/vnd.github+json",
                "Content-Type": "application/json",
                "User-Agent": "datadrobe-alertar",
            },
            method=metodo)
        with urllib.request.urlopen(pedido, timeout=30) as resposta:
            bruto = resposta.read()
            return json.loads(bruto) if bruto else {}

    def issue_aberta(self):
        achadas = self._pedir(
            "GET", "/issues?state=open&labels={}&per_page=1".format(ROTULO))
        # A API de issues devolve pull requests junto; PR nunca e alerta nosso.
        for item in achadas:
            if "pull_request" not in item:
                return item
        return None

    def abrir(self, titulo, corpo):
        return self._pedir("POST", "/issues", {
            "title": titulo, "body": corpo, "labels": [ROTULO]})

    def comentar(self, numero, corpo):
        return self._pedir(
            "POST", "/issues/{}/comments".format(numero), {"body": corpo})

    def fechar(self, numero, corpo):
        self.comentar(numero, corpo)
        return self._pedir("PATCH", "/issues/{}".format(numero),
                           {"state": "closed", "state_reason": "completed"})


def corpo_da_falha(execucao, workflow, quem_falhou):
    linhas = [
        "O **{}** falhou.".format(workflow),
        "",
        "| | |",
        "|---|---|",
        "| Execução | {} |".format(execucao or "—"),
        "| Jobs que falharam | {} |".format(quem_falhou or "—"),
        "",
        "Enquanto esta issue estiver aberta, o pipeline está quebrado. "
        "Ela fecha sozinha na primeira execução verde.",
        "",
        "Onde olhar primeiro:",
        "",
        "- `SAUDE.md` no repositório — o relatório da última coleta que rodou",
        "- `python3 coletor/verificar_capacidade_banco.py` — banco cheio "
        "bloqueia escrita e derruba a coleta",
        "- `python3 ferramentas/testar_edge_luna.py --so-contrato` — se a "
        "suspeita for a rota paga de visão",
    ]
    return "\n".join(linhas)


def main():
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    repositorio = os.environ.get("GITHUB_REPOSITORY", "").strip()
    estado = os.environ.get("ESTADO_DO_PIPELINE", "").strip().lower()
    if not token or not repositorio:
        print("ERRO: GITHUB_TOKEN e GITHUB_REPOSITORY sao necessarios.",
              file=sys.stderr)
        return 1

    try:
        acao = decidir(estado, None)  # valida o estado antes de chamar a rede
    except ValueError as erro:
        print("ERRO: {}".format(erro), file=sys.stderr)
        return 1

    workflow = os.environ.get("GITHUB_WORKFLOW", "pipeline")
    execucao = "{}/actions/runs/{}".format(
        os.environ.get("GITHUB_SERVER_URL", "https://github.com")
        + "/" + repositorio,
        os.environ.get("GITHUB_RUN_ID", ""))
    quem_falhou = os.environ.get("JOBS_QUE_FALHARAM", "").strip()

    api = Github(repositorio, token)
    try:
        aberta = api.issue_aberta()
        acao = decidir(estado, aberta)
        if acao == "abrir":
            criada = api.abrir(
                "Pipeline vermelho — {}".format(workflow),
                corpo_da_falha(execucao, workflow, quem_falhou))
            print("Alerta aberto: issue #{}".format(criada.get("number")))
        elif acao == "comentar":
            api.comentar(
                aberta["number"],
                "Falhou de novo.\n\n" + corpo_da_falha(
                    execucao, workflow, quem_falhou))
            print("Alerta ja aberto (#{}); falha registrada como comentario."
                  .format(aberta["number"]))
        elif acao == "fechar":
            api.fechar(
                aberta["number"],
                "Voltou ao verde em {}.\n\nFechando automaticamente."
                .format(execucao))
            print("Pipeline verde; issue #{} fechada.".format(
                aberta["number"]))
        else:
            print("Pipeline verde e nenhum incidente aberto; nada a fazer.")
    except (urllib.error.HTTPError, urllib.error.URLError, OSError,
            KeyError, ValueError) as erro:
        # Alerta que derruba a run que ele deveria vigiar e pior que alerta
        # nenhum: o vermelho verdadeiro fica escondido atras do erro do alerta.
        print("::warning title=Alerta nao pode ser publicado::{}".format(erro))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
