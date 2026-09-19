#!/usr/bin/env node
// Backup somente leitura; a restauração sempre cria seu próprio cluster local.
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { chmod, mkdir, mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { StringDecoder } from 'node:string_decoder';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.umask(0o077);
const AQUI = path.dirname(fileURLToPath(import.meta.url));
const PROJETO = 'tbluoqpnjqsflfoclmms';
const ESQUEMAS = ['public', 'auth', 'storage', 'supabase_migrations'];
// Somente a conexão administrativa de leitura. Não altera defaults do banco/papéis.
export const LEITURA_SETUP = "SET statement_timeout = '10min'; SET default_transaction_read_only = on; SET lock_timeout = '10s'; SET idle_in_transaction_session_timeout = '30min'; SET transaction_timeout = '30min'; SET timezone='UTC'; SET datestyle='ISO,YMD'; SET extra_float_digits=3; SET intervalstyle='postgres'; SET bytea_output='hex';\n";
const BIN_PADRAO = path.join(os.homedir(), '.local/share/datadrobe-tools/Postgres.app/Contents/Versions/17/bin');
const qid = s => '"' + s.replaceAll('"', '""') + '"';
const lit = s => "'" + s.replaceAll("'", "''") + "'";
const localChildren = new Set();
const activeClusters = new Set();
let signalCleanupInstalled = false;
let signalCleanupRunning = false;

function installSignalCleanup() {
  if (signalCleanupInstalled) return;
  signalCleanupInstalled = true;
  const cleanup = signal => {
    if (signalCleanupRunning) return;
    signalCleanupRunning = true;
    for (const child of [...localChildren]) {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    }
    void Promise.allSettled([...activeClusters].map(cluster => cluster.close()))
      .finally(() => process.exit(signal === 'SIGINT' ? 130 : 143));
  };
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
}

export function resumirErro(stderr) {
  // Só categorias conhecidas saem no Terminal: CONTEXT/DETAIL podem conter linhas.
  const causes = [
    [/password authentication failed/i, 'O servidor recusou a autenticação.'],
    [/statement timeout/i, 'O servidor cancelou a consulta por statement_timeout.'],
    [/idle-in-transaction timeout/i, 'O servidor encerrou uma transação ociosa.'],
    [/transaction timeout/i, 'O servidor encerrou a transação por limite de duração.'],
    [/terminating connection due to administrator command/i, 'O servidor encerrou a conexão por comando administrativo.'],
    [/SSL connection has been closed unexpectedly|server closed the connection unexpectedly|connection reset by peer|SSL SYSCALL error|unexpected EOF/i, 'A conexão foi interrompida durante a leitura.'],
    [/no space left on device|disk full/i, 'Foi reportada falta de espaço.'],
    [/permission denied/i, 'Foi reportada falta de permissão.'],
    [/invalid page|invalid memory alloc|missing chunk|unexpected chunk|compressed data is corrupt/i, 'Foi reportado um erro de integridade/leitura de dados.'],
    [/PQgetCopyData\(\) failed/i, 'A transferência COPY não foi concluída.'],
  ];
  return causes.filter(([pattern]) => pattern.test(stderr)).map(([, label]) => label).join(' ') || 'Falha sem categoria reconhecida; consulte o diagnóstico protegido.';
}

export function run(bin, args, { env = {}, input, stream, timeout = 900_000, diagnosticsFile } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { env: { PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC', ...env }, stdio: ['pipe', 'pipe', 'pipe'] });
    localChildren.add(child);
    let out = '', err = '', truncated = false, timedOut = false, spawnError, killTimer;
    const stdoutDecoder = new StringDecoder('utf8'), stderrDecoder = new StringDecoder('utf8');
    const startedAt = new Date().toISOString();
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => child.kill('SIGKILL'), 2000);
    }, timeout);
    child.stdout.on('data', d => { if (stream) stream(d); else out += stdoutDecoder.write(d); });
    child.stderr.on('data', d => {
      err += stderrDecoder.write(d);
      if (err.length > 1_000_000) { err = err.slice(-1_000_000); truncated = true; }
    });
    // Node emite close também depois de error. Finalizar uma única vez permite
    // que o diagnóstico exista antes de o chamador receber a rejeição.
    child.on('error', e => { clearTimeout(timer); spawnError = e; });
    child.on('close', async (code, signal) => {
      clearTimeout(timer); clearTimeout(killTimer); localChildren.delete(child);
      if (!stream) out += stdoutDecoder.end();
      err += stderrDecoder.end();
      // Arquivo privado, separado do resumo público. Nunca salva ambiente,
      // argumentos, stdin ou stdout; remove a senha até se um filho a emitir.
      for (const secret of new Set([env.PGPASSWORD, env.PGPASSWORD && encodeURIComponent(env.PGPASSWORD)])) {
        if (secret) err = err.replaceAll(secret, '[credencial redigida]');
      }
      err = err.replace(/(postgres(?:ql)?:\/\/[^:\s]+:)[^@\s]+@/gi, '$1[redigido]@');
      let logSaved = false;
      if (diagnosticsFile) {
        try {
          await save(diagnosticsFile, { program:path.basename(bin), started_at:startedAt,
            finished_at:new Date().toISOString(), exit_code:code, signal, local_timeout:timedOut,
            spawn_error_code:spawnError?.code,
            stderr_truncated:truncated, stderr:err });
          logSaved = true;
        } catch { /* A falha original não pode ser escondida por falha do log. */ }
      }
      if (spawnError) reject(spawnError);
      else if (code === 0 && !timedOut) resolve(out);
      else {
        const cause = timedOut ? `Limite local de ${timeout / 1000}s atingido; processo interrompido.` : resumirErro(err);
        reject(new Error(`${path.basename(bin)} falhou (${code ?? signal}). ${cause}${logSaved ? ` Diagnóstico protegido: ${diagnosticsFile}` : ''}`));
      }
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}
function connEnv(c) {
  return { PGHOST: c.host, PGPORT: String(c.port), PGUSER: c.user, PGDATABASE: c.database,
    PGPASSWORD: c.password, PGCONNECT_TIMEOUT: '15', PGSSLMODE: c.sslmode,
    PGAPPNAME: 'datadrobe_backup_leitura', PGOPTIONS: '-c default_transaction_read_only=on -c timezone=UTC -c datestyle=ISO,YMD -c extra_float_digits=3 -c statement_timeout=600000 -c lock_timeout=10000 -c idle_in_transaction_session_timeout=1800000 -c transaction_timeout=1800000' };
}
async function sql(bin, c, query, snapshot) {
  const prefix = snapshot ? `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET TRANSACTION SNAPSHOT ${lit(snapshot)};\n` : '';
  return run(path.join(bin, 'psql'), ['-X', '-qAt', '--no-password', '-v', 'ON_ERROR_STOP=1'],
    { env: connEnv(c), input: LEITURA_SETUP + prefix + query + (snapshot ? '\nCOMMIT;\n' : '\n'),
      diagnosticsFile:c.diagnosticsDir ? path.join(c.diagnosticsDir,`consulta-${Date.now()}-${randomBytes(3).toString('hex')}.json`) : undefined });
}
async function json(bin, c, query, snapshot) { return JSON.parse((await sql(bin, c, query, snapshot)).trim()); }
async function save(file, value) { await writeFile(file, JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: 'wx' }); }
async function sha(file) { const h = createHash('sha256'); for await (const chunk of createReadStream(file)) h.update(chunk); return h.digest('hex'); }
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, stable(value[k])]));
  return value;
}
function equal(a, b) { return JSON.stringify(stable(a)) === JSON.stringify(stable(b)); }

