#!/usr/bin/env bash
# Commita e empurra arquivos gerados por um workflow, com retry.
#
# Existe porque em 27/07 um push do coletor morreu com `remote: Internal Server
# Error` (500 do GitHub). O dado ja estava salvo no Supabase, mas o relatorio
# nao chegou ao repositorio e o job ficou vermelho por um erro de terceiro que
# passa sozinho. Erro transitorio merece retry, nao falha de coleta.
#
# Uso: bash .github/commitar.sh "ARQ1 ARQ2" "mensagem do commit"
set -uo pipefail

ARQUIVOS="$1"
MENSAGEM="$2"

git config user.name  "CanarioBot"
git config user.email "canarioch3@gmail.com"

# shellcheck disable=SC2086
git add $ARQUIVOS 2>/dev/null || true

if git diff --cached --quiet; then
  echo "Sem mudança em: $ARQUIVOS"
  exit 0
fi

git commit -m "$MENSAGEM [skip ci]"

for tentativa in 1 2 3 4 5; do
  if git push; then
    echo "Push OK na tentativa $tentativa."
    exit 0
  fi
  espera=$((tentativa * 15))
  echo "Push falhou (tentativa $tentativa). Novo trecho em ${espera}s..."
  sleep "$espera"
  # O remoto pode ter andado (outro workflow) ou ter dado 500: rebase e tenta de novo.
  git pull --rebase --autostash || true
done

echo "Push falhou nas 5 tentativas. O dado coletado está salvo no Supabase;"
echo "só o relatório no repositório ficou para trás."
exit 1
