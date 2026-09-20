#!/bin/bash
# Runner residencial diario do Canario.
#
# Cria um runner efemero em cada janela, acompanha somente as execucoes
# agendadas e o remove ao terminar. O LaunchAgent e permanente; credenciais do
# GitHub Actions nao ficam registradas entre as janelas.

set -euo pipefail
umask 077

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GH_REPO="JogzDev/canario"

BASE="${CANARIO_RUNNER_BASE:-$HOME/.canario/runner-residencial}"
CACHE="$BASE/cache"
RUNS="$BASE/runs"
LOGS="$HOME/Library/Logs/CanarioRunner"
LOCK="$BASE/em-execucao"
RUNNER_VERSION="2.337.0"
RUNNER_SHA256="5a2cd92908a93d7276a194e1de6008099f3e7946f3f8e14aa7a1a7b4a31fdec2"
RUNNER_ARCHIVE="$CACHE/actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"
WORKFLOW_PIPELINE="pipeline-diario.yml"
WORKFLOW_CANDIDATO="coleta-catalogo-candidato.yml"
WORKFLOW_VERIFICAR="verificar-producao.yml"
# O GitHub criou o pipeline de 19/09 com 3h51 de atraso e ja atrasou o
# catalogo candidato em ate 5h27. A janela do runner precisa cobrir o fato
# observado, sem disparar uma segunda coleta que poderia duplicar escritas.
ESPERA_PIPELINE_SEGUNDOS=28800
JANELA_CANDIDATO_SEGUNDOS=43200

mkdir -p "$CACHE" "$RUNS" "$LOGS"
LOG="$LOGS/$(date '+%Y-%m-%d').log"
exec >>"$LOG" 2>&1

agora() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s %s\n' "$(agora)" "$*"; }

abrir_incidente() {
  local titulo="$1" corpo="$2" existente
  existente="$(gh issue list --repo "$GH_REPO" --state open --limit 100 \
    --json number,title --jq ".[] | select(.title == \"$titulo\") | .number" \
    2>/dev/null | head -1 || true)"
  if [ -n "$existente" ]; then
    gh issue comment "$existente" --repo "$GH_REPO" --body "$corpo" >/dev/null 2>&1 || true
  else
    gh issue create --repo "$GH_REPO" --title "$titulo" --body "$corpo" >/dev/null 2>&1 || true
  fi
}

parar_coletas() {
  local motivo="$1"
  gh workflow disable "$WORKFLOW_PIPELINE" --repo "$GH_REPO" >/dev/null 2>&1 || true
  gh workflow disable "$WORKFLOW_CANDIDATO" --repo "$GH_REPO" >/dev/null 2>&1 || true
  abrir_incidente "[Canario] pipeline residencial interrompido" "$motivo"
  log "COLETAS INTERROMPIDAS: $motivo"
}

adquirir_lock() {
  local pid_antigo="" comando_antigo=""
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK/pid"
    return 0
  fi

  if [ -f "$LOCK/pid" ]; then
    pid_antigo="$(sed -n '1p' "$LOCK/pid" 2>/dev/null || true)"
  fi
  if [[ "$pid_antigo" =~ ^[0-9]+$ ]] && kill -0 "$pid_antigo" 2>/dev/null; then
    comando_antigo="$(ps -p "$pid_antigo" -o command= 2>/dev/null || true)"
    if [[ "$comando_antigo" == *"$BASE/runner.sh"* ]]; then
      log "Outra janela do runner ja esta ativa no pid $pid_antigo; saindo."
      return 1
    fi
  fi

  # O pid nao existe ou nao pertence a este runner. Remove somente o lock
  # conhecido; nunca amplia o alvo para BASE ou para um caminho recebido.
  rm -f -- "$LOCK/pid"
  if ! rmdir "$LOCK" 2>/dev/null || ! mkdir "$LOCK" 2>/dev/null; then
    log "Lock residual nao pôde ser recuperado com seguranca: $LOCK."
    return 1
  fi
  printf '%s\n' "$$" > "$LOCK/pid"
  log "Lock residual sem processo ativo foi recuperado."
}