export function normalizarCatalogo(catalog) {
  // attnum é um slot físico: DROP COLUMN deixa lacunas na origem, mas pg_dump
  // restaura apenas as colunas ativas, sem essas lacunas. Comparamos a ordem
  // lógica preservando nomes, tipos, defaults, ACLs e todos os demais campos.
  const copy = structuredClone(catalog);
  for (const relation of copy.relations ?? []) {
    if (relation.columns) relation.columns = relation.columns.map((column, i) => ({ ...column, position:i + 1 }));
  }
  for (const type of copy.types ?? []) {
    if (type.attributes) type.attributes = type.attributes.map((attribute, i) => ({ ...attribute, position:i + 1 }));
  }
  return copy;
}

async function snapshotOpen(bin, c, minutes = 30) {
  if (![30,60].includes(minutes)) throw new Error('Duração de snapshot inválida.');
  const child = spawn(path.join(bin, 'psql'), ['-X', '-qAt', '--no-password', '-v', 'ON_ERROR_STOP=1'],
    { env: { PATH: '/usr/bin:/bin', ...connEnv(c) }, stdio: ['pipe', 'pipe', 'pipe'] });
  localChildren.add(child);
  child.once('close', () => localChildren.delete(child));
  let err = '';
  child.stderr.on('data', d => { err = (err + d).slice(-3000); });
  const lines = createInterface({ input: child.stdout });
  const id = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('Timeout ao abrir snapshot de leitura.')); }, 30_000);
    child.once('error', e => { clearTimeout(timer); reject(e); });
    child.once('exit', code => { clearTimeout(timer); reject(new Error(`Conexão de leitura encerrada (${code}): ${err}`)); });
    lines.once('line', line => { clearTimeout(timer); resolve(line.trim()); });
    child.stdin.write(LEITURA_SETUP + `SET transaction_timeout='${minutes}min'; SET idle_in_transaction_session_timeout='${minutes}min'; BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT pg_export_snapshot();\n`);
  });
  if (!/^[0-9A-F]+-[0-9A-F]+-[0-9]+$/i.test(id)) { child.kill(); throw new Error('Identificador de snapshot inesperado.'); }
  return { id, close: async () => { if (child.exitCode === null) { const done = once(child, 'exit'); child.stdin.end('ROLLBACK;\n'); await done; } lines.close(); } };
}

