#!/usr/bin/env node
// Somente fixtures e clusters locais descartáveis. Não usa arquivo de conexão,
// senha de produção, keychain ou qualquer host remoto.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import os from 'node:os';
import path from 'node:path';
import { capture, digestTableEmBlocos, digestTableSql, localCluster, restore, verifyExisting, LEITURA_SETUP, SQL_DIGEST_METHOD } from './backup_nativo.mjs';

const bin = path.join(os.homedir(), '.local/share/datadrobe-tools/Postgres.app/Contents/Versions/17/bin');
const root = await mkdtemp(path.join(os.tmpdir(), 'dd-verificacao-blocos-'));
const origem = await localCluster(bin);
let snapshot;

// Exporta o snapshot sem depender da implementação privada do módulo testado.
async function abrirSnapshot() {
  const child = spawn(path.join(bin, 'psql'), ['-X', '-qAt', '--no-password', '-v', 'ON_ERROR_STOP=1'], {
    env: { PATH: '/usr/bin:/bin', ...origem.writable }, stdio: ['pipe', 'pipe', 'pipe'],
  });
  const lines = createInterface({ input: child.stdout });
  child.stderr.resume();
  const id = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('Snapshot local demorou demais.')); }, 15000);
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('exit', code => { clearTimeout(timer); reject(new Error(`Snapshot local encerrou: ${code}`)); });
    lines.once('line', value => { clearTimeout(timer); resolve(value.trim()); });
    child.stdin.write(LEITURA_SETUP + 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT pg_export_snapshot();\n');
  });
  assert.match(id, /^[0-9A-F]+-[0-9A-F]+-[0-9]+$/i);
  return { id, close: async () => {
    if (child.exitCode === null) {
      const done = once(child, 'exit');
      child.stdin.end('ROLLBACK;\n');
      await done;
    }
    lines.close();
  } };
}

async function copiarDumpSemManifesto(name) {
  const dest = path.join(root, name);
  await mkdir(dest, { mode: 0o700 });
  for (const file of ['banco.dump', 'captura-inicial.json', 'diagnostico-pg_dump.json']) {
    await copyFile(path.join(root, 'original', file), path.join(dest, file));
  }
  await assert.rejects(stat(path.join(dest, 'manifesto.json')), { code: 'ENOENT' });
  return dest;
}

