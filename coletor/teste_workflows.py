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
import copy
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
    # Os defeitos plantados ficam apenas em memoria. Verifica que este
    # proprio portao rejeita as regressoes que ja passaram despercebidas.
    pipeline = carregados.get("pipeline-diario.yml", {})
    if not checar_capacidade_da_recuperacao(pipeline):
        for mutacao in ("sem_always", "sem_capacidade", "saida_sem_outcome",
                        "sem_medicao", "sem_json", "sem_cancelamento"):
            copia = copy.deepcopy(pipeline)
            jobs = copia["jobs"]
            if mutacao == "sem_always":
                jobs["recuperar-shopify"]["if"] = jobs["recuperar-shopify"]["if"].replace("always()", "true")
            elif mutacao == "sem_capacidade":
                jobs["recuperar-shopify"]["if"] = jobs["recuperar-shopify"]["if"].replace("capacidade_permite_escrita == 'true'", "capacidade_permite_escrita != 'false'")
            elif mutacao == "saida_sem_outcome":
                jobs["saude-inicial"]["outputs"]["capacidade_permite_escrita"] = "${{ steps.capacidade.outputs.escrita_permitida }}"
            elif mutacao == "sem_cancelamento":
                jobs["recuperar-shopify"]["if"] = jobs["recuperar-shopify"]["if"].replace("!cancelled()", "true")
            else:
                passo = next(p for p in jobs["saude-inicial"]["steps"]
                             if p.get("id") == "capacidade")
                if mutacao == "sem_medicao":
                    passo["run"] = "echo escrita_permitida=true"
                else:
                    passo["run"] = passo["run"].replace("--json", "")
            if not checar_capacidade_da_recuperacao(copia):
                falhas.append(("pipeline-diario.yml",
                               "verificador aceitou defeito plantado: " + mutacao))

    sonda = carregados.get("sondar-origem-gerenciada.yml", {})
    if not checar_sonda_origem_gerenciada(sonda):
        for mutacao in ("cron", "runner_pessoal", "permissao_escrita", "segredo",
                        "passo_extra", "comando_anexado"):
            copia = copy.deepcopy(sonda)
            if mutacao == "cron":
                _gatilhos(copia)["schedule"] = [{"cron": "0 0 * * *"}]
            elif mutacao == "runner_pessoal":
                copia["jobs"]["sondar"]["runs-on"] = ["self-hosted", "macOS"]
            elif mutacao == "permissao_escrita":
                copia["permissions"]["contents"] = "write"
            elif mutacao == "segredo":
                copia["jobs"]["sondar"]["env"] = {
                    "TOKEN": "${{ secrets.SUPABASE_SECRET_KEY }}"}
            elif mutacao == "passo_extra":
                copia["jobs"]["sondar"]["steps"].append(
                    {"run": 'ls -la "$HOME"'})
            else:
                copia["jobs"]["sondar"]["steps"][1]["run"] += "\nls -la"
            if not checar_sonda_origem_gerenciada(copia):
                falhas.append(("sondar-origem-gerenciada.yml",
                               "verificador aceitou defeito plantado: " + mutacao))

    inventario = carregados.get("inventariar-i7.yml", {})
    if not checar_inventario_i7(inventario):
        for mutacao in ("cron", "runner_generico", "segredo", "home_inteiro",
                        "passo_extra", "limpeza_checkout", "safe_directory",
                        "artefato_amplo", "artefato_opcional", "comando_anexado"):
            copia = copy.deepcopy(inventario)
            if mutacao == "cron":
                _gatilhos(copia)["schedule"] = [{"cron": "0 0 * * *"}]
            elif mutacao == "runner_generico":
                copia["jobs"]["inventariar"]["runs-on"] = [
                    "self-hosted", "macOS"]
            elif mutacao == "segredo":
                copia["jobs"]["inventariar"]["env"] = {
                    "TOKEN": "${{ secrets.OPENAI_API_KEY }}"}
            elif mutacao == "home_inteiro":
                passo = next(
                    p for p in copia["jobs"]["inventariar"]["steps"]
                    if "inventariar_legado_i7.py" in str(p.get("run", "")))
                passo["run"] = passo["run"].replace(
                    '$HOME/canario-imagens-treino', '$HOME')
            elif mutacao == "passo_extra":
                copia["jobs"]["inventariar"]["steps"].append(
                    {"run": 'ls -la "$HOME"'})
            elif mutacao == "limpeza_checkout":
                copia["jobs"]["inventariar"]["steps"][0]["with"]["clean"] = True
            elif mutacao == "safe_directory":
                copia["jobs"]["inventariar"]["steps"][0]["with"][
                    "set-safe-directory"] = True
            elif mutacao == "artefato_amplo":
                copia["jobs"]["inventariar"]["steps"][2]["with"]["path"] = (
                    "${{ runner.temp }}/*.json")
            elif mutacao == "artefato_opcional":
                copia["jobs"]["inventariar"]["steps"][2]["with"][
                    "if-no-files-found"] = "warn"
            else:
                copia["jobs"]["inventariar"]["steps"][1]["run"] += "\nfind \"$HOME\""
            if not checar_inventario_i7(copia):
                falhas.append(("inventariar-i7.yml",
                               "verificador aceitou defeito plantado: " + mutacao))
    preservacao = carregados.get("preservar-i7.yml", {})
    if not checar_preservacao_i7(preservacao):
        mutacoes = [
            (("permissions", "contents"), "write"),
            (("jobs", "preservar", "runs-on"), ["self-hosted", "macOS"]),
            (("jobs", "preservar", "permissions", "issues"), "write"),
            (("jobs", "preservar", "env"), {"GH_TOKEN": "${{ github.token }}"}),
            (("jobs", "preservar", "steps", 0, "with", "clean"), True),
            (("jobs", "preservar", "steps", 0, "with", "persist-credentials"), True),
            (("jobs", "preservar", "steps", 1, "run"), 'find "$HOME"'),
            (("jobs", "preservar", "steps", 2, "env", "GH_TOKEN"), "${{ secrets.PAT }}"),
            (("jobs", "preservar", "steps", 3, "with", "path"), "${{ runner.temp }}/**"),
        ]
        for caminho, valor in mutacoes:
            copia = copy.deepcopy(preservacao)
            destino = copia
            for chave in caminho[:-1]:
                destino = destino[chave]
            destino[caminho[-1]] = valor
            if not checar_preservacao_i7(copia):
                falhas.append(("preservar-i7.yml", "verificador aceitou mutacao: " + str(caminho)))
        copia = copy.deepcopy(preservacao)
        _gatilhos(copia)["push"] = {"branches": ["main"]}
        if not checar_preservacao_i7(copia):
            falhas.append(("preservar-i7.yml", "verificador aceitou bootstrap na main"))
    return falhas