const TABLES_SQL = `SELECT coalesce(json_agg(json_build_object('schema', n.nspname, 'name', c.relname) ORDER BY n.nspname,c.relname),'[]')
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN (${ESQUEMAS.map(lit)}) AND c.relkind IN ('r','m')
 AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e');`;
const BOOT_SQL = `SELECT json_build_object(
 'schemas', (SELECT json_agg(nspname ORDER BY nspname) FROM pg_namespace WHERE nspname IN (${ESQUEMAS.map(lit)})),
 'roles', (SELECT json_agg(json_build_object('name',rolname,'inherit',rolinherit,'bypassrls',rolbypassrls) ORDER BY rolname) FROM pg_roles WHERE rolname !~ '^pg_'),
 'memberships', (SELECT coalesce(json_agg(json_build_object('role',r.rolname,'member',m.rolname,'admin',a.admin_option,'inherit',a.inherit_option,'set',a.set_option) ORDER BY r.rolname,m.rolname),'[]') FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member),
 'extensions', (SELECT json_agg(json_build_object('name',e.extname,'schema',n.nspname,'version',e.extversion) ORDER BY e.extname) FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace),
 'server_version', current_setting('server_version'), 'captured_at', current_timestamp,
 'read_session', json_build_object('statement_timeout',current_setting('statement_timeout'),
 'statement_timeout_ms',(SELECT setting::int FROM pg_settings WHERE name='statement_timeout'),
 'default_transaction_read_only',current_setting('default_transaction_read_only'),
 'transaction_read_only',current_setting('transaction_read_only')));`;

async function sequences(bin,c) {
  const list = await json(bin,c,`SELECT coalesce(json_agg(json_build_object('schema',n.nspname,'name',c.relname) ORDER BY n.nspname,c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='S' AND n.nspname IN (${ESQUEMAS.map(lit)}) AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e');`);
  const result = {};
  for (const s of list) result[`${s.schema}.${s.name}`] = await json(bin,c,`SELECT json_build_object('last_value',last_value::text,'is_called',is_called) FROM ${qid(s.schema)}.${qid(s.name)};`);
  return result;
}

async function digestTable(bin, c, t, snapshot, blockRange) {
  // SHA-256 multiset: count + soma modular + XOR, independente da ordem física.
  // Sem ORDER BY no servidor: não cria sort temporário num banco quase cheio.
  let pending = '', count = 0, sum = 0n, xor = 0n;
  const decoder = new StringDecoder('utf8');
  const mask = (1n << 256n) - 1n;
  const accept = line => { const v = BigInt('0x' + createHash('sha256').update(line).digest('hex')); sum = (sum + v) & mask; xor ^= v; count++; };
  const prefix = snapshot ? `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET TRANSACTION SNAPSHOT ${lit(snapshot)};\n` : '';
  const where = blockRange ? ` WHERE ctid >= '(${blockRange[0]},0)'::tid AND ctid < '(${blockRange[1]},0)'::tid` : '';
  await run(path.join(bin, 'psql'), ['-X', '-qAt', '--no-password', '-v', 'ON_ERROR_STOP=1'], {
    env: connEnv(c), input: LEITURA_SETUP + prefix + `COPY (SELECT row_to_json(r)::text FROM ONLY ${qid(t.schema)}.${qid(t.name)} r${where}) TO STDOUT;\n` + (snapshot ? 'COMMIT;\n' : ''),
    diagnosticsFile:c.diagnosticsDir ? path.join(c.diagnosticsDir,`psql-${t.schema}-${t.name}-${blockRange?.[0] ?? 'all'}-${Date.now()}.json`) : undefined,
    stream: chunk => { pending += decoder.write(chunk); let i; while ((i = pending.indexOf('\n')) >= 0) { accept(pending.slice(0, i)); pending = pending.slice(i + 1); } }
  });
  pending += decoder.end();
  if (pending) throw new Error('COPY terminou com linha incompleta.');
  return { count, sha256_sum: sum.toString(16).padStart(64, '0'), sha256_xor: xor.toString(16).padStart(64, '0') };
}

