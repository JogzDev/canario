#!/usr/bin/env node
/**
 * A50 -> A59 num PostgreSQL 17.10 descartável, sem conexão com produção.
 * Usa os mesmos módulos instalados para laboratorio_significado; no CI, passe
 * --modulos "$HOME/.canario/laboratorio-significado/node_modules".
 */
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { access, chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORIO = path.resolve(AQUI, '../..');
const MODULOS_PADRAO = path.join(os.homedir(), '.canario/laboratorio-significado/node_modules');
const AMBIENTE = { PATH: '/usr/local/bin:/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', TZ: 'UTC' };

function exigir(condicao, mensagem) {
  if (!condicao) throw new Error(mensagem);
}

function executar(binario, args, timeout = 120_000) {
  return new Promise((resolve, reject) => {
    const filho = spawn(binario, args, { env: AMBIENTE, stdio: ['ignore', 'pipe', 'pipe'] });
    let erro = '';
    const relogio = setTimeout(() => {
      filho.kill('SIGTERM');
      reject(new Error(`Tempo esgotado: ${path.basename(binario)}`));
    }, timeout);
    filho.stdout.resume();
    filho.stderr.on('data', d => { erro = `${erro}${d}`.slice(-4096); });
    filho.on('error', e => { clearTimeout(relogio); reject(e); });
    filho.on('close', codigo => {
      clearTimeout(relogio);
      if (codigo === 0) resolve();
      else reject(new Error(`${path.basename(binario)}: ${erro.trim()}`));
    });
  });
}

async function main() {
  exigir(process.getuid?.() !== 0, 'Rode como usuário comum, sem root.');
  const args = process.argv.slice(2);
  exigir(args.length === 0 || (args.length === 2 && args[0] === '--modulos'),
    'Uso: rodar.mjs [--modulos <node_modules>]');
  const modulos = args[1] ?? MODULOS_PADRAO;
  await access(path.join(modulos, 'pg'));
  const require = createRequire(path.join(modulos, 'index.js'));
  const binarios = require(`@embedded-postgres/${process.platform}-${process.arch}`);
  const pg = require('pg');
  for (const nome of ['initdb', 'postgres', 'pg_ctl']) await chmod(binarios[nome], 0o755);

  const raiz = await mkdtemp(path.join(os.tmpdir(), 'datadrobe-apple-'));
  await chmod(raiz, 0o700);
  const dados = path.join(raiz, 'data');
  const socket = path.join(raiz, 'sock');
  const senhaArquivo = path.join(raiz, 'senha');
  const senha = randomBytes(24).toString('hex');
  await mkdir(socket, { mode: 0o700 });
  await writeFile(senhaArquivo, senha, { mode: 0o600 });
  let processo;
  let cliente;
  try {
    await executar(binarios.initdb, [
      '-D', dados, '-U', 'lab', '--pwfile', senhaArquivo,
      '--auth=scram-sha-256', '--encoding=UTF8', '--no-locale',
    ]);
    processo = spawn(binarios.postgres, [
      '-D', dados, '-k', socket, '-h', '', '-p', '5432',
      '-c', 'listen_addresses=', '-c', 'fsync=off', '-c', 'log_min_messages=warning',
    ], { env: AMBIENTE, stdio: ['ignore', 'pipe', 'pipe'] });
    processo.stdout.resume();
    processo.stderr.resume();
    const conexao = { host: socket, port: 5432, user: 'lab', password: senha,
      database: 'postgres', connectionTimeoutMillis: 5_000 };
    for (let tentativa = 0; tentativa < 50 && !cliente; tentativa += 1) {
      const candidato = new pg.Client(conexao);
      try { await candidato.connect(); cliente = candidato; }
      catch { await new Promise(r => setTimeout(r, 200)); }
    }
    exigir(cliente, 'Cluster não aceitou conexão.');

    await cliente.query(`
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin bypassrls;
      create schema auth;
      create table auth.users (id uuid primary key);
      insert into auth.users values
        ('00000000-0000-4000-8000-000000000001'),
        ('00000000-0000-4000-8000-000000000002'),
        ('00000000-0000-4000-8000-000000000003');
    `);
    const migracoes = [
      '20260831152000_a50_tokens_de_revogacao_apple.sql',
      '20260921164500_a59_cifra_tokens_de_revogacao_apple.sql',
    ];
    const aplicar = async nome => cliente.query(await readFile(
      path.join(REPOSITORIO, 'supabase/migrations', nome), 'utf8'));
    await aplicar(migracoes[0]);
    await cliente.query(`insert into public.apple_refresh_tokens (user_id, refresh_token)
      values ('00000000-0000-4000-8000-000000000001',
              'token-legado-sintetico-123456');`);
    await aplicar(migracoes[1]);
    await aplicar(migracoes[1]); // Reaplicação não deve destruir linhas.
    const { rows: legado } = await cliente.query(`select refresh_token,
      refresh_token_cifrado from public.apple_refresh_tokens
      where user_id = '00000000-0000-4000-8000-000000000001'`);
    exigir(legado.length === 1 && legado[0].refresh_token === 'token-legado-sintetico-123456'
      && legado[0].refresh_token_cifrado === null,
    'A59 perdeu uma credencial A50 existente');
    console.log('ok 1: legado A50 continua legível após aplicação e reaplicação');

    const novo = `insert into public.apple_refresh_tokens
      (user_id, refresh_token, refresh_token_cifrado, nonce_cifragem,
       versao_chave, algoritmo_cifragem) values
      ('00000000-0000-4000-8000-000000000002', null, $1, $2, 1, 'aes-256-gcm-v1')`;
    const cifra = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=';
    const nonce = 'QUJDREVGR0hJSktM';
    await cliente.query(novo, [cifra, nonce]);
    await cliente.query(`update public.apple_refresh_tokens set
      refresh_token = null, refresh_token_cifrado = $1,
      nonce_cifragem = $2, versao_chave = 2,
      algoritmo_cifragem = 'aes-256-gcm-v1'
      where user_id = '00000000-0000-4000-8000-000000000001'`, [cifra, nonce]);
    const { rows: convertidas } = await cliente.query(`select count(*)::int as n
      from public.apple_refresh_tokens
      where refresh_token is null and refresh_token_cifrado is not null`);
    exigir(convertidas[0].n === 2, 'Formato cifrado não aceitou nova linha e conversão');
    console.log('ok 2: cifra nova e conversão de legado aceitas');

    const rejeitar = async (rotulo, sql, parametros = []) => {
      try { await cliente.query(sql, parametros); }
      catch (erro) {
        exigir(erro.code === '23514', `${rotulo}: erro inesperado ${erro.code}`);
        console.log(`ok ${rotulo}: CHECK rejeitou linha inválida`);
        return;
      }
      throw new Error(`${rotulo}: CHECK aceitou linha inválida`);
    };
    const base = `insert into public.apple_refresh_tokens
      (user_id, refresh_token, refresh_token_cifrado, nonce_cifragem,
       versao_chave, algoritmo_cifragem) values
      ('00000000-0000-4000-8000-000000000003', $1, $2, $3, $4, $5)`;
    await rejeitar(3, base, [null, null, null, null, null]);
    await rejeitar(4, base, [null, cifra, null, 1, 'aes-256-gcm-v1']);
    await rejeitar(5, base, ['token-legado-sintetico-123456', cifra, nonce, 1,
      'aes-256-gcm-v1']);
    await rejeitar(6, base, [null, cifra, nonce, 1, 'aes-128-cbc']);
    await rejeitar(7, base, [null, cifra, 'curto', 1, 'aes-256-gcm-v1']);

    const { rows: acesso } = await cliente.query(`select
      has_table_privilege('anon', 'public.apple_refresh_tokens', 'select') as anon_le,
      has_table_privilege('authenticated', 'public.apple_refresh_tokens', 'select') as usuario_le,
      has_table_privilege('service_role', 'public.apple_refresh_tokens', 'select') as servico_le,
      c.relrowsecurity as rls, c.relforcerowsecurity as force_rls
      from pg_class c where c.oid = 'public.apple_refresh_tokens'::regclass`);
    exigir(acesso.length === 1 && !acesso[0].anon_le && !acesso[0].usuario_le
      && acesso[0].servico_le && acesso[0].rls && acesso[0].force_rls,
    'A59 alargou acesso à credencial Apple');
    console.log('ok 8: privilégios e FORCE RLS preservados');
    console.log('LABORATORIO APPLE VERDE');
  } finally {
    if (cliente) await cliente.end().catch(() => {});
    if (processo && processo.exitCode === null) {
      await executar(binarios.pg_ctl, ['stop', '-D', dados, '-m', 'fast', '-w', '-t', '10'])
        .catch(() => processo.kill('SIGKILL'));
      if (processo.exitCode === null) await once(processo, 'exit');
    }
    await rm(raiz, { recursive: true, force: true });
  }
}

main().catch(erro => { console.error(`FALHOU: ${erro.message}`); process.exit(1); });