def checar_capacidade_da_recuperacao(pipeline):
    """Contrato estrito: ausencia, erro e cancelamento nunca autorizam retry."""
    falhas = []
    jobs = pipeline.get("jobs", {})
    inicial = jobs.get("saude-inicial", {})

    def normalizar(valor):
        return "".join(str(valor).split())

    condicao = """${{ always() && !cancelled() &&
        needs.saude-inicial.outputs.saudavel == 'false' &&
        needs.saude-inicial.outputs.capacidade_permite_escrita == 'true' }}"""
    if normalizar(jobs.get("recuperar-shopify", {}).get("if")) != normalizar(condicao):
        falhas.append("recuperacao deve ignorar ancestrais pulados, mas exigir "
                      "saude falsa, capacidade explicita e ausencia de cancelamento")
    saida = """${{ steps.capacidade.outcome == 'success' &&
        steps.capacidade.outputs.escrita_permitida == 'true' }}"""
    if normalizar(inicial.get("outputs", {}).get(
            "capacidade_permite_escrita")) != normalizar(saida):
        falhas.append("capacidade so pode autorizar com leitura bem sucedida "
                      "e escrita_permitida=true")
    passos = [p for p in inicial.get("steps", []) if p.get("id") == "capacidade"]
    if len(passos) != 1:
        falhas.append("saude inicial deve medir capacidade uma vez")
    else:
        passo = passos[0]
        if (passo.get("run") != "$PY coletor/verificar_capacidade_banco.py --json --github-output"
                or passo.get("continue-on-error") is not True
                or not {"SUPABASE_URL", "SUPABASE_SECRET_KEY"}.issubset(
                    passo.get("env", {}))):
            falhas.append("medicao de capacidade deve preservar diagnostico, "
                          "saidas e leitura autenticada sem interromper a saude")
    return falhas


def _gatilhos(dados):
    """PyYAML 1.1 lê `on` como True; centraliza a compatibilidade."""
    return dados.get("on", dados.get(True, {})) or {}


def _passos_com_acao(passos, acao):
    return [passo for passo in passos
            if str(passo.get("uses", "")).startswith(acao + "@")]


def _tem_ambiente_ou_segredo(dados):
    """Percorre a árvore inteira; job-level env não pode escapar pelo formato."""
    if isinstance(dados, dict):
        if any(chave in dados for chave in ("env", "environment", "secrets")):
            return True
        return any(_tem_ambiente_ou_segredo(valor)
                   for valor in dados.values())
    if isinstance(dados, (list, tuple)):
        return any(_tem_ambiente_ou_segredo(valor) for valor in dados)
    return isinstance(dados, str) and "${{ secrets." in dados


def _comando_normalizado(valor):
    return " ".join(str(valor).split())


CHECKOUT_SHA = "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
UPLOAD_SHA = "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"