export async function digestTableEmBlocos(bin,c,t,snapshot,blockCount=256) {
  if (!Number.isSafeInteger(blockCount) || blockCount < 1 || blockCount > 256) throw new Error('Tamanho de bloco inválido.');
  const pages = await json(bin,c,`SELECT ceil(pg_relation_size(${lit(`${qid(t.schema)}.${qid(t.name)}`)}::regclass)::numeric / current_setting('block_size')::int)::bigint;`,snapshot);
  if (!Number.isSafeInteger(pages) || pages < 0) throw new Error('Tamanho físico inválido.');
  const mask=(1n<<256n)-1n;
  let count=0,sum=0n,xor=0n;
  // Intervalos TID disjuntos cobrem todo o heap, sem OFFSET/ORDER BY/sort.
  // Todas as consultas importam o MESMO snapshot; ctid não entra na assinatura.
  for (let start=0;start<pages;start+=blockCount) {
    const d=await digestTable(bin,c,t,snapshot,[start,Math.min(start+blockCount,pages)]);
    count+=d.count; sum=(sum+BigInt('0x'+d.sha256_sum))&mask; xor^=BigInt('0x'+d.sha256_xor);
    if (pages>blockCount) console.log(`  ${t.schema}.${t.name}: blocos ${Math.min(start+blockCount,pages)}/${pages}, ${count} linhas.`);
  }
  return {count,sha256_sum:sum.toString(16).padStart(64,'0'),sha256_xor:xor.toString(16).padStart(64,'0')};
}

export const SQL_DIGEST_METHOD='sha256_record_utf8_count_four_signed64_sums_xors_v1';
export async function digestTableSql(bin,c,t,snapshot) {
  // Hash por linha no servidor, agregado sem sort e sem exportar o conteúdo.
  // Quatro somas de inteiros64 promovidas a numeric (sem overflow) e quatro
  // XORs cobrem os256bits. Strings decimais preservam precisão no JavaScript.
  // record_out preserva SQL NULL vs JSON null e limites inferiores dos arrays;
  // row_to_json perde essas distinções. O MESMO algoritmo roda no restore.
  return json(bin,c,`WITH hashes AS (
    SELECT hashed.h FROM ONLY ${qid(t.schema)}.${qid(t.name)} r
    CROSS JOIN LATERAL (SELECT encode(sha256(convert_to(r::text,'UTF8')),'hex') AS h OFFSET 0) hashed
  ), parts AS (
    SELECT ${[0,1,2,3].map(i=>`('x'||substr(h,${i*16+1},16))::bit(64)::bigint AS p${i}`).join(',')}
    FROM hashes
  ) SELECT json_build_object('method',${lit(SQL_DIGEST_METHOD)},'count',count(*),
    'sums',json_build_array(${[0,1,2,3].map(i=>`coalesce(sum(p${i}),0)::text`).join(',')}),
    'xors',json_build_array(${[0,1,2,3].map(i=>`coalesce(bit_xor(p${i}),0)::text`).join(',')})) FROM parts;`,snapshot);
}

