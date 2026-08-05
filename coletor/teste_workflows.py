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

    motor_pipeline = jobs.get("motor", {})
    condicao_motor_pipeline = str(motor_pipeline.get("if", ""))
    if ("always()" not in condicao_motor_pipeline or
            "needs.saude.result == 'success'" not in condicao_motor_pipeline):
        falhar("pipeline-diario.yml",
               "motor deve ignorar recuperacoes ancestrais puladas")

    saude_inicial = jobs.get("saude-inicial", {})
    if set(saude_inicial.get("needs", [])) != {
            "varejo-vtex", "varejo-shopify", "editorial", "busca"}:
        falhar("pipeline-diario.yml",
               "saude inicial deve observar as quatro coletas")
    if "always()" not in str(saude_inicial.get("if", "")):
        falhar("pipeline-diario.yml",
               "saude inicial deve rodar mesmo quando uma coleta falhar")

    passos = saude_inicial.get("steps", [])
    ids = {p.get("id"): p for p in passos if p.get("id")}
    if not {"portao", "dependencias", "resultado"}.issubset(ids):
        falhar("pipeline-diario.yml",
               "saude inicial nao expoe dados e resultado dos jobs")

    recuperar_shopify = jobs.get("recuperar-shopify", {})
    if (recuperar_shopify.get("needs") != "saude-inicial" or
            recuperar_shopify.get("uses") != individuais["coleta-shopify.yml"]):
        falhar("pipeline-diario.yml",
               "recuperacao Shopify deve depender da saude inicial")
    recuperar_busca = jobs.get("recuperar-busca", {})
    if (set(recuperar_busca.get("needs", [])) != {
            "saude-inicial", "recuperar-shopify"} or
            recuperar_busca.get("uses") != individuais["coleta-trends.yml"] or
            recuperar_busca.get("with", {}).get("tentativa") != 1):
        falhar("pipeline-diario.yml",
               "recuperacao Trends deve usar outra rotacao apos Shopify")

    saude = jobs.get("saude", {})
    if set(saude.get("needs", [])) != {
            "saude-inicial", "recuperar-shopify", "recuperar-busca"}:
        falhar("pipeline-diario.yml",
               "saude final deve aguardar todas as recuperacoes")
    if "always()" not in str(saude.get("if", "")):
        falhar("pipeline-diario.yml",
               "saude final deve rodar mesmo com recuperacao falha")
    ids_finais = {p.get("id") for p in saude.get("steps", []) if p.get("id")}
    if "portao" not in ids_finais:
        falhar("pipeline-diario.yml", "saude final ficou sem portao")

    recuperacao = workflows.get("recuperar-pipeline.yml", {})
    gatilhos_recuperacao = recuperacao.get(
        "on", recuperacao.get(True, {})) or {}
    if "workflow_dispatch" not in gatilhos_recuperacao:
        falhar("recuperar-pipeline.yml", "recuperacao sem disparo manual")
    if "schedule" in gatilhos_recuperacao:
        falhar("recuperar-pipeline.yml", "recuperacao manual ganhou cron")
    jobs_recuperacao = recuperacao.get("jobs", {})
    entrada_recuperacao = gatilhos_recuperacao.get("workflow_dispatch") or {}
    if "somente_validar" not in entrada_recuperacao.get("inputs", {}):
        falhar("recuperar-pipeline.yml",
               "recuperacao sem modo de reaproveitar coletas concluidas")
    if jobs_recuperacao.get("recuperar-shopify", {}).get(
            "uses") != individuais["coleta-shopify.yml"]:
        falhar("recuperar-pipeline.yml", "recuperacao nao chama Shopify")
    busca_recuperacao = jobs_recuperacao.get("recuperar-busca", {})
    if (busca_recuperacao.get("needs") != "recuperar-shopify" or
            busca_recuperacao.get("uses") != individuais["coleta-trends.yml"] or
            busca_recuperacao.get("with", {}).get("tentativa") != 1):
        falhar("recuperar-pipeline.yml", "recuperacao nao rotaciona Trends")
    motor_recuperacao = jobs_recuperacao.get("motor", {})
    if motor_recuperacao.get("needs") != "saude":
        falhar("recuperar-pipeline.yml", "motor manual contorna saude")
    condicao_motor_recuperacao = str(motor_recuperacao.get("if", ""))
    if ("always()" not in condicao_motor_recuperacao or
            "needs.saude.result == 'success'" not in condicao_motor_recuperacao):
        falhar("recuperar-pipeline.yml",
               "motor manual herda jobs pulados e nao publica")
    passos_saude_recuperacao = jobs_recuperacao.get("saude", {}).get(
        "steps", [])
    dependencia_recuperacao = next((p for p in passos_saude_recuperacao
                                    if p.get("id") == "dependencias"), {})
    if "somente_validar" not in str(dependencia_recuperacao.get("if", "")):
        falhar("recuperar-pipeline.yml",
               "modo somente validar ainda exige jobs pulados")

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

    sonda = workflows.get("sonda.yml", {}).get("jobs", {}).get("sondar", {})
    passos_sonda = sonda.get("steps", [])
    publicadores = [p for p in passos_sonda
                    if "commitar.sh" in str(p.get("run", ""))]
    if len(publicadores) != 1 or "github.ref_name == 'main'" not in str(
            publicadores[0].get("if", "") if publicadores else ""):
        falhar("sonda.yml",
               "sonda so pode commitar relatorio na branch main")

    acao = os.path.join(RAIZ, ".github", "actions", "python-mac",
                        "action.yml")
    try:
        texto_acao = open(acao, encoding="utf-8").read()
    except OSError as ex:
        falhas.append((acao, "acao local ilegivel: {}".format(ex)))
    else:
        checksum = "dc3174666a30f4c38d04e79a80c3159b4b3aa69597c4676701c8386696811611"
        exigencias = [checksum, "shasum -a 256 -c -", "--proto '=https'",
                      "--tlsv1.2"]
        for trecho in exigencias:
            if trecho not in texto_acao:
                falhas.append((acao,
                               "Python portatil sem protecao `{}`".format(
                                   trecho)))
        if texto_acao.find("shasum -a 256 -c -") > texto_acao.find("tar xzf"):
            falhas.append((acao, "tarball e extraido antes de validar SHA-256"))
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


def checar_actions_fixadas(arquivos):
    """Código externo com segredo só pode entrar por commit imutável."""
    falhas = []
    padrao = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
    for arquivo in arquivos:
        for numero, linha in enumerate(open(arquivo, encoding="utf-8"), 1):
            achado = padrao.match(linha)
            if not achado:
                continue
            referencia = achado.group(1)
            if referencia.startswith("./"):
                continue
            if not re.search(r"@[0-9a-f]{40}$", referencia):
                falhas.append((
                    arquivo,
                    "linha {}: action externa sem SHA completo: {}".format(
                        numero, referencia)))
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

    falhas.extend(checar_actions_fixadas(arquivos))

    for f, erro in falhas:
        print("FALHOU {}: {}".format(os.path.basename(f), erro))
    print("{} workflows checados via {}, {} falhas".format(
        len(arquivos), modo, len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