def checar_sonda_origem_gerenciada(workflow):
    """Contrato de uma prova de egresso: manual, hospedada e sem escrita."""
    falhas = []
    if set(workflow) != {"name", True, "permissions", "concurrency", "jobs"}:
        falhas.append("sonda gerenciada ganhou chave de topo não auditada")
    gatilhos_esperados = {"workflow_dispatch": None}
    if _gatilhos(workflow) != gatilhos_esperados:
        falhas.append("sonda gerenciada deve ser somente manual depois da prova inicial")
    if workflow.get("permissions") != {"contents": "read"}:
        falhas.append("sonda gerenciada deve ter somente contents: read")
    concorrencia = workflow.get("concurrency") or {}
    if (concorrencia.get("group") != "sonda-origem-gerenciada" or
            concorrencia.get("cancel-in-progress") is not False):
        falhas.append("sonda gerenciada perdeu sua concorrencia exclusiva")
    jobs = workflow.get("jobs") or {}
    if set(jobs) != {"sondar"}:
        falhas.append("sonda gerenciada deve ter somente o job sondar")
        return falhas
    job = jobs["sondar"]
    if set(job) != {"runs-on", "timeout-minutes", "steps"}:
        falhas.append("job da sonda gerenciada ganhou capacidade não auditada")
    if job.get("runs-on") != "ubuntu-latest":
        falhas.append("sonda gerenciada deve provar um runner hospedado Linux")
    if job.get("timeout-minutes") != 5:
        falhas.append("sonda gerenciada deve ter teto de cinco minutos")
    if _tem_ambiente_ou_segredo(workflow) or "permissions" in job:
        falhas.append("sonda gerenciada nao pode receber ambiente, segredo ou permissao do job")
    texto = str(workflow)
    for proibido in ("SUPABASE", "OPENAI", "secrets.", "supabase_rest",
                     "git push", "commitar.sh", "GITHUB_STEP_SUMMARY",
                     "GITHUB_OUTPUT", "sonda_actions.py",
                     "pente_fino_datacenter.py"):
        if proibido.lower() in texto.lower():
            falhas.append("sonda gerenciada contem operacao proibida `{}`".format(
                proibido))
    passos = job.get("steps") or []
    if len(passos) != 3:
        falhas.append("sonda gerenciada deve ter exatamente tres passos")
        return falhas
    checkout, execucao, artefato = passos
    if (set(checkout) != {"uses", "with"} or
            checkout.get("uses") != CHECKOUT_SHA or
            checkout.get("with") != {"persist-credentials": False}):
        falhas.append("sonda gerenciada deve fazer checkout sem credencial persistente")
    comando_esperado = (
        'python3 coletor/sondar_origem_gerenciada.py '
        '--saida "$RUNNER_TEMP/sonda-origem-gerenciada.json"')
    if (set(execucao) != {"name", "run"} or
            _comando_normalizado(execucao.get("run")) != comando_esperado):
        falhas.append("sonda gerenciada deve gravar apenas seu JSON no RUNNER_TEMP")
    with_esperado = {
        "name": "sonda-origem-gerenciada-${{ github.run_id }}-${{ github.run_attempt }}",
        "path": "${{ runner.temp }}/sonda-origem-gerenciada.json",
        "if-no-files-found": "error",
        "retention-days": 14,
    }
    if (set(artefato) != {"name", "uses", "with"} or
            artefato.get("uses") != UPLOAD_SHA or
            artefato.get("with") != with_esperado):
        falhas.append("sonda gerenciada deve publicar um unico artefato temporario")
    return falhas


def checar_inventario_i7(workflow):
    """Contrato de preservação: mede um cache conhecido sem inspecionar o host."""
    falhas = []
    if set(workflow) != {"name", True, "permissions", "concurrency", "jobs"}:
        falhas.append("inventario do i7 ganhou chave de topo não auditada")
    gatilhos_esperados = {"workflow_dispatch": None}
    if _gatilhos(workflow) != gatilhos_esperados:
        falhas.append("inventario do i7 deve ser somente manual depois da prova inicial")
    if workflow.get("permissions") != {"contents": "read"}:
        falhas.append("inventario do i7 deve ter somente contents: read")
    concorrencia = workflow.get("concurrency") or {}
    if (concorrencia.get("group") != "canario-dados" or
            concorrencia.get("cancel-in-progress") is not False):
        falhas.append("inventario do i7 deve serializar com tarefas antigas de dados")
    jobs = workflow.get("jobs") or {}
    if set(jobs) != {"inventariar"}:
        falhas.append("inventario do i7 deve ter somente o job inventariar")
        return falhas
    job = jobs["inventariar"]
    if set(job) != {"runs-on", "timeout-minutes", "steps"}:
        falhas.append("job do inventario ganhou capacidade não auditada")
    if job.get("runs-on") != ["self-hosted", "macOS", "X64", "sempre-ligado"]:
        falhas.append("inventario deve rodar somente no i7 legado")
    if job.get("timeout-minutes") != 20:
        falhas.append("inventario do i7 deve ter teto de vinte minutos")
    if _tem_ambiente_ou_segredo(workflow) or "permissions" in job:
        falhas.append("inventario do i7 nao pode receber ambiente, segredo ou permissao do job")
    texto = str(workflow)
    for proibido in ("SUPABASE", "OPENAI", "secrets.", "git push",
                     "commitar.sh", "RUNNER_WORKSPACE", "Config.xcconfig",
                     ".credentials", "find ", " du ", "GITHUB_STEP_SUMMARY",
                     "GITHUB_OUTPUT"):
        if proibido.lower() in texto.lower():
            falhas.append("inventario do i7 tenta inspecionar ou expor `{}`".format(
                proibido))
    passos = job.get("steps") or []
    if len(passos) != 3:
        falhas.append("inventario do i7 deve ter exatamente tres passos")
        return falhas
    checkout, execucao, artefato = passos
    if (set(checkout) != {"uses", "with"} or
            checkout.get("uses") != CHECKOUT_SHA or
            checkout.get("with") != {
                "persist-credentials": False,
                "clean": False,
                "path": "transicao-i7",
                "set-safe-directory": False,
            }):
        falhas.append("inventario deve usar checkout isolado, sem limpeza ou credencial")
    comando_esperado = _comando_normalizado(r"""
        set -euo pipefail
        PY_LEGADO="$HOME/.canario-python/bin/python3"
        if [[ ! -x "$PY_LEGADO" ]]; then
          echo 'Python portátil verificado ausente; inventário abortado sem instalar nada.' >&2
          exit 1
        fi
        SAIDA="$RUNNER_TEMP/inventario-i7-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json"
        "$PY_LEGADO" transicao-i7/ferramentas/inventariar_legado_i7.py \
          --cache "$HOME/canario-imagens-treino" \
          --saida "$SAIDA" \
          --referencia-do-workflow "$GITHUB_SHA"
    """)
    if (set(execucao) != {"name", "run"} or
            _comando_normalizado(execucao.get("run")) != comando_esperado):
        falhas.append("inventario deve medir somente o cache conhecido e gerar JSON temporario")
    with_esperado = {
        "name": "inventario-i7-${{ github.run_id }}-${{ github.run_attempt }}",
        "path": "${{ runner.temp }}/inventario-i7-${{ github.run_id }}-${{ github.run_attempt }}.json",
        "if-no-files-found": "error",
        "retention-days": 14,
    }
    if (set(artefato) != {"name", "if", "uses", "with"} or
            artefato.get("if") != "always()" or
            artefato.get("uses") != UPLOAD_SHA or
            artefato.get("with") != with_esperado):
        falhas.append("inventario deve publicar um unico artefato agregado temporario")
    return falhas