export async function verifyExisting(bin,c,dest) {
  // Recupera um dump CONCLUÍDO cuja conferência remota caiu depois. Não o
  // modifica nem mistura hashes de snapshots distintos. Um snapshot posterior
  // é declarado no manifesto e precisa concordar integralmente com o restore.
  const initial=JSON.parse(await readFile(path.join(dest,'captura-inicial.json'),'utf8'));
  const dumpLog=JSON.parse(await readFile(path.join(dest,'diagnostico-pg_dump.json'),'utf8'));
  if (dumpLog.exit_code!==0 || dumpLog.local_timeout) throw new Error('Dump não comprovadamente concluído; não verificar archive parcial.');
  const archive=path.join(dest,'banco.dump');
  await run(path.join(bin,'pg_restore'),['--file=/dev/null',archive]);
  const verificationDir=path.join(dest,`verificacao-${Date.now()}`);
  await mkdir(verificationDir,{mode:0o700});
  const v={...c,diagnosticsDir:verificationDir};
  const snap=await snapshotOpen(bin,v,60);
  try {
    const currentBootstrap=await json(bin,v,BOOT_SQL,snap.id);
    if (currentBootstrap.read_session.statement_timeout_ms!==600000 || currentBootstrap.read_session.default_transaction_read_only!=='on' || currentBootstrap.read_session.transaction_read_only!=='on') throw new Error('Sessão de conferência não confirmou limites e modo somente leitura.');
    for (const field of ['roles','memberships','extensions','schemas','server_version']) {
      if (!equal(initial.bootstrap[field],currentBootstrap[field])) throw new Error(`Metadado ${field} mudou desde o dump; requer análise antes de validar.`);
    }
    const currentCatalog=await json(bin,v,await readFile(path.join(AQUI,'catalogo.sql'),'utf8'),snap.id);
    const currentTables=await json(bin,v,TABLES_SQL,snap.id);
    if (!equal(normalizarCatalogo(initial.catalog),normalizarCatalogo(currentCatalog)) || !equal(initial.tables,currentTables)) throw new Error('Estrutura da origem mudou desde o dump; não reutilizar esta verificação.');
    if (!equal(initial.sequences,await sequences(bin,v))) throw new Error('Sequences mudaram desde o dump; requer análise antes de validar.');
    const rows={};
    for (const [i,t] of currentTables.entries()) {
      const key=`${t.schema}.${t.name}`;
      console.log(`[${i+1}/${currentTables.length}] Conferindo assinatura SHA-256 ${key}...`);
      rows[key]=await digestTableSql(bin,v,t,snap.id);
      console.log(`  ${rows[key].count} linhas conferidas, sem transferir conteúdo.`);
      await save(path.join(verificationDir,`tabela-${i}.json`),{table:key,digest:rows[key],status:'CONFERIDO_NA_ORIGEM_RESTORE_PENDENTE'});
    }
    const seqAfter=await sequences(bin,v);
    if (!equal(initial.sequences,seqAfter)) throw new Error('Sequences mudaram durante a conferência.');
    const manifest={format:1,scope_verified:initial.bootstrap.schemas,bootstrap:initial.bootstrap,
      catalog:initial.catalog,tables:initial.tables,rows,sequences:seqAfter,archive_sha256:await sha(archive),
      verification:{same_snapshot_as_dump:false,source_snapshot_at:currentBootstrap.captured_at,
        method:SQL_DIGEST_METHOD,note:'Assinaturas de todas as linhas comparadas com snapshot posterior; igualdade exigida na restauração.'},
      limitations:['Storage: apenas metadados; bytes dos arquivos não incluídos.','Cron/Vault/extensões: operação dos serviços não comprovada.','Senhas dos papéis, e-mails, Edge Functions, autenticação externa e configurações do projeto não comprovados.']};
    await save(path.join(dest,'manifesto.json'),manifest);
    await writeFile(path.join(dest,'inventario.txt'),await run(path.join(bin,'pg_restore'),['--list',archive]),{mode:0o600,flag:'wx'});
    return manifest;
  } finally {await snap.close();}
}

export async function capture(bin, c, dest) {
  await mkdir(dest, { mode: 0o700 });
  await chmod(dest, 0o700);
  const snap = await snapshotOpen(bin, c);
  try {
    const bootstrap = await json(bin, c, BOOT_SQL, snap.id);
    if (!bootstrap.server_version.startsWith('17.')) throw new Error('Produção não é PostgreSQL 17. Reavaliar compatibilidade.');
    if (bootstrap.read_session.statement_timeout_ms !== 600000 || bootstrap.read_session.default_transaction_read_only !== 'on' || bootstrap.read_session.transaction_read_only !== 'on') {
      throw new Error(`Sessão não confirmou configurações: ${JSON.stringify(bootstrap.read_session)}. Nenhum dump gerado.`);
    }
    const catalog = await json(bin, c, await readFile(path.join(AQUI, 'catalogo.sql'), 'utf8'), snap.id);
    const tables = await json(bin, c, TABLES_SQL, snap.id);
    const rows = {};
    const seqBefore = await sequences(bin,c);
    console.log(`Snapshot aberto; ${tables.length} tabelas. Timeout de leitura desta sessão: 10 minutos por consulta.`);
    const archive = path.join(dest, 'banco.dump');
    await save(path.join(dest,'captura-inicial.json'),{bootstrap,catalog,tables,sequences:seqBefore,status:'CAPTURA_EM_ANDAMENTO_NAO_VERIFICADA'});
    // Reproduz primeiro a etapa que falhou, sem gravar dados da tabela no disco.
    // pg_dump redefine seus timeouts SQL para zero; o teto é do processo local.
    if (tables.some(t => t.schema === 'public' && t.name === 'artigos')) {
      console.log('Teste focal de leitura de artigos (até 6 minutos; sem alterar o banco).');
      await run(path.join(bin, 'pg_dump'), ['--data-only', '--table=public.artigos', '--no-password', '--verbose', '--lock-wait-timeout=10s', `--snapshot=${snap.id}`, '--file=/dev/null'],
        { env:connEnv(c), timeout:360_000, diagnosticsFile:path.join(dest,'diagnostico-artigos.json') });
      console.log('Leitura de artigos concluída. Prosseguindo com o backup completo.');
    }
    console.log('Gerando arquivo lógico completo com pg_dump (somente leitura; teto local de 15 minutos).');
    await run(path.join(bin, 'pg_dump'), ['--format=custom', '--compress=gzip:6', '--no-password', '--verbose', '--lock-wait-timeout=10s', `--snapshot=${snap.id}`, '--file', archive],
      { env: connEnv(c), diagnosticsFile:path.join(dest,'diagnostico-pg_dump.json') });
    await chmod(archive, 0o600);
    console.log('Arquivo do dump gerado. Conferindo conteúdo no mesmo snapshot.');
    for (const [i,t] of tables.entries()) {
      const key = `${t.schema}.${t.name}`;
      console.log(`[${i+1}/${tables.length}] Verificando ${key}...`);
      try { rows[key] = await digestTable(bin,c,t,snap.id); }
      catch(e) { throw new Error(`Verificação de ${key}: ${e.message}. O dump já gerado foi preservado.`); }
      console.log(`  ${rows[key].count} linhas conferidas.`);
    }
    const seqAfter = await sequences(bin,c);
    if (!equal(seqBefore,seqAfter)) throw new Error('Sequences mudaram durante a leitura. Dump preservado, mas repetir em janela sem gravações para provar seus estados.');
    const toc = await run(path.join(bin, 'pg_restore'), ['--list', archive]);
    await writeFile(path.join(dest, 'inventario.txt'), toc, { mode: 0o600, flag: 'wx' });
    const manifest = { format: 1, scope_verified: bootstrap.schemas, bootstrap, catalog, tables, rows, sequences:seqAfter, archive_sha256: await sha(archive),
      limitations: ['Storage: o dump contém metadados; bytes dos arquivos não estão incluídos.', 'Cron/Vault/extensões: o arquivo original é preservado; este ensaio local não prova operação dos serviços.', 'Papéis locais não permitem login; credenciais de papéis não são exportadas.', 'Não prova entrega de e-mails, Edge Functions, autenticação externa nem configurações do projeto.'] };
    await save(path.join(dest, 'manifesto.json'), manifest);
    console.log('Dump e manifesto gravados. Iniciando prova em cluster local isolado.');
    return manifest;
  } finally { await snap.close(); }
}

