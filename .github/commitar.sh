#!/usr/bin/env bash
# Commita e empurra arquivos GERADOS por um workflow, com retry.
#
# Existe porque em 27/07 um push do coletor morreu com `remote: Internal Server
# Error` (500 do GitHub). O dado ja estava salvo no Supabase, mas o relatorio
# nao chegou ao repositorio e o job ficou vermelho por um erro de terceiro que
# passa sozinho. Erro transitorio merece retry, nao falha de coleta.
#
# EM 01/08/2026 ELE QUEBROU DE OUTRO JEITO, e o conserto mudou a estrategia.
# A coleta de varejo das 05h04 falhou assim:
#
#   Push falhou (tentativa 5)
#   error: Pulling is not possible because you have unmerged files.
#   fatal: You are not currently on a branch.
#
# A sequencia foi: eu empurrei commits enquanto a coleta rodava, o push do bot
# bateu de frente, o `git pull --rebase` parou num CONFLITO no proprio SAUDE.md,
# e o rebase interrompido deixou o repositorio em HEAD solto com arquivo nao
# mesclado. Dali em diante toda tentativa falhava pelo estado, nao pelo remoto
# -- e num runner auto-hospedado esse estado sobrevive para a execucao seguinte.
#
# A CORRECAO: nunca tentar mesclar arquivo gerado.
#
# Relatorio de saude nao tem historia a preservar: a versao certa e sempre a
# que acabou de ser gerada. Entao, em vez de rebase, o retry limpa qualquer
# operacao pendente, volta ao estado do remoto e reaplica o arquivo por cima.
# Resolver conflito e para codigo escrito por gente; para arquivo gerado, o
# certo e regerar.
#
# Uso: bash .github/commitar.sh "ARQ1 ARQ2" "mensagem do commit"
set -uo pipefail

ARQUIVOS="$1"
MENSAGEM="$2"
RAMO="${GITHUB_REF_NAME:-main}"

git config user.name  "CanarioBot"
git config user.email "canarioch3@gmail.com"

# Guarda o conteudo gerado FORA da arvore de trabalho, para sobreviver ao
# `reset --hard` do retry.
GUARDA="$(mktemp -d)"
trap 'rm -rf "$GUARDA"' EXIT
for f in $ARQUIVOS; do
  if [ -f "$f" ]; then
    mkdir -p "$GUARDA/$(dirname "$f")"
    cp "$f" "$GUARDA/$f"
  fi
done

# Qualquer rebase ou merge pendente de uma execucao anterior morre aqui. Sem
# isto, um runner auto-hospedado carrega o conflito de ontem para hoje.
git rebase --abort  2>/dev/null || true
git merge  --abort  2>/dev/null || true
git cherry-pick --abort 2>/dev/null || true

restaurar() {
  for f in $ARQUIVOS; do
    if [ -f "$GUARDA/$f" ]; then
      mkdir -p "$(dirname "$f")"
      cp "$GUARDA/$f" "$f"
    fi
  done
}

preparar_commit() {
  # shellcheck disable=SC2086
  git add $ARQUIVOS 2>/dev/null || true
  if git diff --cached --quiet; then
    echo "Sem mudança em: $ARQUIVOS"
    return 1
  fi
  git commit -m "$MENSAGEM [skip ci]"
  return 0
}

# Garante que estamos NUM RAMO antes de commitar: o checkout do Actions pode
# deixar HEAD solto, e dali `git push` sem refspec nao funciona.
git checkout -B "$RAMO" 2>/dev/null || true

if ! preparar_commit; then
  exit 0
fi

for tentativa in 1 2 3 4 5; do
  if git push origin "HEAD:$RAMO"; then
    echo "Push OK na tentativa $tentativa."
    exit 0
  fi
  espera=$((tentativa * 15))
  echo "Push falhou (tentativa $tentativa). Nova tentativa em ${espera}s..."
  sleep "$espera"

  # O remoto andou (outro workflow, ou eu empurrando codigo). Em vez de mesclar,
  # adota o remoto e reaplica o arquivo gerado por cima.
  git fetch origin "$RAMO" || continue
  git checkout -B "$RAMO" "origin/$RAMO" || continue
  restaurar
  preparar_commit || exit 0
done

echo "Push falhou nas 5 tentativas. O dado coletado está salvo no Supabase;"
echo "só o relatório no repositório ficou para trás."
exit 1
