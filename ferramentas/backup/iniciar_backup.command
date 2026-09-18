#!/bin/zsh
set -eu
umask 077
cd -- "${0:A:h}"
print 'Backup DataDrobe — produção será acessada somente em leitura.'
print 'A senha é digitada neste Terminal, sem aparecer na tela ou no chat.'
print ''
if ! /usr/local/bin/node backup_nativo.mjs backup; then
  print ''
  print 'O backup não foi concluído. A mensagem acima explica a etapa que falhou.'
  read '?Pressione Enter para fechar esta tentativa. '
  exit 1
fi
print ''
read '?Processo concluído. Pressione Enter para fechar. '