limpar_registros_orfaos() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    gh api -X DELETE "repos/$GH_REPO/actions/runners/$id" >/dev/null
    log "Registro orfao do runner residencial removido: $id."
  done < <(gh api "repos/$GH_REPO/actions/runners" \
    --jq '.runners[] | select(.name|startswith("canario-residencial-")) | .id' \
    2>/dev/null || true)
}

listener_local_ativo() {
  pgrep -f "^$RUNS/runner[.][^/]*/bin/Runner[.]Listener run$" >/dev/null 2>&1
}

workflow_ativo() {
  gh api "repos/$GH_REPO/actions/workflows/$1" --jq '.state' 2>/dev/null | grep -qx active
}

obter_run_nova() {
  local workflow="$1" evento="$2" inicio="$3"
  gh run list --repo "$GH_REPO" --workflow "$workflow" --event "$evento" --limit 20 \
    --json databaseId,createdAt \
    --jq ".[] | select(.createdAt >= \"$inicio\") | .databaseId" 2>/dev/null | head -1
}

esperar_run() {
  local run_id="$1" limite_epoch="$2" estado conclusao
  while [ "$(date -u '+%s')" -lt "$limite_epoch" ]; do
    if [ -n "${LISTENER_PID:-}" ] \
        && ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      log "Runner local encerrou enquanto a execucao $run_id ainda precisava dele."
      return 2
    fi
    estado="$(gh run view "$run_id" --repo "$GH_REPO" --json status --jq '.status' 2>/dev/null || true)"
    if [ "$estado" = completed ]; then
      conclusao="$(gh run view "$run_id" --repo "$GH_REPO" --json conclusion --jq '.conclusion' 2>/dev/null || true)"
      [ "$conclusao" = success ]
      return
    fi
    sleep 30
  done
  return 1
}

dia_de_candidato() {
  case "$(TZ=America/Sao_Paulo date '+%u')" in
    1|4) return 0 ;;
    *) return 1 ;;
  esac
}

medir_observacao() {
  local segmento="$1" contexto="$2" inicio run_id="" cota_pct
  inicio="$(agora)"
  gh workflow run "$WORKFLOW_VERIFICAR" --repo "$GH_REPO" --ref main \
    -f segmento="$segmento"
  for _ in $(seq 1 30); do
    run_id="$(obter_run_nova "$WORKFLOW_VERIFICAR" workflow_dispatch "$inicio")"
    [ -n "$run_id" ] && break
    sleep 2
  done
  if [ -z "$run_id" ] || ! esperar_run "$run_id" $(( $(date -u '+%s') + 900 )); then
    parar_coletas "A verificacao read-only de producao falhou $contexto em $(agora)."
    return 1
  fi

  cota_pct="$(gh run view "$run_id" --repo "$GH_REPO" --log 2>/dev/null \
    | sed -nE 's/.*Cota: ([0-9]+([.][0-9]+)?)%.*/\1/p' | tail -1)"
  if [ -z "$cota_pct" ]; then
    parar_coletas "A verificacao $run_id terminou sem uma medida de capacidade legivel $contexto em $(agora)."
    return 1
  fi
  log "Capacidade $contexto: $cota_pct%."
  if awk "BEGIN { exit !($cota_pct > 85.0) }"; then
    parar_coletas "A cota chegou a $cota_pct% $contexto, acima do limite de observacao de 85%."
    return 1
  fi
}

garantir_archive() {
  local atual=""
  if [ -f "$RUNNER_ARCHIVE" ]; then
    atual="$(shasum -a 256 "$RUNNER_ARCHIVE" | awk '{print $1}')"
  fi
  if [ "$atual" != "$RUNNER_SHA256" ]; then
    rm -f -- "$RUNNER_ARCHIVE"
    log "Baixando runner autenticado v$RUNNER_VERSION."
    curl --proto '=https' --tlsv1.2 -fL "$RUNNER_URL" -o "$RUNNER_ARCHIVE.tmp"
    printf '%s  %s\n' "$RUNNER_SHA256" "$RUNNER_ARCHIVE.tmp" | shasum -a 256 -c -
    mv "$RUNNER_ARCHIVE.tmp" "$RUNNER_ARCHIVE"
  fi
}

MODO="${1:-}"
RUN_ADOTADA="${2:-}"

