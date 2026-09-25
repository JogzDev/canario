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

    def grupo_de_concorrencia(dados):
        concorrencia = dados.get("concurrency")
        if isinstance(concorrencia, str):
            return concorrencia
        if isinstance(concorrencia, dict):
            return concorrencia.get("group")
        return None

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

    # O GitHub documenta o começo de cada hora como pico: `schedule` pode ser
    # atrasado e, sob carga suficiente, ate descartado. Foi exatamente o que
    # observamos em 19 e 20/09, quando `0 6 * * *` nasceu quase quatro horas
    # tarde. Toda agenda autônoma precisa fugir do minuto zero.
    for arquivo, dados in workflows.items():
        gatilhos = dados.get("on", dados.get(True, {})) or {}
        for agenda in gatilhos.get("schedule", []) or []:
            cron = str(agenda.get("cron", "")).strip()
            campos = cron.split()
            if len(campos) != 5:
                falhar(arquivo, "cron agendado fora do formato de cinco campos")
            elif campos[0] == "0":
                falhar(arquivo,
                       "cron no minuto zero entra no pico documentado do GitHub")

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

    for arquivo in ("coleta.yml", "coleta-shopify.yml",
                    "coleta-editorial.yml", "coleta-trends.yml"):
        dados = workflows.get(arquivo, {})
        gatilhos = dados.get("on", dados.get(True, {})) or {}
        chamada = gatilhos.get("workflow_call") or {}
        if "data_operacional" not in chamada.get("inputs", {}):
            falhar(arquivo, "workflow reutilizavel sem ancora de data")
        if "data_operacional" not in chamada.get("outputs", {}):
            falhar(arquivo, "workflow reutilizavel nao propaga a ancora")

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
    gatilhos_varejo = coleta_varejo.get(
        "on", coleta_varejo.get(True, {})) or {}
    for gatilho in ("workflow_call", "workflow_dispatch"):
        entradas = (gatilhos_varejo.get(gatilho) or {}).get("inputs", {})
        if "animale_forcar" not in entradas:
            falhar("coleta.yml",
                   "Animale semanal ficou sem override manual auditavel")
    passos_varejo = coleta_varejo.get("jobs", {}).get(
        "coletar", {}).get("steps", [])
    passos_pente = [p for p in passos_varejo
                    if "Pente fino" in str(p.get("name", ""))]
    if (len(passos_pente) != 1 or
            "inputs.marca == ''" not in str(passos_pente[0].get("if", "")) or
            "inputs.pente_fino" not in str(passos_pente[0].get("if", ""))):
        falhar("coleta.yml",
               "coleta direcionada nao deve repetir o pente fino inteiro")
    passo_coletor_varejo = next((p for p in passos_varejo
                                 if "coletor_varejo.py" in str(p.get("run", ""))), {})
    ambiente_varejo = passo_coletor_varejo.get("env", {})
    if (ambiente_varejo.get("COLETA_ANIMALE_CADENCIA") != "semanal"
            or "inputs.animale_forcar" not in str(
                ambiente_varejo.get("COLETA_ANIMALE_FORCAR", ""))):
        falhar("coleta.yml",
               "cadencia semanal da Animale nao chega ao coletor")

    pipeline = workflows.get("pipeline-diario.yml", {})
    gatilhos = pipeline.get("on", pipeline.get(True, {})) or {}
    # A63: o titular e o pg_cron do Supabase; o GitHub e reserva. Cron aqui
    # voltaria a correr o pipeline duas vezes no mesmo dia.
    if "schedule" in gatilhos or "workflow_dispatch" not in gatilhos:
        falhar("pipeline-diario.yml",
               "pipeline deve nascer so por disparo (Supabase ou reserva), sem cron")
    vtex = (pipeline.get("jobs", {}).get("varejo-vtex") or {}).get("with") or {}
    if vtex.get("pente_fino") is not False:
        falhar("pipeline-diario.yml",
               "pipeline disparado rodaria o pente fino todo dia")
    reserva = workflows.get("gatilho-reserva.yml", {})
    gatilhos_reserva = reserva.get("on", reserva.get(True, {})) or {}
    texto_reserva = open(os.path.join(RAIZ, ".github", "workflows", "gatilho-reserva.yml"),
                         encoding="utf-8").read()
    if (not gatilhos_reserva.get("schedule")
            or (reserva.get("permissions") or {}).get("actions") != "write"
            or "gh run list --workflow pipeline-diario.yml" not in texto_reserva
            or 'if [ "$execucoes" -gt 0 ]' not in texto_reserva
            or "gh workflow run pipeline-diario.yml --ref main" not in texto_reserva):
        falhar("gatilho-reserva.yml",
               "a reserva precisa de cron e so disparar sem execucao no dia")

    jobs = pipeline.get("jobs", {})
    for mensagem in checar_portao_publicacao(jobs):
        falhar("pipeline-diario.yml", mensagem)
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

    for job in ("varejo-shopify", "editorial", "busca"):
        if "data_operacional" not in jobs.get(job, {}).get("with", {}):
            falhar("pipeline-diario.yml",
                   "job `{}` pode trocar de dia no meio da run".format(job))

    verificacao_final = jobs.get("verificacao-final", {})
    passos_verificacao = verificacao_final.get("steps", [])
    passo_capacidade_final = next((p for p in passos_verificacao
                                  if "verificar_capacidade_banco.py" in
                                  str(p.get("run", ""))), {})
    passo_isolamento_final = next((p for p in passos_verificacao
                                  if "verificar_isolamento_segmento.py" in
                                  str(p.get("run", ""))), {})
    if (verificacao_final.get("needs") != "publicacao" or
            verificacao_final.get("runs-on") != "ubuntu-latest" or
            passo_capacidade_final.get("env", {}).get(
                "CAPACIDADE_MAXIMA_PCT") != "85" or
            passo_isolamento_final.get("env", {}).get(
                "SEGMENTO_VERIFICADO") != "direcao_intl"):
        falhar("pipeline-diario.yml",
               "verificacao final hospedada nao fecha capacidade e isolamento")

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
    if "data_operacional" not in saude_inicial.get("outputs", {}):
        falhar("pipeline-diario.yml",
               "saude inicial nao preserva a data das coletas")

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
    passo_portao_final = next((p for p in saude.get("steps", [])
                              if p.get("id") == "portao"), {})
    if "DATA_OPERACIONAL" not in passo_portao_final.get("env", {}):
        falhar("pipeline-diario.yml", "saude final pode trocar de dia")

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
    if "data_operacional" not in entrada_recuperacao.get("inputs", {}):
        falhar("recuperar-pipeline.yml",
               "recuperacao sem ancora explicita para virada de dia")
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
    passo_portao_recuperacao = next((p for p in passos_saude_recuperacao
                                    if p.get("id") == "portao"), {})
    if "DATA_OPERACIONAL" not in passo_portao_recuperacao.get("env", {}):
        falhar("recuperar-pipeline.yml",
               "portao de recuperacao pode trocar de dia no meio da run")
    for nome in ("recuperar-shopify", "recuperar-busca"):
        if "data_operacional" not in jobs_recuperacao.get(nome, {}).get("with", {}):
            falhar("recuperar-pipeline.yml",
                   "{} nao recebe a ancora da recuperacao".format(nome))

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

    testes = workflows.get("testes.yml", {}).get("jobs", {}).get("app", {})
    comandos_app = [str(p.get("run", ""))
                    for p in testes.get("steps", [])]
    swift = [c for c in comandos_app if c.strip() == "swift test"]
    if testes.get("runs-on") != "macos-latest" or len(swift) != 1:
        falhar("testes.yml",
               "logica Swift deve rodar uma vez no macOS gerenciado")
    if any("xcodebuild" in comando for comando in comandos_app):
        falhar("testes.yml",
               "build/UI completo deve usar a franquia separada do Xcode Cloud")

    workflow_sonda = workflows.get("sonda.yml", {})
    sonda = workflow_sonda.get("jobs", {}).get("sondar", {})
    passos_sonda = sonda.get("steps", [])
    publicadores = [p for p in passos_sonda
                    if "commitar.sh" in str(p.get("run", ""))]
    artefatos = [p for p in passos_sonda
                 if str(p.get("uses", "")).startswith(
                     "actions/upload-artifact@")]
    if publicadores:
        falhar("sonda.yml",
               "sonda nao pode furar a protecao da main para gravar relatorio")
    if workflow_sonda.get("permissions") != {"contents": "read"}:
        falhar("sonda.yml", "sonda precisa somente de leitura no repositorio")
    if len(artefatos) != 1:
        falhar("sonda.yml", "diagnostico da sonda nao e guardado uma vez")
    else:
        parametros = artefatos[0].get("with", {})
        if (parametros.get("path") != "SONDA_ACTIONS.md" or
                parametros.get("if-no-files-found") != "error" or
                parametros.get("retention-days") != 14 or
                "always()" not in str(artefatos[0].get("if", ""))):
            falhar("sonda.yml",
                   "artefato da sonda nao preserva diagnostico parcial por 14 dias")

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