export async function localCluster(bin) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'dd-pg-'));
  await chmod(root, 0o700);
  const data = path.join(root, 'data'), socket = path.join(root, 'sock'), pw = path.join(root, 'pw');
  const password = randomBytes(32).toString('hex');
  let started = false;
  let closePromise;
  const control = { close: () => {
    if (!closePromise) closePromise = (async () => {
      activeClusters.delete(control);
      if (started) await run(path.join(bin, 'pg_ctl'), ['stop', '-D', data, '-m', 'fast', '-w', '-t', '30']);
      await rm(root, { recursive: true, force: true });
    })();
    return closePromise;
  } };
  activeClusters.add(control);
  await mkdir(socket, { mode: 0o700 });
  await writeFile(pw, password, { mode: 0o600 });
  try {
    await run(path.join(bin, 'initdb'), ['-D', data, '-U', 'postgres', '--pwfile', pw, '--auth=scram-sha-256', '--encoding=UTF8', '--no-locale']);
    // Marque antes do start: se houver sinal nesta janela, tentar parar é mais
    // seguro do que apagar um PGDATA cujo postmaster pode já ter subido.
    started = true;
    await run(path.join(bin, 'pg_ctl'), ['start', '-D', data, '-l', path.join(root, 'server.log'), '-w', '-t', '30', '-o', `-k ${socket} -h '' -p 5432 -c listen_addresses=''`]);
  } catch (e) { await control.close().catch(() => {}); throw e; }
  const c = { host: socket, port: 5432, user: 'postgres', password, database: 'postgres', sslmode: 'disable' };
  const writable = { ...connEnv(c), PGOPTIONS: '-c timezone=UTC -c datestyle=ISO,YMD -c extra_float_digits=3' };
  return { c, writable, root,
    exec: query => run(path.join(bin, 'psql'), ['-X', '-qAt', '--no-password', '-v', 'ON_ERROR_STOP=1'], { env: writable, input: query }),
    close: control.close };
}