def checar_preservacao_i7(workflow):
    """Limita a cópia autorizada ao cache, ao i7 e a um recibo pequeno."""
    falhas = []
    bootstrap = {"branches": ["codex/produto-pos-challenge"], "paths": [
        ".github/workflows/preservar-i7.yml", "ferramentas/preservar_cache_luna.py",
        "ferramentas/enviar_snapshot_luna.py"]}
    if (set(workflow) != {"name", True, "permissions", "concurrency", "jobs"} or
            _gatilhos(workflow) not in ({"workflow_dispatch": None},
                                      {"workflow_dispatch": None, "push": bootstrap}) or
            workflow.get("permissions") != {"contents": "read"} or
            workflow.get("concurrency") != {"group": "canario-dados", "cancel-in-progress": False}):
        falhas.append("preservacao exige bootstrap isolado, permissao minima e serializacao com os dados")
    jobs = workflow.get("jobs", {})
    if set(jobs) != {"preservar"}:
        return falhas + ["preservacao deve ter somente o job preservar"]
    job = jobs["preservar"]
    if (set(job) != {"runs-on", "timeout-minutes", "permissions", "steps"} or
            job.get("runs-on") != ["self-hosted", "macOS", "X64", "sempre-ligado"] or
            job.get("timeout-minutes") != 45 or job.get("permissions") != {"contents": "write"}):
        falhas.append("preservacao exige i7 exato, teto de 45 minutos e somente contents write no job")
    passos = job.get("steps", [])
    if len(passos) != 4:
        return falhas + ["preservacao deve ter somente checkout, criacao, upload e recibo"]
    checkout, criar, enviar, artefato = passos
    if (set(checkout) != {"uses", "with"} or checkout.get("uses") != CHECKOUT_SHA or
            checkout.get("with") != {"persist-credentials": False, "clean": False,
                                     "path": "preservacao-i7", "set-safe-directory": False}):
        falhas.append("checkout de preservacao deve ser isolado e sem limpeza ou credenciais persistentes")
    comandos = [(criar, {"name", "run"}, r'''
        set -euo pipefail
        umask 077
        PY_LEGADO="$HOME/.canario-python/bin/python3"
        test -x "$PY_LEGADO"
        "$PY_LEGADO" preservacao-i7/ferramentas/preservar_cache_luna.py create \
          --cache "$HOME/canario-imagens-treino" \
          --output-dir "$RUNNER_TEMP/luna-backup-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" \
          --expected-count 5289 --expected-bytes 1988815984
    '''), (enviar, {"name", "run", "env"}, r'''
        set -euo pipefail
        umask 077
        PY_LEGADO="$HOME/.canario-python/bin/python3"
        "$PY_LEGADO" preservacao-i7/ferramentas/enviar_snapshot_luna.py \
          --output-dir "$RUNNER_TEMP/luna-backup-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" \
          --run-id "$GITHUB_RUN_ID" --attempt "$GITHUB_RUN_ATTEMPT" \
          --receipt "$RUNNER_TEMP/luna-upload-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json"
    ''')]
    for passo, chaves, comando in comandos:
        if set(passo) != chaves or _comando_normalizado(passo.get("run")) != _comando_normalizado(comando):
            falhas.append("comando de preservacao diverge do cache, totais ou destinos autorizados")
    sem_token = copy.deepcopy(workflow)
    sem_token["jobs"]["preservar"]["steps"][2].pop("env", None)
    if enviar.get("env") != {"GH_TOKEN": "${{ github.token }}"} or _tem_ambiente_ou_segredo(sem_token):
        falhas.append("somente o upload pode receber o token efemero; outros ambientes e segredos sao proibidos")
    if (set(artefato) != {"name", "uses", "with"} or artefato.get("uses") != UPLOAD_SHA or
            artefato.get("with") != {
                "name": "luna-upload-${{ github.run_id }}-${{ github.run_attempt }}",
                "path": "${{ runner.temp }}/luna-upload-${{ github.run_id }}-${{ github.run_attempt }}.json",
                "if-no-files-found": "error", "retention-days": 14}):
        falhas.append("artefato deve conter somente o recibo JSON da transferencia por catorze dias")
    return falhas


