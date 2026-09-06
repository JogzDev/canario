#!/usr/bin/env node
/** PostgreSQL real, descartável e acessível somente pelo socket deste processo. */
import { spawn } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { once } from 'node:events';
import {
  chmod, mkdir, mkdtemp, readFile, realpath, rm, writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import pg from 'pg';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY = path.resolve(HERE, '../..');
const FOUNDATION = path.join(REPOSITORY,
  'supabase/migrations/20260831170000_a51_fundacao_de_evidencias_13.sql');
const EXPECTED_VERSION = '17.10';
const SUPPORTED = new Set(['darwin-arm64', 'darwin-x64', 'linux-x64']);
// Ambiente explícito: subprocessos não recebem configuração de bancos/serviços.
const CHILD_ENV = Object.freeze({
  PATH: '/usr/local/bin:/usr/bin:/bin',
  LANG: 'C', LC_ALL: 'C', TZ: 'UTC',
  PYTHONDONTWRITEBYTECODE: '1',
});

function argumentsFor(argv) {
  const options = { sqlFiles: [], harnessFiles: [], fixtureFile: null };
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`Falta valor para ${flag}.`);
    if (flag === '--sql') options.sqlFiles.push(value);
    else if (flag === '--harness') options.harnessFiles.push(value);
    else if (flag === '--fixture' && !options.fixtureFile) options.fixtureFile = value;
    else throw new Error(`Opção desconhecida ou repetida: ${flag}.`);
  }
  return options;
}

async function repositoryFile(input, suffix) {
  const resolved = await realpath(path.resolve(REPOSITORY, input));
  if (!resolved.startsWith(`${REPOSITORY}${path.sep}`) || !resolved.endsWith(suffix)) {
    throw new Error(`Entrada deve ser um arquivo ${suffix} dentro deste checkout.`);
  }
  return resolved;
}

function command(binary, args, { timeout = 60_000, input = null } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { env: CHILD_ENV, stdio: ['pipe', 'pipe', 'pipe'] });
    const chunks = [];
    let size = 0;
    let finished = false;
    const finish = (error, output) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (error) reject(error); else resolve(output);
    };
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      finish(new Error(`Tempo esgotado em ${path.basename(binary)}.`));
    }, timeout);
    child.on('error', error => finish(error));
    child.stdout.on('data', data => {
      size += data.length;
      if (size > 16 * 1024 * 1024) {
        child.kill('SIGTERM');
        finish(new Error('Saída do subprocesso ultrapassou 16 MiB.'));
      } else chunks.push(data);
    });
    let stderr = '';
    child.stderr.on('data', data => { stderr = `${stderr}${data}`.slice(-16_384); });
    child.on('close', code => {
      const stdout = Buffer.concat(chunks).toString('utf8');
      finish(code === 0 ? null : new Error(
        `${path.basename(binary)} terminou com código ${code}: ${stderr.trim()}`), stdout);
    });
    child.stdin.end(input);
  });
}