export async function restore(bin, dest) {
  installSignalCleanup();
  const manifest = JSON.parse(await readFile(path.join(dest, 'manifesto.json'), 'utf8'));
  const archive = path.join(dest, 'banco.dump');
  if (manifest.format !== 1 || await sha(archive) !== manifest.archive_sha256) throw new Error('Formato ou SHA-256 do backup divergente.');
  const cluster = await localCluster(bin);
  try {
    const b = manifest.bootstrap;
    for (const r of b.roles) if (r.name !== 'postgres' && !r.name.startsWith('pg_')) {
      await cluster.exec(`CREATE ROLE ${qid(r.name)} NOLOGIN ${r.inherit ? 'INHERIT' : 'NOINHERIT'} ${r.bypassrls ? 'BYPASSRLS' : 'NOBYPASSRLS'};`);
    }
    for (const a of b.memberships) await cluster.exec(`GRANT ${qid(a.role)} TO ${qid(a.member)} WITH ADMIN ${a.admin ? 'TRUE' : 'FALSE'}, INHERIT ${a.inherit ? 'TRUE' : 'FALSE'}, SET ${a.set ? 'TRUE' : 'FALSE'};`);
    const available = await json(bin, cluster.c, 'SELECT json_agg(name) FROM pg_available_extensions;');
    const unsupported = [];
    for (const e of b.extensions) {
      if (e.name === 'plpgsql') continue;
      if (!available.includes(e.name)) { unsupported.push(e.name); continue; }
      if (e.schema !== 'public') await cluster.exec(`CREATE SCHEMA IF NOT EXISTS ${qid(e.schema)};`);
      await cluster.exec(`CREATE EXTENSION IF NOT EXISTS ${qid(e.name)} WITH SCHEMA ${qid(e.schema)};`);
    }
    // --schema não inclui as entradas CREATE SCHEMA (namespace "-") do TOC.
    // Reincorpora esses IDs explicitamente, preservando a ordem do archive.
    const toc = await run(path.join(bin,'pg_restore'),['--list',archive]);
    const selected = await run(path.join(bin,'pg_restore'),['--list',...b.schemas.flatMap(s=>['--schema',s]),archive]);
    const ids = new Set(selected.split('\n').map(s=>s.match(/^(\d+);/)?.[1]).filter(Boolean));
    const schemaPattern = new RegExp(` (?:SCHEMA -|(?:ACL|COMMENT) - SCHEMA) (${b.schemas.join('|')})(?: |$)`);
    const restoreToc = toc.split('\n').filter(line => {
      const id=line.match(/^(\d+);/)?.[1];
      return !id || ids.has(id) || schemaPattern.test(line) || / DEFAULT ACL - /.test(line);
    }).join('\n');
    const selectionPath = path.join(cluster.root,'restore.list');
    await writeFile(selectionPath,restoreToc,{mode:0o600});
    // Falha em qualquer objeto escolhido. Nunca ignora erros SQL.
    await run(path.join(bin, 'pg_restore'), ['--exit-on-error', '--single-transaction', '--no-password', '--no-tablespaces', '--use-list',selectionPath, '--dbname', 'postgres', archive], { env: cluster.writable });
    const actualCatalog = await json(bin, cluster.c, await readFile(path.join(AQUI, 'catalogo.sql'), 'utf8'));
    if (!equal(normalizarCatalogo(manifest.catalog), normalizarCatalogo(actualCatalog))) {
      await save(path.join(dest, `catalogo-divergente-${Date.now()}.json`), actualCatalog);
      throw new Error('Catálogo restaurado diverge: definições, permissões, RLS, índices ou constraints.');
    }
    const actualTables = await json(bin, cluster.c, TABLES_SQL);
    if (!equal(actualTables, manifest.tables)) throw new Error('Conjunto de tabelas restaurado diverge.');
    for (const t of manifest.tables) {
      const key = `${t.schema}.${t.name}`;
      const expected=manifest.rows[key];
      const actual=expected.method===SQL_DIGEST_METHOD ? await digestTableSql(bin,cluster.c,t) : await digestTable(bin,cluster.c,t);
      if (!equal(actual,expected)) throw new Error(`Dados divergentes em ${key}.`);
    }
    if (!equal(await sequences(bin,cluster.c),manifest.sequences)) throw new Error('Estado das sequences/identity diverge.');
    const report = { result: 'VERIFICADO_NO_ESCOPO_DECLARADO', at: new Date().toISOString(), schemas:b.schemas, tables: manifest.tables.length,
      archive_sha256: manifest.archive_sha256, unsupported_extensions: unsupported,
      source_verification:manifest.verification ?? {same_snapshot_as_dump:true},
      catalog_comparison:'logical_column_order_without_dropped_physical_slots', limitations: manifest.limitations };
    await save(path.join(dest, `restauracao-${Date.now()}.json`), report);
    console.log(`RESTAURAÇÃO VERIFICADA: ${manifest.tables.length} tabelas, conteúdo e catálogo iguais no escopo declarado.`);
    console.log(`Escopo: ${b.schemas.join(', ')}.`);
    console.log('Pendente: bytes do Storage, operação cron/Vault e serviços externos.');
    return report;
  } finally { await cluster.close(); }
}

