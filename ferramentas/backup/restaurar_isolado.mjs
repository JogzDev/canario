#!/usr/bin/env node
/**
 * Restaura um dump lógico do Supabase num PostgreSQL 17.10 descartável e
 * verifica o resultado contra as contagens medidas em produção.
 *
 * POR QUE ESTE DESTINO
 * ====================
 *
 * A porta de saída da etapa 1 não é "o dump existe": é "o dump volta e confere".
 * Esta máquina não tem `brew`, `pg_dump`, `psql` nem Docker, e o plano gratuito
 * do Supabase não dá backup baixável pelo painel. O destino, então, é o
 * PostgreSQL 17.10 do pacote `@embedded-postgres` -- mesma versão maior da
 * produção, cluster criado e destruído nesta invocação, acessível somente pelo
 * socket deste processo.
 *
 * O QUE ESTA PROVA NÃO COBRE, E ESTÁ DECLARADO
 * ============================================
 *
 * `pg_cron` e `supabase_vault` são plataforma, não dado: não existem fora do
 * Supabase. As linhas do dump que dependem delas são puladas, uma por uma, e
 * impressas. Agendamento de cron e segredos do vault continuam sem prova de
 * restauração e seguem como pendência no ESTADO.md.
 *
 * USO
 * ===
 *
 *   node ferramentas/backup/restaurar_isolado.mjs \
 *     --dump ~/backups/datadrobe-AAAA-MM-DD \
 *     [--modulos <node_modules com @embedded-postgres e pg>]
 *
 * A senha do banco não entra aqui: o dump já foi feito pelo JP.
 */
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORIO = path.resolve(AQUI, '../..');
const EXPECTATIVA = path.join(REPOSITORIO, 'anexos/contagens_producao_2026-09-17.json');
const VERSAO_ESPERADA = '17.10';
const AMBIENTE = Object.freeze({
  PATH: '/usr/local/bin:/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', TZ: 'UTC',
});
// Objetos de plataforma: ausentes num PostgreSQL comum.
const PLATAFORMA = /(pg_cron|supabase_vault|pgsodium|pg_graphql|pg_net|supabase_functions|graphql|cron\.)/i;
const PAPEIS = ['anon', 'authenticated', 'service_role', 'supabase_admin',
  'supabase_auth_admin', 'supabase_storage_admin', 'authenticator',
  'dashboard_user', 'pgbouncer'];
const ESQUEMAS = ['auth', 'storage', 'extensions', 'graphql', 'graphql_public',
  'realtime', 'vault', 'cron', 'pgbouncer'];

function opcoes(argv) {
  const escolhas = { dump: null, modulos: path.join(AQUI, 'node_modules') };
  for (let i = 0; i < argv.length; i += 2) {
    const valor = argv[i + 1];
    if (!valor) throw new Error(`Falta valor para ${argv[i]}`);
    if (argv[i] === '--dump') escolhas.dump = valor;
    else if (argv[i] === '--modulos') escolhas.modulos = valor;
    else throw new Error(`Opção desconhecida: ${argv[i]}`);
  }
  if (!escolhas.dump) throw new Error('Informe --dump com a pasta do dump.');
  return escolhas;
}

