#!/bin/bash
set -euo pipefail

DESTINO="$HOME/.canario/runner-residencial"
PLIST="$HOME/Library/LaunchAgents/br.com.canario.runner-residencial.plist"
LABEL="br.com.canario.runner-residencial"
DOMINIO="gui/$(id -u)"

launchctl bootout "$DOMINIO/$LABEL" >/dev/null 2>&1 || true
rm -f -- "$PLIST"
if [ -d "$DESTINO" ]; then
  rm -rf -- "$DESTINO"
fi
echo "Runner residencial removido. Workflows e dados do GitHub nao foram alterados."