export function normalizarEntradaSenha(answer) {
  // Remove somente o envelope de bracketed paste do terminal, nunca espaços
  // ou símbolos da senha. readline terminal:false não interpreta esse protocolo.
  let value = answer;
  if (value.startsWith('\u001b[200~') && value.endsWith('\u001b[201~')) {
    value = value.slice(6, -6);
  }
  if (/[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error('A colagem contém caracteres de controle. Copie novamente somente a senha no gerenciador e tente outra vez. Nenhuma conexão foi feita.');
  }
  if (!value) throw new Error('Senha vazia; nenhuma conexão efetuada.');
  return value;
}

async function passwordPrompt() {
  if (process.env.PGPASSWORD) return process.env.PGPASSWORD;
  const key = spawnSync('/usr/bin/security', ['find-generic-password', '-s', 'Supabase CLI', '-a', PROJETO, '-w'], { encoding: 'utf8', timeout: 10000 });
  if (key.status === 0 && key.stdout.trim()) return key.stdout.trim();
  if (!process.stdin.isTTY) throw new Error('Senha não disponível. Abra iniciar_backup.command no Terminal para digitá-la sem eco.');
  process.stdout.write('Senha atual do banco Supabase (não aparece ao digitar): ');
  const old = spawnSync('/bin/stty', ['-g'], { stdio: ['inherit', 'pipe', 'inherit'], encoding: 'utf8' }).stdout.trim();
  const disabled = spawnSync('/bin/stty', ['-echo'], { stdio: 'inherit' });
  if (disabled.status !== 0) throw new Error('Não foi possível ocultar a senha.');
  const rl = createInterface({ input: process.stdin, terminal: false });
  const reset = () => { spawnSync('/bin/stty', [old], { stdio: 'inherit' }); process.stdout.write('\n'); };
  const cancel = () => { reset(); process.exit(130); };
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try { const answer = await new Promise((resolve, reject) => {
    rl.once('line', resolve);
    rl.once('close', () => reject(new Error('Entrada de senha encerrada.')));
  }); return normalizarEntradaSenha(answer); }
  finally { rl.close(); reset(); process.removeListener('SIGINT', cancel); process.removeListener('SIGTERM', cancel); }
}

export async function main(argv = process.argv.slice(2)) {
  const mode = argv.shift() || 'backup';
  const opts = {};
  while (argv.length) { const key = argv.shift(), value = argv.shift(); if (!['--bin', '--dest', '--project-root'].includes(key) || !value) throw new Error('Argumentos inválidos.'); opts[key] = value; }
  const bin = opts['--bin'] || BIN_PADRAO;
  const version = await run(path.join(bin, 'pg_dump'), ['--version']);
  if (!/\b17\./.test(version)) throw new Error('É necessário pg_dump 17.');
  if (mode === 'restore') { if (!opts['--dest']) throw new Error('Informe --dest.'); return restore(bin, opts['--dest']); }
  if (!['backup','verify-existing'].includes(mode)) throw new Error('Modo deve ser backup, verify-existing ou restore.');
  if (mode==='verify-existing' && !opts['--dest']) throw new Error('verify-existing exige --dest do dump concluído.');
  const projectRoot = opts['--project-root'] || '/Users/jpscoliveira/Canario';
  const url = new URL((await readFile(path.join(projectRoot, 'supabase/.temp/pooler-url'), 'utf8')).trim());
  if (url.username !== `postgres.${PROJETO}` || !url.hostname.endsWith('.pooler.supabase.com') || url.port !== '5432' || url.password) throw new Error('Conexão salva não corresponde ao session pooler esperado, sem senha.');
  const parent = path.join(os.homedir(), 'backups');
  await mkdir(parent, { recursive: true, mode: 0o700 });
  const dest = opts['--dest'] || path.join(parent, `datadrobe-${new Date().toISOString().replaceAll(':', '-')}-${randomBytes(3).toString('hex')}`);
  const password = await passwordPrompt();
  installSignalCleanup();
  const c = { host: url.hostname, port: 5432, user: url.username, database: url.pathname.slice(1), sslmode: 'require', password };
  if (!c.password) throw new Error('Senha vazia; nenhuma conexão efetuada.');
  console.log('Consultando produção somente em leitura. Nenhuma migration será aplicada.');
  console.log(`Destino protegido: ${dest}`);
  try {
    if (mode==='verify-existing') await verifyExisting(bin,c,dest);
    else await capture(bin, c, dest);
    c.password = '';
    await restore(bin, dest);
    console.log(`Arquivos preservados em ${dest}`);
  } catch(error) {
    // Apenas a mensagem sanitizada; nunca ambiente, URI, senha ou linhas COPY.
    await save(path.join(dest, `falha-${Date.now()}.json`), {
      status:'FALHOU_NAO_VERIFICADO', at:new Date().toISOString(), message:error.message
    }).catch(()=>{});
    throw error;
  } finally { c.password = ''; }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(e => {
    console.error(`FALHOU: ${e.message}`);
    if (/password authentication failed|recusou a autenticação/i.test(e.message)) {
      console.error('O servidor recusou esta senha. Copie novamente a senha do banco que funcionou antes e cole uma única vez no próximo prompt. Não cole a senha no chat.');
    }
    process.exitCode = 1;
  });
}
