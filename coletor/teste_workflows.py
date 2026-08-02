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
    carregados = {}
    for f in arquivos:
        try:
            with open(f, encoding="utf-8") as entrada:
                dados = yaml.safe_load(entrada)
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
        carregados[os.path.basename(f)] = dados

    falhas.extend(checar_orquestracao(carregados))
    return falhas


def checar_orquestracao(workflows):
    """Impede cron concorrente e regressão na ordem coleta -> saúde -> motor."""
    falhas = []

    def falhar(arquivo, mensagem):
        falhas.append((os.path.join(os.path.dirname(WORKFLOWS), arquivo),
                       mensagem))

    individuais = {
        "coleta.yml": "./.github/workflows/coleta.yml",
        "coleta-shopify.yml": "./.github/workflows/coleta-shopify.yml",
        "coleta-editorial.yml": "./.github/workflows/coleta-editorial.yml",
        "coleta-trends.yml": "./.github/workflows/coleta-trends.yml",
        "motor.yml": "./.github/workflows/motor.yml",
    }
    for arquivo in individuais:
        dados = workflows.get(arquivo, {})
        gatilhos = dados.get("on", dados.get(True, {})) or {}
        if "workflow_call" not in gatilhos:
            falhar(arquivo, "workflow individual sem `workflow_call`")
        if "schedule" in gatilhos:
            falhar(arquivo, "workflow individual voltou a ter cron proprio")

    pipeline = workflows.get("pipeline-diario.yml", {})
    gatilhos = pipeline.get("on", pipeline.get(True, {})) or {}
    if "schedule" not in gatilhos:
        falhar("pipeline-diario.yml", "pipeline unico sem `schedule`")

    jobs = pipeline.get("jobs", {})
    cadeia = {
        "varejo-vtex": (None, individuais["coleta.yml"]),
        "varejo-shopify": ("varejo-vtex", individuais["coleta-shopify.yml"]),
        "editorial": ("varejo-shopify", individuais["coleta-editorial.yml"]),
        "busca": ("editorial", individuais["coleta-trends.yml"]),
        "motor": ("saude", individuais["motor.yml"]),
    }
    for job, (dependencia, reutilizavel) in cadeia.items():
        definicao = jobs.get(job, {})
        if definicao.get("uses") != reutilizavel:
            falhar("pipeline-diario.yml",
                   "job `{}` nao chama `{}`".format(job, reutilizavel))
        if definicao.get("needs") != dependencia:
            falhar("pipeline-diario.yml",
                   "job `{}` deveria depender de `{}`".format(
                       job, dependencia))

    saude = jobs.get("saude", {})
    if set(saude.get("needs", [])) != {
            "varejo-vtex", "varejo-shopify", "editorial", "busca"}:
        falhar("pipeline-diario.yml",
               "saude deve observar as quatro coletas")
    if "always()" not in str(saude.get("if", "")):
        falhar("pipeline-diario.yml",
               "saude deve rodar mesmo quando uma coleta falhar")

    passos = saude.get("steps", [])
    ids = {p.get("id"): p for p in passos if p.get("id")}
    if not {"portao", "dependencias"}.issubset(ids):
        falhar("pipeline-diario.yml",
               "saude nao valida dados e resultado dos jobs")

    motor = workflows.get("motor.yml", {}).get("jobs", {}).get(
        "computar", {})
    comandos = [str(p.get("run", "")) for p in motor.get("steps", [])]
    atributos = [i for i, comando in enumerate(comandos)
                 if "motor_atributos.py" in comando]
    legado = [comando for comando in comandos
              if "motor_computar.py" in comando]
    backfill = [i for i, comando in enumerate(comandos)
                if "backfill_editorial.py" in comando]
    if len(atributos) != 1 or legado:
        falhar("motor.yml",
               "workflow deve ter uma unica publicacao atomica do motor")
    if backfill and atributos and backfill[0] > atributos[0]:
        falhar("motor.yml", "backfill deve acontecer antes da publicacao")
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