if [ "$MODO" = --check ]; then
  command -v gh >/dev/null
  command -v curl >/dev/null
  command -v shasum >/dev/null
  gh auth status --hostname github.com >/dev/null
  garantir_archive
  log "CHECK OK: ferramentas, autenticacao e pacote do runner verificados."
  exit 0
fi

if ! workflow_ativo "$WORKFLOW_PIPELINE"; then
  log "Pipeline esta desativado; nenhuma credencial de runner foi criada."
  exit 0
fi

if ! adquirir_lock; then
  exit 0
fi

if listener_local_ativo; then
  log "Listener local ja esta ativo sem lock confiavel; recusando duplicata."
  rm -f -- "$LOCK/pid"
  rmdir "$LOCK" 2>/dev/null || true
  exit 0
fi

limpar_registros_orfaos

RUNROOT=""
RUNNER_NAME=""
LISTENER_PID=""
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [ -n "$RUNROOT" ] && [[ "$RUNROOT" == "$RUNS/"* ]]; then
    # `run.sh` cria dois wrappers; sinalizar apenas o shell externo nao chega
    # ao Listener quando nao ha TTY. O caminho absoluto limita o alvo ao
    # runner desta janela, e TERM faz o Listener encerrar graciosamente.
    while IFS= read -r pid; do
      [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
    done < <(pgrep -f "^$RUNROOT/bin/Runner.Listener run$" 2>/dev/null || true)
  fi
  if [ -n "$LISTENER_PID" ] && kill -0 "$LISTENER_PID" 2>/dev/null; then
    for _ in $(seq 1 15); do
      kill -0 "$LISTENER_PID" 2>/dev/null || break
      sleep 1
    done
    kill -TERM "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
  fi
  if [ -n "$RUNNER_NAME" ]; then
    runner_id="$(gh api "repos/$GH_REPO/actions/runners" \
      --jq ".runners[] | select(.name == \"$RUNNER_NAME\") | .id" \
      2>/dev/null | head -1 || true)"
    if [ -n "$runner_id" ]; then
      gh api -X DELETE "repos/$GH_REPO/actions/runners/$runner_id" >/dev/null 2>&1 || true
    fi
  fi
  if [ -n "$RUNROOT" ] && [[ "$RUNROOT" == "$RUNS/"* ]]; then
    rm -rf -- "$RUNROOT"
  fi
  rm -f -- "$LOCK/pid"
  rmdir "$LOCK" 2>/dev/null || true
  log "Runner efemero removido; encerramento rc=$rc."
  exit "$rc"
}
trap cleanup EXIT INT TERM

garantir_archive
RUNROOT="$(mktemp -d "$RUNS/runner.XXXXXX")"
tar xzf "$RUNNER_ARCHIVE" -C "$RUNROOT"
RUNNER_NAME="canario-residencial-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
TOKEN="$(gh api -X POST "repos/$GH_REPO/actions/runners/registration-token" --jq '.token')"
(
  cd "$RUNROOT"
  ./config.sh --unattended --url "https://github.com/$GH_REPO" --token "$TOKEN" \
    --name "$RUNNER_NAME" --labels sempre-ligado,xcode --work _work --replace
)
unset TOKEN

(
  cd "$RUNROOT"
  ./run.sh
) &
LISTENER_PID=$!
log "Runner $RUNNER_NAME iniciado."

if [ "$MODO" = --smoke ]; then
  ONLINE=""
  for _ in $(seq 1 30); do
    ONLINE="$(gh api "repos/$GH_REPO/actions/runners" \
      --jq ".runners[] | select(.name == \"$RUNNER_NAME\" and .status == \"online\") | .id" \
      2>/dev/null | head -1 || true)"
    [ -n "$ONLINE" ] && break
    sleep 2
  done
  if [ -z "$ONLINE" ]; then
    log "SMOKE FALHOU: runner nao ficou online."
    exit 1
  fi
  log "SMOKE OK: runner ficou online e sera removido sem receber trabalho."
  exit 0
fi

