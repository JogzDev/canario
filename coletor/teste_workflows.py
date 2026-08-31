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

    testes = workflows.get("testes.yml", {}).get("jobs", {}).get("app", {})
    comandos_app = [str(p.get("run", ""))
                    for p in testes.get("steps", [])]
    ui = [c for c in comandos_app
          if "xcodebuild test" in c and "CanarioUITests" in c]
    if len(ui) != 1:
        falhar("testes.yml",
               "alvo CanarioUITests existe, mas nao roda uma vez no CI")

    # `-only-testing` com nome ERRADO nao falha: o xcodebuild roda zero testes e
    # devolve `** TEST SUCCEEDED **`. Foi assim que
    # `testFillInfoAbreClothingDetailsForaDaSheet` -- um nome que nunca existiu
    # -- ficou listado como um dos cinco fluxos offline protegidos e nunca
    # rodou, com o CI verde o tempo todo. Verde por ausencia e pior que
    # vermelho: ele afirma cobertura que nao existe.
    if ui:
        fonte_ui = os.path.join(RAIZ, "app", "CanarioUITests",
                                "CanarioUITests.swift")
        try:
            texto_ui = open(fonte_ui, encoding="utf-8").read()
        except OSError as ex:
            falhar("testes.yml", "CanarioUITests.swift ilegivel: {}".format(ex))
        else:
            existentes = set(re.findall(r"func (test[A-Za-z0-9_]*)", texto_ui))
            pedidos = set(re.findall(
                r"-only-testing:CanarioUITests/CanarioUITests/([A-Za-z0-9_]+)",
                ui[0]))
            if not pedidos:
                falhar("testes.yml",
                       "o passo de UI nao seleciona nenhum teste por nome")
            for nome in sorted(pedidos - existentes):
                falhar("testes.yml",
                       "-only-testing pede {} , que nao existe em "
                       "CanarioUITests.swift: o CI passa rodando zero testes"
                       .format(nome))

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
    "sonda-edge-luna.yml", "testes.yml",
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
