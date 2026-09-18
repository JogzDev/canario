#!/bin/zsh
set -eu
umask 077
cd -- "${0:A:h}"
print 'Backup DataDrobe — produção será acessada somente em leitura.'
print 'A senha é digitada neste Terminal, sem aparecer na tela ou no chat.'
print ''
/usr/local/bin/node backup_nativo.mjs backup
print ''
read '?Processo concluído. Pressione Enter para fechar. '
