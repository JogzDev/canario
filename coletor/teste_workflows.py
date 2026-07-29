"""Valida os workflows do Actions antes de empurrar.

Existe por um erro real: em 28/07 os dois workflows foram empurrados com YAML
invalido e ficaram TRES DIAS sem rodar. A causa foi um `run:` sem aspas com
`: ` no meio do texto ("Saude: relatorio da coleta") -- em YAML isso vira
separador de mapa e quebra o parse.

O sintoma e traicoeiro: o GitHub nao avisa por e-mail, a run aparece com o
CAMINHO do arquivo no lugar do nome, e o cron simplesmente nunca registra.
Coletor nao quebra com erro na tela, quebra em silencio (§20).

Rodar: python3 coletor/teste_workflows.py
"""

import glob
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOWS = os.path.join(RAIZ, ".github", "workflows", "*.yml")


def checar_com_pyyaml(arquivos):
    import yaml
    falhas = []
    for f in arquivos:
        try:
            dados = yaml.safe_load(open(f, encoding="utf-8"))
        except Exception as ex:
            falhas.append((f, str(ex).replace("\n", " ")[:200]))
            continue
        if not isinstance(dados, dict):
            falhas.append((f, "raiz nao e um mapa"))
            continue
        # `on:` vira True em YAML 1.1 (palavra reservada); aceitar os dois.
        if "jobs" not in dados:
            falhas.append((f, "sem a chave `jobs`"))
        if "on" not in dados and True not in dados:
            falhas.append((f, "sem a chave `on`"))
    return falhas


def checar_a_mao(arquivos):
    """Sem pyyaml: pega ao menos o padrao que ja nos mordeu."""
    falhas = []
    for f in arquivos:
        for i, linha in enumerate(open(f, encoding="utf-8"), 1):
            s = linha.strip()
            if "\t" in linha:
                falhas.append((f, "linha {}: TAB (YAML nao aceita)".format(i)))
            if not s.startswith("run:"):
                continue
            valor = s[4:].strip()
            if valor.startswith("|") or valor.startswith(">"):
                continue  # escalar de bloco: seguro
            if valor.startswith('"') and valor.endswith('"'):
                continue
            if ": " in valor:
                falhas.append((f, "linha {}: `run:` sem aspas com ': ' no meio "
                                  "-> {}".format(i, valor[:60])))
    return falhas


def main():
    arquivos = sorted(glob.glob(WORKFLOWS))
    if not arquivos:
        print("Nenhum workflow encontrado.")
        return 1

    try:
        import yaml  # noqa: F401
        falhas = checar_com_pyyaml(arquivos)
        modo = "pyyaml"
    except ImportError:
        falhas = checar_a_mao(arquivos)
        modo = "verificacao manual (pyyaml ausente)"

    for f, erro in falhas:
        print("FALHOU {}: {}".format(os.path.basename(f), erro))
    print("{} workflows checados via {}, {} falhas".format(
        len(arquivos), modo, len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
