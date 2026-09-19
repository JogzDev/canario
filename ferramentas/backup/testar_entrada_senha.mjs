import assert from 'node:assert/strict';
import { normalizarEntradaSenha } from './backup_nativo.mjs';

// Dados estritamente fictícios, sem ler clipboard, chaveiro ou produção.
const exemplo = '  Senha_FICTICIA:$`!& á🎨  ';
assert.equal(normalizarEntradaSenha(exemplo),exemplo);
assert.equal(normalizarEntradaSenha('\u001b[200~'+exemplo+'\u001b[201~'),exemplo);
assert.throws(()=>normalizarEntradaSenha('\u001b[200~incompleto'),/caracteres de controle/);
assert.throws(()=>normalizarEntradaSenha('linha\nextra'),/caracteres de controle/);
assert.throws(()=>normalizarEntradaSenha(''),/Senha vazia/);
console.log('Entrada de senha: colagem com/sem envelope, símbolos e espaços preservados; controles rejeitados.');
