#!/usr/bin/env node
/**
 * Executor do roteiro da etapa 1: um arquivo de passo por vez, um comando por
 * vez, na mesma sessão.
 *
 * POR QUE NÃO O EDITOR SQL
 * ========================
 *
 * `VACUUM` não roda dentro de bloco de transação, e uma string com mais de um
 * comando é um bloco implícito: `set lock_timeout = '5s'; vacuum full t;`
 * falha inteira (medido no PostgreSQL 17.10 do laboratório). Sem
 * `lock_timeout` na MESMA sessão, um `VACUUM FULL` que espera lock entra na
 * fila e trava todas as leituras que chegam depois dele. Este executor manda
 * cada comando sozinho, na mesma conexão, com os tempos-limite já definidos.
 *
 * O QUE ELE GARANTE
 * =================
 *
 *   - Sem `--executar`, NADA escreve: todo comando que não é a ação roda
 *     dentro de `begin transaction read only`, e a ação não é enviada.
 *   - Com `--executar`, só o comando marcado `-- @acao` escreve, e só depois
 *     que todas as pré-condições passaram. Pré-condição que falha aborta com
 *     código 1 antes da ação.
 *   - Mede a cota (soma de todos os bancos), o banco principal, o WAL e o
 *     alvo antes e depois, e imprime a diferença.
 *   - A senha é lida do terminal sem eco e fica só na memória deste processo.
 *     Não entra em argumento, variável de ambiente, arquivo nem saída.
 *
 * USO
 * ===
 *
 *   node ferramentas/capacidade/passo.mjs <passo.sql> \
 *     --host <host do pooler de SESSÃO> --porta 5432 \
 *     --usuario <usuario> [--banco postgres] [--executar]
 *
 * A porta 6543 (pooler de TRANSAÇÃO) é recusada: ali `set lock_timeout` não
 * sobrevive até o comando seguinte.
 *
 * No laboratório: `--socket <pasta> --usuario lab --senha-vazia`.
 */
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const CANDIDATOS = [
  path.join(os.homedir(), '.canario/laboratorio-capacidade/node_modules'),
  path.join(os.homedir(), '.canario/laboratorio-significado/node_modules'),
  path.join(AQUI, '../laboratorio_capacidade/node_modules'),
];

// Teclas lidas do terminal em modo cru, por código: Ctrl+C, Enter e apagar.
const CTRL_C = String.fromCharCode(3);
const ENTER = [String.fromCharCode(13), String.fromCharCode(10)];
const APAGAR = String.fromCharCode(127);

// Tempos da sessão. `lock_timeout` curto é a proteção contra a fila de locks;
// `statement_timeout` é o teto de cada comando, inclusive da ação.
const SESSAO = [
  "set application_name = 'datadrobe-etapa1'",
  "set lock_timeout = '5s'",
  "set statement_timeout = '180s'",
  "set idle_in_transaction_session_timeout = '60s'",
];

export function opcoes(argv) {
  const o = { arquivo: null, executar: false, banco: 'postgres', porta: 5432,
    senhaVazia: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--executar') o.executar = true;
    else if (a === '--senha-vazia') o.senhaVazia = true;
    else if (['--host', '--porta', '--usuario', '--banco', '--socket', '--modulos']
      .includes(a)) { o[a.slice(2)] = argv[i + 1]; i += 1; }
    else if (!a.startsWith('--') && !o.arquivo) o.arquivo = a;
    else throw new Error(`Opção desconhecida: ${a}`);
  }
  if (!o.arquivo) throw new Error('Informe o arquivo do passo.');
  if (!o.usuario) throw new Error('Informe --usuario.');
  if (!o.socket && !o.host) throw new Error('Informe --host (ou --socket no laboratório).');
  if (Number(o.porta) === 6543) {
    throw new Error('Porta 6543 é o pooler de transação: SET não sobrevive entre '
      + 'comandos. Use o pooler de sessão (5432) ou a conexão direta.');
  }
  return o;
}

/**
 * Divide o arquivo em comandos, respeitando `$$ ... $$`. Um comentário
 * `-- @acao` marca o comando seguinte como a ação do passo.
 */
export function comandos(sql) {
  const lista = [];
  let atual = '';
  let dolar = false;
  let acao = false;
  for (const linha of sql.split('\n')) {
    if (!dolar && /^\s*--\s*@acao\b/.test(linha)) { acao = true; continue; }
    if (!dolar && /^\s*--/.test(linha)) continue;
    const marcas = (linha.match(/\$\$/g) || []).length;
    if (marcas % 2 === 1) dolar = !dolar;
    atual += `${linha}\n`;
    if (!dolar && /;\s*$/.test(linha)) {
      if (atual.trim() !== ';') lista.push({ sql: atual.trim(), acao });
      atual = '';
      acao = false;
    }
  }
  if (atual.trim()) lista.push({ sql: atual.trim(), acao });
  if (lista.filter(c => c.acao).length > 1) {
    throw new Error('Um passo tem no máximo UMA ação.');
  }
  return lista;
}