function executar(binario, args, { timeout = 600_000 } = {}) {
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

async function dependencias(modulos) {
  const plataforma = `${process.platform}-${process.arch}`;
  const require = createRequire(path.join(modulos, 'index.js'));
  try {
    return { binarios: require(`@embedded-postgres/${plataforma}`), pg: require('pg') };
  } catch (causa) {
    throw new Error(`Não achei @embedded-postgres/${plataforma} e pg em ${modulos}.\n`
      + `Aponte --modulos para o node_modules do laboratório do radar.\n${causa.message}`);
  }
}

/**
 * Divide o dump em comandos. `pg_dump` não gera `$$` no meio de literais de
 * COPY, então quebrar em `;` no fim de linha é suficiente -- exceto dentro de
 * corpo de função (`$$ ... $$`) e de bloco COPY, que são acompanhados aqui.
 */
function comandos(sql) {
  const lista = [];
  let atual = '';
  let dolar = null;
  let copiando = false;
  for (const linha of sql.split('\n')) {
    if (copiando) {
      atual += `${linha}\n`;
      if (linha === '\\.') { lista.push(atual); atual = ''; copiando = false; }
      continue;
    }
    if (!dolar) {
      const abre = linha.match(/\$([A-Za-z_]*)\$/);
      if (abre && (linha.match(/\$([A-Za-z_]*)\$/g) || []).length % 2 === 1) dolar = abre[0];
    } else if (linha.includes(dolar)) {
      dolar = null;
    }
    atual += `${linha}\n`;
    if (!dolar && /^COPY .* FROM stdin;\s*$/i.test(linha)) { copiando = true; continue; }
    if (!dolar && /;\s*$/.test(linha)) { lista.push(atual); atual = ''; }
  }
  if (atual.trim()) lista.push(atual);
  return lista.filter(c => c.trim() && !/^\s*--/.test(c));
}

async function main() {
  const { dump, modulos } = opcoes(process.argv.slice(2));
  if (process.getuid?.() === 0) throw new Error('Rode como usuário comum, sem root.');
  const esperado = JSON.parse(await readFile(EXPECTATIVA, 'utf8'));
  const { binarios, pg } = await dependencias(modulos);
  for (const nome of ['initdb', 'postgres', 'pg_ctl']) await chmod(binarios[nome], 0o755);
  const versao = (await executar(binarios.postgres, ['--version'])).trim();
  if (versao !== `postgres (PostgreSQL) ${VERSAO_ESPERADA}`) {
    throw new Error(`Versão inesperada: ${versao}`);
  }

  const raiz = await mkdtemp(path.join(os.tmpdir(), 'datadrobe-restore-'));
  await chmod(raiz, 0o700);
  const dados = path.join(raiz, 'data');
  const socket = path.join(raiz, 'sock');
  const senhaArquivo = path.join(raiz, 'senha');
  const senha = randomBytes(24).toString('hex');
  await mkdir(socket, { mode: 0o700 });
  await writeFile(senhaArquivo, senha, { mode: 0o600 });

  let processo;
  let cliente;
  const encerrar = async () => {
    if (cliente) await cliente.end().catch(() => {});
    if (processo && processo.exitCode === null) {
      await executar(binarios.pg_ctl, ['stop', '-D', dados, '-m', 'fast', '-w', '-t', '20'])
        .catch(() => processo.kill('SIGKILL'));
      if (processo.exitCode === null) await once(processo, 'exit');
    }
    await rm(raiz, { recursive: true, force: true });
  };

  try {
    await executar(binarios.initdb, ['-D', dados, '-U', 'postgres',
      '--pwfile', senhaArquivo, '--auth=scram-sha-256', '--encoding=UTF8', '--no-locale']);
    processo = spawn(binarios.postgres, ['-D', dados, '-k', socket, '-h', '',
      '-p', '5432', '-c', 'listen_addresses=', '-c', 'fsync=off',
      '-c', 'log_min_messages=warning', '-c', 'maintenance_work_mem=256MB'],
    { env: AMBIENTE, stdio: ['ignore', 'pipe', 'pipe'] });
    processo.stdout.resume();
    processo.stderr.resume();

    const conexao = { host: socket, port: 5432, user: 'postgres', password: senha,
      database: 'postgres', connectionTimeoutMillis: 5_000 };
    for (let tentativa = 0; tentativa < 60 && !cliente; tentativa += 1) {
      const tentativaCliente = new pg.Client(conexao);
      try { await tentativaCliente.connect(); cliente = tentativaCliente; }
      catch { await new Promise(r => setTimeout(r, 250)); }
    }
    if (!cliente) throw new Error('O cluster não aceitou conexão.');

    for (const papel of PAPEIS) {
      await cliente.query(`do $$ begin
        if not exists (select 1 from pg_roles where rolname = '${papel}') then
          create role ${papel} nologin;
        end if; end $$;`);
    }
    for (const esquema of ESQUEMAS) {
      await cliente.query(`create schema if not exists ${esquema};`);
    }
    console.log(`papéis e esquemas de plataforma preparados (${PAPEIS.length}/${ESQUEMAS.length})`);

    const arquivos = ['papeis.sql', 'schema.sql', 'dados.sql'];
    let pulados = 0;
    for (const nome of arquivos) {
      const caminho = path.join(dump, nome);
      const sql = await readFile(caminho, 'utf8');
      const lista = comandos(sql);
      let aplicados = 0;
      for (const comando of lista) {
        try {
          await cliente.query(comando);
          aplicados += 1;
        } catch (erro) {
          const daPlataforma = PLATAFORMA.test(comando) || PLATAFORMA.test(erro.message);
          if (!daPlataforma) {
            throw new Error(`${nome}: ${erro.message}\n--- comando ---\n`
              + `${comando.slice(0, 500)}`);
          }
          pulados += 1;
          console.log(`pulado (plataforma): ${comando.split('\n')[0].slice(0, 120)}`
            + `  [${erro.message.split('\n')[0]}]`);
        }
      }
      console.log(`${nome}: ${aplicados} comandos aplicados de ${lista.length}`);
    }
    console.log(`comandos de plataforma pulados: ${pulados}`);

    const divergencias = [];
    for (const [tabela, linhas] of Object.entries(esperado.linhas_por_tabela)) {
      const { rows } = await cliente.query(
        `select count(*)::bigint as n from public.${tabela}`).catch(() => ({ rows: null }));
      if (!rows) { divergencias.push(`${tabela}: tabela ausente`); continue; }
      const obtido = Number(rows[0].n);
      if (obtido !== linhas) divergencias.push(`${tabela}: ${obtido} != ${linhas}`);
    }
    const { rows: funcoes } = await cliente.query(
      `select count(*)::int as n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'`);
    const { rows: politicas } = await cliente.query(
      "select count(*)::int as n from pg_policies where schemaname = 'public'");
    if (funcoes[0].n < esperado.funcoes_no_public) {
      divergencias.push(`funções: ${funcoes[0].n} < ${esperado.funcoes_no_public}`);
    }
    if (politicas[0].n < esperado.politicas_rls_no_public) {
      divergencias.push(`políticas RLS: ${politicas[0].n} < ${esperado.politicas_rls_no_public}`);
    }

    console.log(`funções no public: ${funcoes[0].n} (esperado ${esperado.funcoes_no_public})`);
    console.log(`políticas RLS: ${politicas[0].n} (esperado ${esperado.politicas_rls_no_public})`);
    if (divergencias.length) {
      throw new Error(`restauração divergente:\n- ${divergencias.join('\n- ')}`);
    }
    console.log('RESTAURACAO VERDE');
  } finally {
    await encerrar();
  }
}

main().catch(erro => {
  console.error(`FALHOU: ${erro.message}`);
  process.exit(1);
});