def checar_orquestracao(workflows):
    """Impede cron concorrente e regressão na ordem coleta -> saúde -> motor."""
    falhas = []

    def falhar(arquivo, mensagem):
        falhas.append((os.path.join(os.path.dirname(WORKFLOWS), arquivo),
                       mensagem))

    def grupo_de_concorrencia(dados):
        concorrencia = dados.get("concurrency")
        if isinstance(concorrencia, str):
            return concorrencia
        if isinstance(concorrencia, dict):
            return concorrencia.get("group")
        return None

    for mensagem in checar_sonda_origem_gerenciada(
            workflows.get("sondar-origem-gerenciada.yml", {})):
        falhar("sondar-origem-gerenciada.yml", mensagem)
    for mensagem in checar_inventario_i7(
            workflows.get("inventariar-i7.yml", {})):
        falhar("inventariar-i7.yml", mensagem)
    for mensagem in checar_preservacao_i7(
            workflows.get("preservar-i7.yml", {})):
        falhar("preservar-i7.yml", mensagem)

    # Um workflow chamador mantém o próprio grupo ocupado durante toda a run.
    # Se chamar um workflow reutilizável que pede o mesmo grupo literal, o
    # filho nunca consegue começar. O GitHub encerra em segundos sem criar o
    # job chamado nem produzir log útil — exatamente o vermelho silencioso da
    # coleta de catálogo em 31/08.
    for arquivo, dados in workflows.items():
        grupo_pai = grupo_de_concorrencia(dados)
        if not grupo_pai:
            continue
        for nome_job, job in (dados.get("jobs") or {}).items():
            chamado = job.get("uses") if isinstance(job, dict) else None
            prefixo = "./.github/workflows/"
            if not isinstance(chamado, str) or not chamado.startswith(prefixo):
                continue
            arquivo_filho = os.path.basename(chamado)
            grupo_filho = grupo_de_concorrencia(workflows.get(arquivo_filho, {}))
            if grupo_filho == grupo_pai:
                falhar(arquivo,
                       "job `{}` chama workflow com o mesmo grupo de "
                       "concorrencia `{}` e cria deadlock".format(
                           nome_job, grupo_pai))

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

    editorial = workflows.get("coleta-editorial.yml", {})
    entrada_editorial = (editorial.get("on", editorial.get(True, {})) or {})
    for gatilho in ("workflow_call", "workflow_dispatch"):
        entradas = (entrada_editorial.get(gatilho) or {}).get("inputs", {})
        if "somente_arquivo" not in entradas:
            falhar("coleta-editorial.yml",
                   "coleta editorial sem modo de arquivo atomico")
    passos_editorial = editorial.get("jobs", {}).get("coletar", {}).get("steps", [])
    passo_coleta_editorial = next((p for p in passos_editorial
                                   if "coletor_editorial.py" in str(p.get("run", ""))), {})
    if "EDITORIAL_SOMENTE_ARQUIVO" not in passo_coleta_editorial.get("env", {}):
        falhar("coleta-editorial.yml",
               "entrada somente_arquivo nao chega ao coletor")

    # Coletas de novos paineis não podem cair no brasileiro por omissão.
    for arquivo in ("coleta.yml", "coleta-shopify.yml"):
        dados = workflows.get(arquivo, {})
        gatilhos = dados.get("on", dados.get(True, {})) or {}
        chamada = (gatilhos.get("workflow_call") or {}).get("inputs", {})
        segmento = chamada.get("segmento", {})
        if segmento.get("default") != "feminino_casual_br":
            falhar(arquivo, "coleta reutilizavel sem segmento brasileiro explicito")

    direcao = workflows.get("coleta-direcao-internacional.yml", {})
    job_direcao = direcao.get("jobs", {}).get("coletar", {})
    if (job_direcao.get("uses") != individuais["coleta-shopify.yml"] or
            job_direcao.get("with", {}).get("segmento") != "direcao_intl"):
        falhar("coleta-direcao-internacional.yml",
               "direcao internacional nao esta isolada em direcao_intl")

    candidatos = workflows.get("coleta-catalogo-candidato.yml", {})
    gatilhos_candidatos = candidatos.get(
        "on", candidatos.get(True, {})) or {}
    if "schedule" not in gatilhos_candidatos:
        falhar("coleta-catalogo-candidato.yml",
               "catalogo candidato sem manutencao recorrente")
    jobs_candidatos = candidatos.get("jobs", {})
    for job, reutilizavel in (("vtex", individuais["coleta.yml"]),
                              ("shopify", individuais["coleta-shopify.yml"])):
        definicao = jobs_candidatos.get(job, {})
        if (definicao.get("uses") != reutilizavel or
                definicao.get("with", {}).get("segmento") !=
                "catalogo_candidato_br"):
            falhar("coleta-catalogo-candidato.yml",
                   "catalogo candidato {} nao esta isolado".format(job))
        if "github.event_name == 'schedule'" not in str(definicao.get("if", "")):
            falhar("coleta-catalogo-candidato.yml",
                   "catalogo candidato {} nao roda na agenda".format(job))
        if job == "vtex" and definicao.get("with", {}).get("pente_fino") is not False:
            falhar("coleta-catalogo-candidato.yml",
                   "catalogo candidato VTEX ainda dispara sonda ampla")
        if (job == "shopify" and
                definicao.get("with", {}).get("verificar_isolamento") is not False):
            falhar("coleta-catalogo-candidato.yml",
                   "catalogo candidato verifica antes do motor")
    publicacao_candidatos = jobs_candidatos.get("publicar", {})
    if (publicacao_candidatos.get("uses") != individuais["motor.yml"] or
            set(publicacao_candidatos.get("needs", [])) != {"vtex", "shopify"}):
        falhar("coleta-catalogo-candidato.yml",
               "catalogo candidato nao publica o motor depois das coletas")
    verificacao_candidatos = jobs_candidatos.get("verificar", {})
    if (verificacao_candidatos.get("needs") != "publicar" or
            "verificar_isolamento_segmento.py" not in str(
                verificacao_candidatos.get("steps", []))):
        falhar("coleta-catalogo-candidato.yml",
               "catalogo candidato nao prova isolamento depois do motor")

    for arquivo in ["coleta.yml", "coleta-shopify.yml",
                    "coleta-editorial.yml", "coleta-trends.yml"]:
        passos = workflows.get(arquivo, {}).get("jobs", {}).get(
            "coletar", {}).get("steps", [])
        portoes = [p for p in passos
                   if "verificar_capacidade_banco.py" in str(p.get("run", ""))]
        if len(portoes) != 1:
            falhar(arquivo, "coleta sem portao unico de capacidade")
            continue
        portao = portoes[0]
        ambiente = portao.get("env", {})
        if (portao.get("continue-on-error") or
                not {"SUPABASE_URL", "SUPABASE_SECRET_KEY"}.issubset(ambiente)):
            falhar(arquivo,
                   "portao de capacidade pode falhar aberto ou esta sem segredo")

    coleta_varejo = workflows.get("coleta.yml", {})
    passos_varejo = coleta_varejo.get("jobs", {}).get(
        "coletar", {}).get("steps", [])
    passos_pente = [p for p in passos_varejo
                    if "Pente fino" in str(p.get("name", ""))]
    if (len(passos_pente) != 1 or
            "inputs.marca == ''" not in str(passos_pente[0].get("if", "")) or
            "inputs.pente_fino" not in str(passos_pente[0].get("if", ""))):
        falhar("coleta.yml",
               "coleta direcionada nao deve repetir o pente fino inteiro")

    pipeline = workflows.get("pipeline-diario.yml", {})
    for mensagem in checar_capacidade_da_recuperacao(pipeline):
        falhar("pipeline-diario.yml", mensagem)
    gatilhos = pipeline.get("on", pipeline.get(True, {})) or {}
    if "schedule" not in gatilhos:
        falhar("pipeline-diario.yml", "pipeline unico sem `schedule`")

    # O primeiro pacote factual da 1.3 e um laboratorio deliberadamente
    # separado do pipeline diario. Transformar esse workflow em cron, deixar o
    # artefato persistir ou remover a limpeza do runner mudaria o contrato de
    # privacidade sem passar pela revisao de fontes.
    etiqueta = workflows.get("radar-etiqueta-privado.yml", {})
    gatilhos_etiqueta = etiqueta.get(
        "on", etiqueta.get(True, {})) or {}
    if set(gatilhos_etiqueta) != {"workflow_dispatch"}:
        falhar("radar-etiqueta-privado.yml",
               "pacote privado da Etiqueta deve ter apenas disparo manual")
    job_etiqueta = etiqueta.get("jobs", {}).get("materializar", {})
    if job_etiqueta.get("environment") != "market-intelligence-lab":
        falhar("radar-etiqueta-privado.yml",
               "materializador saiu do ambiente isolado do laboratorio")
    passos_etiqueta = job_etiqueta.get("steps", [])
    execucoes_etiqueta = "\n".join(
        str(p.get("run", "")) for p in passos_etiqueta)
    if ("materializar_etiqueta_radar.py" not in execucoes_etiqueta or
            "--supabase" not in execucoes_etiqueta or
            "preparar_revisao_etiqueta_radar.py" not in execucoes_etiqueta or
            "teste_revisao_etiqueta_radar.py" not in execucoes_etiqueta):
        falhar("radar-etiqueta-privado.yml",
               "workflow nao materializa e prepara a revisao privada")
    artefatos_etiqueta = [
        p for p in passos_etiqueta
        if str(p.get("uses", "")).startswith("actions/upload-artifact@")]
    caminhos_artefatos_etiqueta = [
        str(passo.get("with", {}).get("path", ""))
        for passo in artefatos_etiqueta
    ]
    if (len(artefatos_etiqueta) != 2 or
            set(caminhos_artefatos_etiqueta) != {
                "${{ runner.temp }}/radar-etiqueta-facts.json",
                "${{ runner.temp }}/radar-etiqueta-revisao.html",
            } or
            any(passo.get("with", {}).get("retention-days") != 7
                or "success()" not in str(passo.get("if", ""))
                for passo in artefatos_etiqueta)):
        falhar("radar-etiqueta-privado.yml",
               "pacote e fila cegos devem ser artefatos separados por sete dias")
    limpezas_etiqueta = [
        p for p in passos_etiqueta
        if "rm -f" in str(p.get("run", "")) and
        "radar-etiqueta-facts.json" in str(p.get("run", ""))]
    if (len(limpezas_etiqueta) != 2 or
            "always()" not in str(limpezas_etiqueta[-1].get("if", ""))):
        falhar("radar-etiqueta-privado.yml",
               "runner persistente nao limpa o pacote antes e depois da run")
    if any("radar-etiqueta-revisao.html" not in str(p.get("run", ""))
           for p in limpezas_etiqueta):
        falhar("radar-etiqueta-privado.yml",
               "runner persistente nao limpa a fila cega antes e depois")
    proibidos_etiqueta = ("openai", "schedule", "pipeline-diario.yml",
                          "insert into", "update public.", "delete from")
    for proibido in proibidos_etiqueta:
        if proibido in execucoes_etiqueta.lower():
            falhar("radar-etiqueta-privado.yml",
                   "workflow privado contem operacao proibida `{}`".format(
                       proibido))

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
            recuperar_busca.get("uses") is not None or
            not recuperar_busca.get("steps")):
        falhar("pipeline-diario.yml",
               "pipeline nao deve repetir Trends imediatamente apos recusa")

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

    def conferir_relatorio_fora_do_portao(arquivo, job):
        """Relatorio pode falhar; somente o dado pode impedir o motor.

        A main protegida passou a exigir PR em 27/08. O antigo `commitar.sh`
        transformava essa recusa administrativa em falha da saude e pulava o
        motor, mesmo com todas as fontes verdes. O resumo e o artefato deixam
        o diagnostico auditavel sem escrever na branch nem contaminar o gate.
        """
        passos_job = job.get("steps", [])
        escritores = [p for p in passos_job
                      if "commitar.sh" in str(p.get("run", ""))
                      or "git push" in str(p.get("run", ""))]
        if escritores:
            falhar(arquivo,
                   "saude voltou a escrever na branch e pode bloquear o motor")

        resumos = [p for p in passos_job
                   if "GITHUB_STEP_SUMMARY" in str(p.get("run", ""))
                   and "SAUDE.md" in str(p.get("run", ""))]
        if (len(resumos) != 1 or
                "always()" not in str(resumos[0].get("if", "")) or
                resumos[0].get("continue-on-error") is not True):
            falhar(arquivo,
                   "relatorio de saude nao vai ao resumo de forma nao bloqueante")

        artefatos = [p for p in passos_job
                     if str(p.get("uses", "")).startswith(
                         "actions/upload-artifact@")
                     and p.get("with", {}).get("path") == "SAUDE.md"]
        if (len(artefatos) != 1 or
                "always()" not in str(artefatos[0].get("if", "")) or
                artefatos[0].get("continue-on-error") is not True):
            falhar(arquivo,
                   "SAUDE.md nao fica disponivel como artefato nao bloqueante")

    conferir_relatorio_fora_do_portao("pipeline-diario.yml", saude)

    # A coleta VTEX integra o pipeline diario. Mesmo que SAUDE.md nao escreva
    # mais na branch, o antigo commit do cache ainda reproduziria GH006 assim
    # que uma marca descobrisse departamento novo.
    coleta_vtex = workflows.get("coleta.yml", {})
    job_vtex = coleta_vtex.get("jobs", {}).get("coletar", {})
    passos_vtex = job_vtex.get("steps", [])
    escritores_vtex = [p for p in passos_vtex
                       if "commitar.sh" in str(p.get("run", ""))
                       or "git push" in str(p.get("run", ""))]
    if escritores_vtex:
        falhar("coleta.yml",
               "coleta VTEX ainda escreve direto na main protegida")
    artefatos_cache = [p for p in passos_vtex
                       if str(p.get("uses", "")).startswith(
                           "actions/upload-artifact@")
                       and p.get("with", {}).get("path") ==
                       "anexos/departamentos_vtex.json"]
    if (len(artefatos_cache) != 1 or
            artefatos_cache[0].get("continue-on-error") is not True):
        falhar("coleta.yml",
               "cache VTEX alterado nao fica auditavel sem bloquear a coleta")

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
    conferir_relatorio_fora_do_portao(
        "recuperar-pipeline.yml", jobs_recuperacao.get("saude", {}))
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
    reclassificar = [i for i, comando in enumerate(comandos)
                     if "reclassificar_editorial.py" in comando]
    if len(atributos) != 1 or legado:
        falhar("motor.yml",
               "workflow deve ter uma unica publicacao atomica do motor")
    if backfill and atributos and backfill[0] > atributos[0]:
        falhar("motor.yml", "backfill deve acontecer antes da publicacao")
    if (len(reclassificar) != 1 or not backfill or
            not (backfill[0] < reclassificar[0] < atributos[0])):
        falhar("motor.yml",
               "reclassificacao editorial deve ficar entre arquivo e motor")
    passos_motor = motor.get("steps", [])
    passo_backfill = next((p for p in passos_motor
                           if "backfill_editorial.py" in str(p.get("run", ""))), {})
    if passo_backfill.get("env", {}).get("BACKFILL_SOMENTE_ARQUIVO") != "1":
        falhar("motor.yml", "backfill completo pode publicar serie intermediaria")

    testes = workflows.get("testes.yml", {}).get("jobs", {})
    if set(testes) != {"coletores"}:
        falhar("testes.yml",
               "GitHub deve executar somente Python; Swift pertence ao Xcode Cloud")
    job_python = testes.get("coletores", {})
    if (job_python.get("runs-on") != "ubuntu-latest" or
            job_python.get("env") != {"PY": "python3"}):
        falhar("testes.yml",
               "suite Python deve usar runner Linux efemero com interpretador explicito")
    passos_python = job_python.get("steps", [])
    setup_python = [p for p in passos_python
                    if str(p.get("uses", "")).startswith("actions/setup-python@")]
    if (len(setup_python) != 1 or
            setup_python[0].get("uses") !=
            "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1" or
            setup_python[0].get("with") != {"python-version": "3.11"}):
        falhar("testes.yml",
               "suite Python perdeu o setup 3.11 fixado por commit")

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


