#!/bin/bash
set -euo pipefail
umask 077

AQUI="$(cd "$(dirname "$0")" && pwd)"
DESTINO="$HOME/.canario/runner-residencial"
PLIST_DESTINO="$HOME/Library/LaunchAgents/br.com.canario.runner-residencial.plist"
LABEL="br.com.canario.runner-residencial"
LABEL_TEMPORARIO="br.com.canario.observacao-runner"
DOMINIO="gui/$(id -u)"

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

mkdir -p "$DESTINO" "$HOME/Library/LaunchAgents" \
  "$HOME/Library/Logs/CanarioRunner"
install -m 700 "$AQUI/runner.sh" "$DESTINO/runner.sh"

TEMP_PLIST="$(mktemp "$HOME/Library/LaunchAgents/.canario-runner.XXXXXX")"
trap 'rm -f -- "$TEMP_PLIST"' EXIT
sed "s|__HOME__|$HOME|g" \
  "$AQUI/br.com.canario.runner-residencial.plist.in" > "$TEMP_PLIST"
plutil -lint "$TEMP_PLIST" >/dev/null
chmod 600 "$TEMP_PLIST"
mv "$TEMP_PLIST" "$PLIST_DESTINO"
trap - EXIT

CANARIO_RUNNER_BASE="$DESTINO" "$DESTINO/runner.sh" --check

launchctl bootout "$DOMINIO/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMINIO" "$PLIST_DESTINO"
launchctl enable "$DOMINIO/$LABEL"
echo "Runner residencial instalado. Ele aguardara o cron; nenhuma coleta foi disparada."