async function senhaDoTerminal(pergunta) {
  if (!process.stdin.isTTY) throw new Error('A senha só é lida de um terminal.');
  process.stdout.write(pergunta);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  return new Promise((resolve, reject) => {
    let senha = '';
    const ler = (tecla) => {
      if (tecla === CTRL_C) {
        process.stdin.setRawMode(false);
        reject(new Error('Cancelado.'));
      } else if (ENTER.includes(tecla)) {
        process.stdin.setRawMode(false);
        process.stdin.pause();
        process.stdin.off('data', ler);
        process.stdout.write('\n');
        resolve(senha);
      } else if (tecla === APAGAR) {
        senha = senha.slice(0, -1);
      } else {
        senha += tecla;
      }
    };
    process.stdin.on('data', ler);
  });
}

const MEDIDA = `
  select (select sum(pg_database_size(oid)) from pg_database)::bigint as cota,
         pg_database_size(current_database())::bigint as principal,
         (select coalesce(sum(size), 0) from pg_ls_waldir())::bigint as wal,
         current_setting('default_transaction_read_only') as somente_leitura`;

function mb(n) { return `${(Number(n) / 1e6).toFixed(2)} MB`; }

async function medir(cliente, alvo) {
  await cliente.query('begin transaction read only');
  try {
    const { rows: [m] } = await cliente.query(MEDIDA);
    if (alvo) {
      const { rows: [a] } = await cliente.query(
        'select pg_total_relation_size($1::regclass)::bigint as alvo', [alvo]);
      m.alvo = a.alvo;
    }
    return m;
  } finally {
    await cliente.query('commit');
  }
}

async function main() {
  const o = opcoes(process.argv.slice(2));
  const texto = await readFile(o.arquivo, 'utf8');
  const lista = comandos(texto);
  const alvo = (texto.match(/^\s*--\s*@alvo\s+(\S+)/m) || [])[1] || null;
  // Passo que devolve espaco e nao encolhe o alvo falhou em silencio: VACUUM
  // sem permissao, por exemplo, PULA a tabela com um aviso e sai com sucesso.
  const esperaEncolher = /^\s*--\s*@espera_encolher\b/m.test(texto);
  const acao = lista.find(c => c.acao);

  const modulos = o.modulos || CANDIDATOS.find(c => {
    try { createRequire(path.join(c, 'index.js')).resolve('pg'); return true; }
    catch { return false; }
  });
  if (!modulos) throw new Error('Não achei o pacote `pg`. Veja o README do laboratório.');
  const pg = createRequire(path.join(modulos, 'index.js'))('pg');

  const senha = o.senhaVazia ? undefined
    : await senhaDoTerminal(`Senha de ${o.usuario} (não aparece na tela): `);
  const cliente = new pg.Client({
    host: o.socket || o.host, port: Number(o.porta), user: o.usuario,
    database: o.banco, password: senha,
    ssl: o.socket ? false : { rejectUnauthorized: false },
    connectionTimeoutMillis: 10_000,
  });
  await cliente.connect();
  cliente.on('notice', n => console.log(`  aviso: ${n.message}`));
  try {
    for (const s of SESSAO) await cliente.query(s);
    if (o.executar && acao) {
      // A documentação do Supabase manda fazer isto quando o projeto já está
      // em somente-leitura: sem, a ação que libera espaço seria recusada.
      await cliente.query('set session characteristics as transaction read write');
    }

    console.log(`passo: ${path.basename(o.arquivo)}${alvo ? ` · alvo ${alvo}` : ''}`);
    const antes = await medir(cliente, alvo);
    console.log(`antes: cota ${mb(antes.cota)} · principal ${mb(antes.principal)}`
      + ` · WAL ${mb(antes.wal)}${alvo ? ` · alvo ${mb(antes.alvo)}` : ''}`
      + ` · somente-leitura ${antes.somente_leitura}`);

    for (const c of lista) {
      if (c.acao) continue;
      if (/^set\s/i.test(c.sql)) { await cliente.query(c.sql); continue; }
      await cliente.query('begin transaction read only');
      try {
        const r = await cliente.query(c.sql);
        for (const linha of [].concat(r).flatMap(x => x.rows || [])) {
          console.log(`  ${JSON.stringify(linha)}`);
        }
        await cliente.query('commit');
      } catch (erro) {
        await cliente.query('rollback').catch(() => {});
        throw new Error(`pré-condição/consulta falhou -- nada foi executado: ${erro.message}`);
      }
    }

    if (!acao) {
      console.log('passo sem ação: só leitura.');
      return;
    }
    if (!o.executar) {
      console.log(`ENSAIO: pré-condições verdes. A ação NÃO foi enviada:\n  ${acao.sql}`);
      return;
    }
    const t0 = Date.now();
    console.log(`executando: ${acao.sql}`);
    await cliente.query(acao.sql);
    const segundos = ((Date.now() - t0) / 1000).toFixed(1);
    const depois = await medir(cliente, alvo);
    console.log(`depois (${segundos} s): cota ${mb(depois.cota)} (${mb(depois.cota - antes.cota)})`
      + ` · principal ${mb(depois.principal)} (${mb(depois.principal - antes.principal)})`
      + ` · WAL ${mb(depois.wal)}`
      + (alvo ? ` · alvo ${mb(depois.alvo)} (${mb(depois.alvo - antes.alvo)})` : ''));
    if (esperaEncolher && alvo && Number(depois.alvo) >= Number(antes.alvo)) {
      throw new Error(`o alvo ${alvo} não encolheu (${antes.alvo} -> ${depois.alvo} bytes). `
        + 'Pare e revise antes do próximo passo.');
    }
  } finally {
    await cliente.end();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch(erro => {
    console.error(`FALHOU: ${erro.message}`);
    process.exit(1);
  });
}
