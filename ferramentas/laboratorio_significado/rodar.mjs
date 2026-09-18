#!/usr/bin/env node
/**
 * Laboratório de significado: roda a A57 e a A58 num PostgreSQL 17.10 real,
 * descartável, acessível somente pelo socket deste processo.
 *
 * POR QUE NÃO BASTA O PORTÃO DE TEXTO
 * ===================================
 *
 * `coletor/teste_migrations.py` procura trechos nas migrations: pega contrato
 * apagado, não pega `JOIN` errado nem denominador tirado da data errada. Aqui
 * as funções executam sobre dados desenhados para que cada defeito conhecido
 * apareça como falha.
 *
 * COMO RODAR
 * ==========
 *
 *   node ferramentas/laboratorio_significado/rodar.mjs
 *
 * Os binários do PostgreSQL vêm do pacote `@embedded-postgres`, declarado no
 * `package.json` desta pasta. Instale-os uma vez, fora da árvore de trabalho,
 * porque o `actions/checkout` limpa o workspace a cada execução e 133 MB
 * baixados todo dia seriam desperdício:
 *
 *   LAB=~/.canario/laboratorio-significado
 *   mkdir -p "$LAB" && cp ferramentas/laboratorio_significado/package*.json "$LAB/"
 *   (cd "$LAB" && npm install --no-audit --no-fund)
 *
 * Qualquer outra pasta serve, apontada por `--modulos`.
 *
 * Nada aqui fala com o Supabase: o cluster nasce e morre nesta invocação, e
 * nenhuma migration é aplicada em produção.
 */
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { access, chmod, mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORIO = path.resolve(AQUI, '../..');
const VERSAO_ESPERADA = '17.10';
const MIGRATIONS = [
  'supabase/migrations/20260917210000_a57_frescor_ancorado_no_dado.sql',
  'supabase/migrations/20260917211000_a58_significado_da_capa_e_busca_editorial.sql',
];
const AMBIENTE = Object.freeze({
  PATH: '/usr/local/bin:/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', TZ: 'UTC',
});

// Onde procurar os binários quando ninguém passa `--modulos`: a própria pasta
// primeiro, depois o destino de instalação do CI.
const CANDIDATOS = [
  path.join(AQUI, 'node_modules'),
  path.join(os.homedir(), '.canario/laboratorio-significado/node_modules'),
];

function opcoes(argv) {
  const escolhas = { modulos: null };
  for (let i = 0; i < argv.length; i += 2) {
    if (argv[i] === '--modulos' && argv[i + 1]) escolhas.modulos = argv[i + 1];
    else throw new Error(`Opção desconhecida: ${argv[i]}`);
  }
  return escolhas;
}

async function ondeEstaoOsModulos(escolhido) {
  if (escolhido) return escolhido;
  for (const candidato of CANDIDATOS) {
    try {
      await access(path.join(candidato, 'pg'));
      return candidato;
    } catch { /* tenta o proximo */ }
  }
  throw new Error('Não achei `pg` nem `@embedded-postgres`. Instale uma vez:\n'
    + '  LAB=~/.canario/laboratorio-significado\n'
    + '  mkdir -p "$LAB" && cp ferramentas/laboratorio_significado/package*.json "$LAB/"\n'
    + '  (cd "$LAB" && npm install --no-audit --no-fund)\n'
    + 'Ou aponte outra pasta com --modulos.');
}

function executar(binario, args, { timeout = 120_000 } = {}) {
  return new Promise((resolve, reject) => {
    const filho = spawn(binario, args, { env: AMBIENTE, stdio: ['ignore', 'pipe', 'pipe'] });
    let saida = '';
    let erro = '';
    const relogio = setTimeout(() => {
      filho.kill('SIGTERM');
      reject(new Error(`Tempo esgotado em ${path.basename(binario)}.`));
    }, timeout);
    filho.stdout.on('data', d => { saida += d; });
    filho.stderr.on('data', d => { erro = `${erro}${d}`.slice(-8192); });
    filho.on('error', e => { clearTimeout(relogio); reject(e); });
    filho.on('close', codigo => {
      clearTimeout(relogio);
      if (codigo === 0) resolve(saida);
      else reject(new Error(`${path.basename(binario)} saiu com ${codigo}: ${erro.trim()}`));
    });
  });
}

/** Resolve @embedded-postgres e pg a partir da pasta de módulos escolhida. */
async function dependencias(modulos) {
  const plataforma = `${process.platform}-${process.arch}`;
  const require = createRequire(path.join(modulos, 'index.js'));
  let binarios;
  let pg;
  try {
    binarios = require(`@embedded-postgres/${plataforma}`);
    pg = require('pg');
  } catch (causa) {
    throw new Error(
      `Não achei @embedded-postgres/${plataforma} e pg em ${modulos}.\n`
      + 'Use --modulos apontando para um node_modules com as duas.\n'
      + `Causa: ${causa.message}`);
  }
  return { binarios, pg };
}

async function main() {
  const modulos = await ondeEstaoOsModulos(opcoes(process.argv.slice(2)).modulos);
  if (process.getuid?.() === 0) throw new Error('Rode como usuário comum, sem root.');
  const { binarios, pg } = await dependencias(modulos);
  for (const nome of ['initdb', 'postgres', 'pg_ctl']) await chmod(binarios[nome], 0o755);
  const versao = (await executar(binarios.postgres, ['--version'])).trim();
  if (versao !== `postgres (PostgreSQL) ${VERSAO_ESPERADA}`) {
    throw new Error(`Versão inesperada: ${versao}`);
  }

  // Caminho curto: socket Unix do macOS tem limite de comprimento.
  const raiz = await mkdtemp(path.join(os.tmpdir(), 'datadrobe-sig-'));
  await chmod(raiz, 0o700);
  const dados = path.join(raiz, 'data');
  const socket = path.join(raiz, 'sock');
  const senhaArquivo = path.join(raiz, 'senha');
  const senha = randomBytes(24).toString('hex');
  await mkdir(socket, { mode: 0o700 });
  await require_writeFile(senhaArquivo, senha);

  let processo;
  let cliente;
  const encerrar = async () => {
    if (cliente) await cliente.end().catch(() => {});
    if (processo && processo.exitCode === null) {
      await executar(binarios.pg_ctl, ['stop', '-D', dados, '-m', 'fast', '-w', '-t', '10'])
        .catch(() => processo.kill('SIGKILL'));
      if (processo.exitCode === null) await once(processo, 'exit');
    }
    await rm(raiz, { recursive: true, force: true });
  };

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

    const conexao = {
      host: socket, port: 5432, user: 'lab', password: senha,
      database: 'postgres', connectionTimeoutMillis: 5_000,
    };
    for (let tentativa = 0; tentativa < 50; tentativa += 1) {
      cliente = new pg.Client(conexao);
      try {
        await cliente.connect();
        break;
      } catch {
        cliente = null;
        await new Promise(r => setTimeout(r, 200));
      }
    }
    if (!cliente) throw new Error('O cluster não aceitou conexão.');

    const arquivos = [
      path.join(AQUI, 'fixture.sql'),
      ...MIGRATIONS.map(m => path.join(REPOSITORIO, m)),
      path.join(AQUI, 'assercoes.sql'),
    ];
    cliente.on('notice', aviso => {
      if (aviso.message) console.log(aviso.message);
    });
    for (const arquivo of arquivos) {
      const sql = await readFile(arquivo, 'utf8');
      await cliente.query(sql);
      console.log(`aplicado ${path.relative(REPOSITORIO, arquivo)}`);
    }
    console.log('LABORATORIO VERDE');
  } finally {
    await encerrar();
  }
}

/** writeFile com modo restrito, isolado para manter o topo do arquivo enxuto. */
async function require_writeFile(caminho, conteudo) {
  const { writeFile } = await import('node:fs/promises');
  await writeFile(caminho, conteudo, { mode: 0o600 });
}

main().catch(erro => {
  console.error(`FALHOU: ${erro.message}`);
  process.exit(1);
});