try {
  await origem.exec(`
    CREATE SCHEMA auth;
    CREATE SCHEMA storage;
    CREATE SCHEMA supabase_migrations;
    CREATE TABLE public.comum (id integer PRIMARY KEY, texto text NOT NULL);
    ALTER TABLE public.comum ALTER COLUMN texto SET STORAGE PLAIN;
    INSERT INTO public.comum SELECT g, repeat('á🎨',120) || g || E'\\nlinha\\tbarra\\\\fim'
      FROM generate_series(1,4000) g;
    CREATE TABLE public.com_lacuna (id integer PRIMARY KEY, removida text, texto text, valor integer);
    INSERT INTO public.com_lacuna SELECT g, 'ignorado', 'çã ' || g, CASE WHEN g % 3 = 0 THEN NULL ELSE g END
      FROM generate_series(1,700) g;
    ALTER TABLE public.com_lacuna DROP COLUMN removida;
    CREATE TABLE public.vazia (id integer, texto text);
    CREATE TABLE public.esvaziada (id integer, texto text);
    INSERT INTO public.esvaziada SELECT g, repeat('x',200) FROM generate_series(1,200) g;
    DELETE FROM public.esvaziada;
    CREATE TABLE public.duplicadas (texto text, numero integer);
    INSERT INTO public.duplicadas VALUES ('mesma',1),('mesma',1),('outra',NULL);
    CREATE MATERIALIZED VIEW public.resumo AS SELECT valor % 2 AS grupo, count(*) AS quantidade
      FROM public.com_lacuna GROUP BY valor % 2;
    CREATE TABLE auth.fixture (id integer PRIMARY KEY, label text);
    CREATE TABLE storage.fixture (id integer PRIMARY KEY, label text);
    CREATE TABLE supabase_migrations.fixture (id integer PRIMARY KEY, label text);
    INSERT INTO auth.fixture VALUES (1,'somente local');
    INSERT INTO storage.fixture VALUES (1,'somente local');
    INSERT INTO supabase_migrations.fixture VALUES (1,'somente local');
  `);
  const baseline = await capture(bin, origem.c, path.join(root, 'original'));
  const pages = Number((await origem.exec("SELECT pg_relation_size('public.comum') / current_setting('block_size')::int;")).trim());
  assert.ok(pages > 256, 'Fixture deve atravessar vários intervalos padrão de 256 páginas.');
  assert.equal(baseline.rows['public.comum'].count, 4000);
  assert.equal(baseline.rows['public.vazia'].count, 0);
  assert.equal(baseline.rows['public.esvaziada'].count, 0);
  assert.equal(baseline.rows['public.duplicadas'].count, 3);
  snapshot = await abrirSnapshot();
  for (const table of baseline.tables) {
    const key = `${table.schema}.${table.name}`;
    assert.deepEqual(await digestTableEmBlocos(bin, origem.c, table, snapshot.id), baseline.rows[key], key);
  }
  assert.deepEqual(await digestTableEmBlocos(bin, origem.c, { schema:'public', name:'com_lacuna' }, snapshot.id, 1), baseline.rows['public.com_lacuna']);
  assert.deepEqual(await digestTableEmBlocos(bin, origem.c, { schema:'public', name:'comum' }, snapshot.id, 127), baseline.rows['public.comum']);
  for (const size of [0,-1,257,1.5,NaN]) {
    await assert.rejects(digestTableEmBlocos(bin, origem.c, {schema:'public',name:'comum'}, snapshot.id, size), /Tamanho de bloco inválido/);
  }
  console.log('ok 1: blocos disjuntos equivalem ao digest integral; colunas excluídas, Unicode/COPY, vazios, duplicatas e matview cobertos.');

  await origem.exec(`
    UPDATE public.comum SET texto = 'alterado após snapshot' WHERE id = 1;
    DELETE FROM public.comum WHERE id = 2;
    INSERT INTO public.comum VALUES (9000,'novo após snapshot');
  `);
  assert.deepEqual(await digestTableEmBlocos(bin, origem.c, {schema:'public',name:'comum'}, snapshot.id, 127), baseline.rows['public.comum']);
  assert.notDeepEqual(await digestTableEmBlocos(bin, origem.c, {schema:'public',name:'comum'}), baseline.rows['public.comum']);
  await snapshot.close(); snapshot = undefined;
  await origem.exec(`
    UPDATE public.comum SET texto = repeat('á🎨',120) || id || E'\\nlinha\\tbarra\\\\fim' WHERE id = 1;
    INSERT INTO public.comum SELECT 2, repeat('á🎨',120) || 2 || E'\\nlinha\\tbarra\\\\fim';
    DELETE FROM public.comum WHERE id = 9000;
  `);
  console.log('ok 2: snapshot único mantém conteúdo original após UPDATE, DELETE e INSERT concorrentes.');

  const baselineSql = {};
  for (const table of baseline.tables) baselineSql[`${table.schema}.${table.name}`] = await digestTableSql(bin,origem.c,table);
  const recuperado = await copiarDumpSemManifesto('recuperado');
  const manifest = await verifyExisting(bin, origem.c, recuperado);
  assert.deepEqual(manifest.rows, baselineSql);
  assert.equal(manifest.verification.same_snapshot_as_dump, false);
  assert.equal(manifest.verification.method, SQL_DIGEST_METHOD);
  assert.match(manifest.verification.source_snapshot_at, /^\d{4}-\d{2}-\d{2}/);
  assert.equal(manifest.archive_sha256, baseline.archive_sha256);
  assert.equal((await stat(path.join(recuperado,'manifesto.json'))).mode & 0o777, 0o600);
  const report = await restore(bin, recuperado);
  assert.equal(report.result, 'VERIFICADO_NO_ESCOPO_DECLARADO');
  assert.equal(report.source_verification.same_snapshot_as_dump, false);
  console.log('ok 3: dump completo sem manifesto recuperado e restaurado com conteúdo integral idêntico.');

  const divergente = await copiarDumpSemManifesto('divergente');
  await origem.exec("UPDATE public.comum SET texto = 'mudança posterior ao dump' WHERE id = 1;");
  const changed = await verifyExisting(bin, origem.c, divergente);
  assert.notDeepEqual(changed.rows['public.comum'], baselineSql['public.comum']);
  await assert.rejects(restore(bin, divergente), /Dados divergentes em public\.comum/);
  assert.equal((await readdir(divergente)).some(name => /^restauracao-/.test(name)), false);
  console.log('ok 4: uma linha alterada depois do dump reprova restore e não produz relatório de sucesso.');

  const incompleto = await copiarDumpSemManifesto('incompleto');
  const dumpLog = JSON.parse(await readFile(path.join(incompleto,'diagnostico-pg_dump.json'),'utf8'));
  dumpLog.exit_code = 1;
  await writeFile(path.join(incompleto,'diagnostico-pg_dump.json'), JSON.stringify(dumpLog), {mode:0o600});
  await assert.rejects(verifyExisting(bin, {...origem.c, host:path.join(root,'socket-inexistente')}, incompleto), /Dump não comprovadamente concluído/);
  await assert.rejects(stat(path.join(incompleto,'manifesto.json')), {code:'ENOENT'});
  console.log('ok 5: diagnóstico de dump incompleto impede recuperação antes de acessar a origem.');
  console.log('VERIFICAÇÃO EM BLOCOS VERDE — somente ensaio local, sem produção.');
} finally {
  if (snapshot) await snapshot.close();
  await origem.close();
  await rm(root, {recursive:true});
}