def checar_portao_publicacao(jobs):
    """Não confundir COMMIT do motor com avanço do dia público do painel."""
    falhas = []
    publicacao = jobs.get("publicacao", {})
    if (set(publicacao.get("needs", [])) != {"motor", "saude-inicial"}
            or "always()" not in str(publicacao.get("if", ""))
            or "needs.motor.result == 'success'" not in str(publicacao.get("if", ""))
            or publicacao.get("continue-on-error")):
        falhas.append("publicacao deve aguardar motor e a data original, sem falhar aberto")
    portoes = [p for p in publicacao.get("steps", [])
               if "sonda_significado_publico.py" in str(p.get("run", ""))]
    if len(portoes) != 1:
        falhas.append("publicacao deve conferir a API uma vez, depois do motor")
    else:
        p = portoes[0]
        comando, ambiente = str(p.get("run", "")), p.get("env", {})
        if (p.get("continue-on-error") or p.get("if")
                or "--exigir-publicacao" not in comando
                or '--data-operacional "$DATA_OPERACIONAL"' not in comando
                or "--relatorio publicacao-painel.json" not in comando
                or ambiente.get("DATA_OPERACIONAL") !=
                "${{ needs.saude-inicial.outputs.data_operacional }}"
                or not {"SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"}.issubset(ambiente)
                or "SUPABASE_SECRET_KEY" in ambiente):
            falhas.append("publicacao sem data propagada, chave publica ou falha fechada")
    artefatos = [p for p in publicacao.get("steps", [])
                if str(p.get("uses", "")).startswith("actions/upload-artifact@")
                and p.get("with", {}).get("path") == "publicacao-painel.json"]
    if len(artefatos) != 1 or "always()" not in str(artefatos[0].get("if", "")):
        falhas.append("publicacao deve preservar o diagnostico quando falhar")
    alerta = jobs.get("alerta", {})
    ambiente_alerta = next((p.get("env", {}) for p in alerta.get("steps", [])
                           if "ESTADO_DO_PIPELINE" in p.get("env", {})), {})
    if ("publicacao" not in alerta.get("needs", [])
            or "needs.publicacao.result == 'success'" not in
            str(ambiente_alerta.get("ESTADO_DO_PIPELINE", ""))
            or "publicacao=${{ needs.publicacao.result }}" not in
            str(ambiente_alerta.get("JOBS_QUE_FALHARAM", ""))):
        falhas.append("alerta nao pode encerrar incidente sem publicacao confirmada")
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
WORKFLOWS_QUE_DEVEM_SER_AUTONOMOS = {
    "pipeline-diario.yml", "coleta-shopify.yml", "coleta-trends.yml",
    "motor.yml", "recuperar-pipeline.yml", "sonda.yml",
    "sonda-edge-luna.yml", "testes.yml", "coleta.yml",
    "coleta-editorial.yml", "coleta-catalogo-candidato.yml",
    "verificar-producao.yml", "sonda-significado.yml",
}
ROTULOS_PESSOAIS = {"self-hosted", "sempre-ligado", "xcode", "X64"}


def checar_runner_das_tarefas_automaticas(arquivos):
    """Nenhum job depende de máquina pessoal; agendas têm executor previsível."""
    falhas = []
    for caminho in arquivos:
        nome = os.path.basename(caminho)
        with open(caminho, encoding="utf-8") as arquivo:
            for numero, linha in enumerate(arquivo, 1):
                bruto = linha.strip()
                if not bruto.startswith("runs-on:"):
                    continue
                alvo = bruto[len("runs-on:"):].strip()
                if any(rotulo in alvo for rotulo in ROTULOS_PESSOAIS):
                    falhas.append((caminho, (
                        "linha {}: `{}` ainda depende de runner pessoal."
                    ).format(numero, alvo)))
                elif (nome in WORKFLOWS_QUE_DEVEM_SER_AUTONOMOS
                      and "${{" in alvo and "inputs.executor" not in alvo):
                    falhas.append((caminho, (
                        "linha {}: executor variável não está restrito ao "
                        "fallback gerenciado do Trends.").format(numero)))
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
