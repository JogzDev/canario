#!/usr/bin/env node
// Compatibilidade de nome; restauração nativa com pg_restore e manifesto novo.
import { main } from './backup_nativo.mjs';
const args = process.argv.slice(2).map(a => a === '--dump' ? '--dest' : a);
main(['restore', ...args]).catch(error => {
  console.error(`FALHOU: ${error.message}`);
  process.exitCode = 1;
});
