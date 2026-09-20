#!/bin/bash
set -euo pipefail
umask 077

AQUI="$(cd "$(dirname "$0")" && pwd)"
DESTINO="$HOME/.canario/runner-residencial"
PLIST_DESTINO="$HOME/Library/LaunchAgents/br.com.canario.runner-residencial.plist"
LABEL="br.com.canario.runner-residencial"
LABEL_TEMPORARIO="br.com.canario.observacao-runner"
DOMINIO="gui/$(id -u)"
LOCK="$DESTINO/em-execucao"

runner_permanente_em_execucao() {
  local pid="" comando=""

  if launchctl print "$DOMINIO/$LABEL" 2>/dev/null \
      | grep -q 'state = running'; then
    return 0
  fi

  if [ -f "$LOCK/pid" ]; then
    pid="$(sed -n '1p' "$LOCK/pid" 2>/dev/null || true)"
  fi
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    comando="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$comando" == *"$DESTINO/runner.sh"* ]]; then
      return 0
    fi
  fi

  pgrep -f "$DESTINO/runner.sh" >/dev/null 2>&1
}

if runner_permanente_em_execucao; then
  echo "RECUSADO: o runner residencial esta executando uma janela."
  echo "Espere a execucao terminar antes de atualizar o script instalado."
  exit 1
fi

if launchctl print "$DOMINIO/$LABEL_TEMPORARIO" >/dev/null 2>&1; then
  echo "RECUSADO: o supervisor temporario ainda esta instalado."
  echo "Espere a observacao terminar ou remova-o conscientemente antes da troca."
  exit 1
fi

command -v gh >/dev/null
command -v plutil >/dev/null
command -v sed >/dev/null
gh auth status --hostname github.com >/dev/null
bash -n "$AQUI/runner.sh"
plutil -lint "$AQUI/br.com.canario.runner-residencial.plist.in" >/dev/null
CANARIO_RUNNER_BASE="$DESTINO" "$AQUI/runner.sh" --check

mkdir -p "$DESTINO" "$HOME/Library/LaunchAgents" \
  "$HOME/Library/Logs/CanarioRunner"

TEMP_PLIST="$(mktemp "$HOME/Library/LaunchAgents/.canario-runner.XXXXXX")"
trap 'rm -f -- "$TEMP_PLIST"' EXIT
sed "s|__HOME__|$HOME|g" \
  "$AQUI/br.com.canario.runner-residencial.plist.in" > "$TEMP_PLIST"
plutil -lint "$TEMP_PLIST" >/dev/null
chmod 600 "$TEMP_PLIST"

launchctl bootout "$DOMINIO/$LABEL" >/dev/null 2>&1 || true
install -m 700 "$AQUI/runner.sh" "$DESTINO/runner.sh"
mv "$TEMP_PLIST" "$PLIST_DESTINO"
trap - EXIT
launchctl bootstrap "$DOMINIO" "$PLIST_DESTINO"
launchctl enable "$DOMINIO/$LABEL"
echo "Runner residencial instalado. Ele aguardara o cron; nenhuma coleta foi disparada."