"""Jobs que rodam sozinhos, sem ninguem olhando, nao podem cair no notebook.

Em 20/08/2026 a coleta das 03:00 caiu no Mac pessoal do JP em vez do i7, porque
`RUNNER_COLETA` valia `self-hosted` -- rotulo que os DOIS runners tem, entao o
GitHub escolhia o que estivesse livre. As 04:17 a maquina dormiu, o GitHub
declarou "the self-hosted runner lost communication with the server", e:

  * a coleta VTEX terminou LOCALMENTE as 04:24, com as 13 marcas gravadas;
  * o GitHub ja a considerava falha, entao Shopify, editorial e busca foram
    puladas por dependencia;
  * a saude rodou seis minutos antes das gravacoes e viu zero marca;
  * o motor foi bloqueado pelo portao, e o app ficou sem dado novo.

Um dia inteiro perdido por uma perna que tinha dado certo. A saida nao e manter
o notebook acordado -- e nao mandar trabalho de madrugada para ele. O rotulo
`sempre-ligado` existe so no i7.
"""
JOBS_QUE_NAO_PODEM_DEPENDER_DE_NOTEBOOK = {
    "pipeline-diario.yml", "coleta-shopify.yml", "coleta-trends.yml",
    "motor.yml", "recuperar-pipeline.yml", "sonda.yml",
    "sonda-edge-luna.yml",
}
# Estes precisam do Xcode do Mac do JP (Vision, XCTest, xcodebuild) e por isso
# sao disparados a mao, com alguem olhando.
ROTULOS_QUE_EXIGEM_O_MAC_DO_JP = {"xcode"}