RUN_ID=""
INICIO_ISO="$(agora)"
JANELA_INICIO_EPOCH="$(date -u '+%s')"
if [ "$MODO" = --adopt ]; then
  if ! [[ "$RUN_ADOTADA" =~ ^[0-9]+$ ]]; then
    log "--adopt exige o id numerico de uma execucao."
    exit 1
  fi
  RUN_META="$(gh api "repos/$GH_REPO/actions/runs/$RUN_ADOTADA" \
    --jq '[.event,.status,.path] | @tsv')"
  if ! printf '%s\n' "$RUN_META" | grep -Eq \
      '^schedule[[:space:]]+(queued|in_progress)[[:space:]]+\.github/workflows/pipeline-diario\.yml(@|$)'; then
    log "Execucao $RUN_ADOTADA nao e um pipeline agendado adotavel: $RUN_META"
    exit 1
  fi
  RUN_ID="$RUN_ADOTADA"
  log "Adotando pipeline agendado que ja estava na fila: $RUN_ID."
else
  # O cron do GitHub e 06:00 UTC. Nao criamos uma segunda execucao: esperamos
  # a agendada dentro da maior janela sustentada pelos atrasos observados.
  ESPERA_ATE=$(( JANELA_INICIO_EPOCH + ESPERA_PIPELINE_SEGUNDOS ))
  while [ "$(date -u '+%s')" -lt "$ESPERA_ATE" ]; do
    RUN_ID="$(obter_run_nova "$WORKFLOW_PIPELINE" schedule "$INICIO_ISO")"
    [ -n "$RUN_ID" ] && break
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      parar_coletas "O runner residencial encerrou antes de receber o pipeline em $(agora)."
      exit 1
    fi
    sleep 20
  done
fi

if [ -z "$RUN_ID" ]; then
  parar_coletas "A execucao agendada do pipeline nao apareceu dentro da janela de oito horas em $(agora)."
  exit 1
fi

log "Acompanhando pipeline $RUN_ID."
if ! esperar_run "$RUN_ID" $(( $(date -u '+%s') + 28800 )); then
  parar_coletas "O pipeline $RUN_ID falhou ou excedeu oito horas em $(agora). Consulte a execucao no GitHub Actions."
  exit 1
fi
log "Pipeline $RUN_ID concluido com sucesso."

# O proprio pipeline, no job `publicacao`, ja prova as duas RPCs datadas depois
# do motor. Nao repetir aqui a sonda manual de contrato: ela inclui a busca
# editorial, que nao carrega a data do painel e pode ter timeout transitorio.

# Medicao oficial hospedada. Acima de 85%, ou sem medicao confiavel, a
# observacao para antes da proxima escrita.
medir_observacao direcao_intl "depois do pipeline $RUN_ID" || exit 1

# Segunda e quinta possuem uma segunda execucao agendada. Ela pode nascer
# horas depois do horario nominal; o runner permanece disponivel, acompanha a
# run exata e mede de novo antes de se remover. Nos outros dias ele sai cedo.
if dia_de_candidato && workflow_ativo "$WORKFLOW_CANDIDATO"; then
  CANDIDATO_ID="$(obter_run_nova "$WORKFLOW_CANDIDATO" schedule "$INICIO_ISO")"
  CANDIDATO_ATE=$(( JANELA_INICIO_EPOCH + JANELA_CANDIDATO_SEGUNDOS ))
  while [ -z "$CANDIDATO_ID" ] && [ "$(date -u '+%s')" -lt "$CANDIDATO_ATE" ]; do
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      parar_coletas "O runner residencial encerrou enquanto aguardava o catalogo candidato em $(agora)."
      exit 1
    fi
    sleep 20
    CANDIDATO_ID="$(obter_run_nova "$WORKFLOW_CANDIDATO" schedule "$INICIO_ISO")"
  done
  if [ -z "$CANDIDATO_ID" ]; then
    parar_coletas "A execucao agendada do catalogo candidato nao apareceu dentro da janela observada em $(agora)."
    exit 1
  fi
  log "Acompanhando catalogo candidato $CANDIDATO_ID."
  if ! esperar_run "$CANDIDATO_ID" $(( $(date -u '+%s') + 28800 )); then
    parar_coletas "O catalogo candidato $CANDIDATO_ID falhou ou excedeu oito horas em $(agora)."
    exit 1
  fi
  log "Catalogo candidato $CANDIDATO_ID concluido com sucesso."
  medir_observacao catalogo_candidato_br \
    "depois do catalogo candidato $CANDIDATO_ID" || exit 1
fi

log "Janela diaria completa e verde; o runner sera removido agora."