/** O callback recebe apenas conexões para o cluster criado nesta invocação. */
export async function runLab({ sqlFiles = [], fixtureFile = null, harnessFiles = [] } = {}) {
  const platform = `${process.platform}-${process.arch}`;
  if (!SUPPORTED.has(platform)) throw new Error(`Plataforma não preparada: ${platform}.`);
  if (process.getuid?.() === 0) throw new Error('Execute como usuário comum, sem root.');
  const binaries = await import(`@embedded-postgres/${platform}`);
  for (const name of ['initdb', 'postgres', 'pg_ctl']) await chmod(binaries[name], 0o755);
  const versionOutput = (await command(binaries.postgres, ['--version'])).trim();
  if (versionOutput !== `postgres (PostgreSQL) ${EXPECTED_VERSION}`) {
    throw new Error(`Versão inesperada do binário: ${versionOutput}.`);
  }
  // Caminho curto evita o limite de comprimento dos sockets Unix no macOS.
  const directory = await mkdtemp('/private/tmp/datadrobe-lab-'.replace(
    '/private/tmp/', process.platform === 'darwin' ? '/private/tmp/' : '/tmp/'));
  await chmod(directory, 0o700);
  const dataDirectory = path.join(directory, 'data');
  const socketDirectory = path.join(directory, 'socket');
  const passwordFile = path.join(directory, 'bootstrap.password');
  const ownerMarker = path.join(directory, 'owner.json');
  const destinationId = randomUUID();
  const database = `datadrobe_lab_${destinationId.replaceAll('-', '')}`;
  const ownerPassword = randomBytes(32).toString('hex');
  const writerPassword = randomBytes(32).toString('hex');
  const logFile = path.join(directory, 'postgres.log');
  const clients = new Set();
  const connection = {
    host: socketDirectory, port: 5432, database,
    user: 'datadrobe_lab_bootstrap', password: ownerPassword,
    connectionTimeoutMillis: 5_000,
  };
  let postgresProcess;
  let postgresLog = '';
  let succeeded = false;
  let stopping;
  let fixture = null;
  const checks = [];
  const startedAt = Date.now();
  await mkdir(socketDirectory, { mode: 0o700 });
  await writeFile(ownerMarker, JSON.stringify({ destinationId, directory }), { mode: 0o600 });

  const connect = async options => {
    const client = new pg.Client({ ...connection, ...options });
    clients.add(client);
    client.on('error', error => { postgresLog += `\nclient: ${error.message}`; });
    await client.connect();
    return client;
  };
  const stop = async () => {
    if (stopping) return stopping;
    stopping = (async () => {
      await Promise.allSettled([...clients].map(client => client.end()));
      if (postgresProcess && postgresProcess.exitCode === null && !postgresProcess.signalCode) {
        await command(binaries.pg_ctl,
          ['stop', '-D', dataDirectory, '-m', 'fast', '-w', '-t', '10'], { timeout: 15_000 });
        if (postgresProcess.exitCode === null && !postgresProcess.signalCode) {
          await once(postgresProcess, 'exit');
        }
      }
      await writeFile(logFile, postgresLog, { mode: 0o600 });
      await rm(passwordFile, { force: true });
    })();
    return stopping;
  };
  const interrupted = signal => {
    succeeded = false;
    stop().finally(() => {
      process.stderr.write(`Laboratório interrompido; diagnóstico: ${directory}\n`);
      process.exit(signal === 'SIGINT' ? 130 : 143);
    });
  };
  const onInterrupt = () => interrupted('SIGINT');
  const onTerminate = () => interrupted('SIGTERM');
  process.once('SIGINT', onInterrupt);
  process.once('SIGTERM', onTerminate);
  try {
    await writeFile(passwordFile, `${ownerPassword}\n`, { mode: 0o600 });
    await command(binaries.initdb, [
      '-D', dataDirectory, '--encoding=UTF8', '--locale=C',
      '--auth=scram-sha-256', '--username=datadrobe_lab_bootstrap',
      `--pwfile=${passwordFile}`,
    ]);
    await rm(passwordFile);
    postgresProcess = spawn(binaries.postgres, [
      '-D', dataDirectory, '-k', socketDirectory, '-h', '', '-p', '5432',
      '-c', 'unix_socket_permissions=0700',
      '-c', 'max_connections=20', '-c', 'shared_buffers=32MB',
      '-c', 'statement_timeout=15000', '-c', 'lock_timeout=5000',
      '-c', 'timezone=UTC', '-c', 'log_statement=none',
    ], { env: CHILD_ENV, stdio: ['ignore', 'pipe', 'pipe'] });
    for (const stream of [postgresProcess.stdout, postgresProcess.stderr]) {
      stream.on('data', data => { postgresLog = `${postgresLog}${data}`.slice(-1_048_576); });
    }
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Postgres não iniciou em 15 segundos.')), 15_000);
      const ready = data => {
        if (data.toString().includes('database system is ready to accept connections')) {
          clearTimeout(timer); resolve();
        }
      };
      postgresProcess.stderr.on('data', ready);
      postgresProcess.once('error', error => { clearTimeout(timer); reject(error); });
      postgresProcess.once('exit', code => {
        clearTimeout(timer); reject(new Error(`Postgres encerrou ao iniciar (${code}).`));
      });
    });
    const bootstrap = await connect({ database: 'postgres' });
    await bootstrap.query(`CREATE DATABASE ${database}`);
    const admin = await connect({});
    const identity = (await admin.query(`SELECT current_database() AS database,
      current_setting('listen_addresses') AS listen_addresses,
      current_setting('server_version') AS server_version,
      inet_server_addr() AS address`)).rows[0];
    if (identity.database !== database || identity.listen_addresses !== '' || identity.address !== null) {
      throw new Error('O servidor não corresponde ao laboratório isolado criado nesta execução.');
    }
    await admin.query(`
      CREATE ROLE anon NOLOGIN NOBYPASSRLS;
      CREATE ROLE authenticated NOLOGIN NOBYPASSRLS;
      CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE TABLE public.termos (id text PRIMARY KEY, status text NOT NULL);
    `);
    await admin.query(await readFile(FOUNDATION, 'utf8'));
    checks.push('A51 aplicada em PostgreSQL real');
    if (fixtureFile) {
      const script = await repositoryFile(fixtureFile, '.py');
      fixture = JSON.parse(await command('/usr/bin/python3', [
        script, '--destination-id', destinationId,
      ]));
      if (fixture === null || Array.isArray(fixture) || typeof fixture !== 'object') {
        throw new Error('O gerador da fixture precisa retornar um objeto JSON.');
      }
      await writeFile(path.join(directory, 'fixture.json'), JSON.stringify(fixture), { mode: 0o600 });
      await admin.query("SELECT set_config('lab.fixture', $1, false)", [JSON.stringify(fixture)]);
    }
    await admin.query("SELECT set_config('lab.destination_id', $1, false)", [destinationId]);
    for (const input of sqlFiles) {
      const script = await repositoryFile(input, '.sql');
      await admin.query(await readFile(script, 'utf8'));
      checks.push(path.relative(REPOSITORY, script));
    }
    const connectWriter = async () => {
      const client = await connect({ user: 'datadrobe_lab_writer', password: writerPassword });
      await client.query("SELECT set_config('lab.destination_id', $1, false)", [destinationId]);
      if (fixture) await client.query("SELECT set_config('lab.fixture', $1, false)", [JSON.stringify(fixture)]);
      return client;
    };
    if (harnessFiles.length) {
      // Hex gerado localmente; não há conteúdo de usuário na instrução ALTER ROLE.
      await admin.query(`ALTER ROLE datadrobe_lab_writer PASSWORD '${writerPassword}'`);
    }
    for (const input of harnessFiles) {
      const script = await repositoryFile(input, '.mjs');
      const harness = await import(pathToFileURL(script).href);
      if (typeof harness.executar !== 'function') throw new Error('Harness precisa exportar executar().');
      await harness.executar({ admin, fixture, connectWriter, destinationId, database });
      checks.push(path.relative(REPOSITORY, script));
    }
    succeeded = true;
    return {
      state: 'passed', database, destination_id: destinationId,
      server_version: identity.server_version, network: 'private_unix_socket_only',
      checks, elapsed_ms: Date.now() - startedAt,
    };
  } catch (error) {
    postgresLog += `\nLaboratório: ${error.stack || error.message}\n`;
    process.stderr.write(`Diagnóstico preservado em ${directory}\n`);
    throw error;
  } finally {
    try {
      await stop();
      if (succeeded) {
        const owner = JSON.parse(await readFile(ownerMarker, 'utf8'));
        if (owner.destinationId !== destinationId || owner.directory !== directory) {
          throw new Error('Marcador de propriedade divergiu; diretório foi preservado.');
        }
        await rm(directory, { recursive: true });
      }
    } finally {
      process.removeListener('SIGINT', onInterrupt);
      process.removeListener('SIGTERM', onTerminate);
    }
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runLab(argumentsFor(process.argv.slice(2)))
    .then(result => process.stdout.write(`${JSON.stringify(result, null, 2)}\n`))
    .catch(error => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
}