def checar_runner_das_tarefas_automaticas(arquivos):
    falhas = []
    for caminho in arquivos:
        nome = os.path.basename(caminho)
        if nome not in JOBS_QUE_NAO_PODEM_DEPENDER_DE_NOTEBOOK:
            continue
        with open(caminho, encoding="utf-8") as arquivo:
            for numero, linha in enumerate(arquivo, 1):
                bruto = linha.strip()
                if not bruto.startswith("runs-on:"):
                    continue
                alvo = bruto[len("runs-on:"):].strip()
                if "${{" in alvo:
                    # Vem de `vars.RUNNER_COLETA`, que aponta para o rotulo
                    # exclusivo do i7. Conferido no proprio GitHub, nao aqui.
                    continue
                rotulos = {r.strip() for r in alvo.strip("[]").split(",")}
                if rotulos & ROTULOS_QUE_EXIGEM_O_MAC_DO_JP:
                    continue
                if "sempre-ligado" not in rotulos and "X64" not in rotulos:
                    falhas.append((caminho, (
                        "linha {}: `{}` aceita qualquer Mac, inclusive o "
                        "notebook. Tarefa automatica precisa de "
                        "`sempre-ligado`.").format(numero, alvo)))
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


def checar_suites_no_ci():
    """Todo `teste_*.py` tem de estar no CI.

    "Funcao criada nao e funcao chamada" ja custou um dia de eventos parados em
    30/07. O mesmo vale para teste: em 05/08 o `teste_fila_de_busca.py`, escrito
    para trancar um bug que ja tinha aparecido DUAS vezes, ficou de fora do
    `testes.yml` e portanto nunca rodou no CI. Escrever o teste e so metade.
    """
    # Allowlist curta e justificada, uma linha por excecao -- mesmo formato do
    # teste de vocabulario. Cada entrada precisa se defender.
    fora_do_ci = {
        # Bate em 26 sites externos a 1 req/s para descobrir plataforma. E
        # ferramenta de descoberta, rodada a mao quando entra marca nova; no CI
        # seria lento, instavel e deselegante com os sites (regra 7).
        "teste_30s.py": "faz rede em 26 dominios externos",
    }
    ci = os.path.join(os.path.dirname(WORKFLOWS), "testes.yml")
    if not os.path.exists(ci):
        return [(ci, "testes.yml nao existe")]
    conteudo = open(ci, encoding="utf-8").read()
    pasta = os.path.dirname(os.path.abspath(__file__))
    faltando = []
    for nome in sorted(os.listdir(pasta)):
        if not (nome.startswith("teste_") and nome.endswith(".py")):
            continue
        if nome in fora_do_ci:
            continue
        if "coletor/" + nome not in conteudo:
            faltando.append((
                ci, "{} existe e NAO roda no CI: teste escrito nao e teste "
                    "rodado".format(nome)))
    return faltando


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
    falhas.extend(checar_runner_das_tarefas_automaticas(arquivos))
    falhas.extend(checar_suites_no_ci())

    for f, erro in falhas:
        print("FALHOU {}: {}".format(os.path.basename(f), erro))
    print("{} workflows checados via {}, {} falhas".format(
        len(arquivos), modo, len(falhas)))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
