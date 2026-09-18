#!/usr/bin/env node
/**
 * Laboratório de capacidade: P21, P22, P24 e P25 num PostgreSQL 17.10 real,
 * descartável, acessível somente pelo socket deste processo.
 *
 * O QUE ELE PROVA
 * ===============
 *
 * 1. Que o "antes" é o código de produção. As definições atuais de
 *    `computar_serie_varejo`, `computar_serie_editorial`, `computar_z`,
 *    `computar_indice` e `uso_do_banco` são extraídas das migrations no momento da
 *    execução -- nunca copiadas à mão -- e o hash de `pg_get_functiondef` de
 *    cada uma é comparado com o medido em produção (`hashes_de_producao.json`).
 *    Hash divergente é falha: o laboratório estaria testando outra coisa.
 *
 * 2. Que o defeito existe. `linha_de_base.sql` roda as funções ANTIGAS duas
 *    vezes e exige que a segunda reescreva todas as linhas. Se um dia essa
 *    asserção falhar, o teste deixou de distinguir o antes do depois. As duas
 *    tabelas são esvaziadas em seguida.
 *
 * 3. Que a correção funciona, caminho por caminho: primeira escrita,
 *    reexecução idêntica com zero linhas reescritas, e mudança real com
 *    somente as linhas cujo valor mudou -- medidas por três instrumentos
 *    independentes: o retorno da função, o contador de updates da transação
 *    (`pg_stat_get_xact_tuples_updated`) e o `ctid` de cada linha.
 *
 * COMO RODAR
 * ==========
 *
 *   node ferramentas/laboratorio_capacidade/rodar.mjs [--modulos <node_modules>]
 *
 * Os binários vêm de `@embedded-postgres`, declarado no `package.json` desta
 * pasta. Instale uma vez, fora da árvore de trabalho:
 *
 *   LAB=~/.canario/laboratorio-capacidade
 *   mkdir -p "$LAB" && cp ferramentas/laboratorio_capacidade/package*.json "$LAB/"
 *   (cd "$LAB" && npm install --no-audit --no-fund)
 *
 * Nada aqui fala com o Supabase.
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
const MIGRATIONS = path.join(REPOSITORIO, 'supabase/migrations');
const VERSAO_ESPERADA = '17.10';
const AMBIENTE = Object.freeze({
  PATH: '/usr/local/bin:/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', TZ: 'UTC',
});

// As funções que P21, P22, P24 e P25 substituem. O "antes" é a ÚLTIMA definição
// de cada uma nas migrations anteriores a elas -- a mesma regra de
// `coletor/teste_migrations.py`.
const ANTIGAS = ['computar_serie_varejo', 'computar_serie_editorial',
  'computar_z', 'computar_indice', 'uso_do_banco', 'podar_snapshots'];
const P21 = '20260917200000_p21_uso_do_banco_mede_a_cota.sql';
const P22 = '20260917201000_p22_series_sem_reescrita_identica.sql';
const P24 = '20260917203000_p24_poda_espera_o_denominador.sql';
const P25 = '20260917204000_p25_indices_sem_reescrita_identica.sql';

// O backup restaurável de 18/09 mostrou uma divergência de uma linha entre a
// migration histórica e a função realmente ativa. O cálculo é idêntico; só a
// prosa de `meta.por_que` é curta em produção. A linha de base precisa carregar
// o que estava no banco, não uma reconstrução que nunca rodou lá.
const PORQUE_NO_REPOSITORIO = 'o app posiciona peca no mercado brasileiro; '
  + 'quem confirma direcao daqui e sinal daqui. Medido em 06/08: '
  + 'busca x editorial_br r=0,235 e 67,7% de mesmo sinal; '
  + 'busca x editorial_intl r=-0,070, dentro de um erro-padrao de zero';
const PORQUE_EM_PRODUCAO = 'o app posiciona peca no mercado brasileiro; '
  + 'quem confirma direcao daqui e sinal daqui';

const CANDIDATOS = [
  path.join(AQUI, 'node_modules'),
  path.join(os.homedir(), '.canario/laboratorio-capacidade/node_modules'),
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
    } catch { /* tenta o próximo */ }
  }
  throw new Error('Não achei `pg` nem `@embedded-postgres`. Instale uma vez:\n'
    + '  LAB=~/.canario/laboratorio-capacidade\n'
    + '  mkdir -p "$LAB" && cp ferramentas/laboratorio_capacidade/package*.json "$LAB/"\n'
    + '  (cd "$LAB" && npm install --no-audit --no-fund)');
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

/** A última definição de `public.<nome>` nas migrations anteriores à P21. */
async function definicaoAtual(nome) {
  const { readdir } = await import('node:fs/promises');
  const arquivos = (await readdir(MIGRATIONS))
    .filter(a => a.endsWith('.sql') && a < P21)
    .sort()
    .reverse();
  const assinatura = `create or replace function public.${nome}(`;
  for (const arquivo of arquivos) {
    const texto = await readFile(path.join(MIGRATIONS, arquivo), 'utf8');
    const inicio = texto.toLowerCase().lastIndexOf(assinatura);
    if (inicio < 0) continue;
    const corpo = texto.indexOf('$function$', inicio);
    const fim = texto.indexOf('$function$;', corpo + 10);
    let sql = texto.slice(inicio, fim + '$function$;'.length);
    let origem = arquivo;
    if (nome === 'computar_indice') {
      const ocorrencias = sql.split(PORQUE_NO_REPOSITORIO).length - 1;
      if (ocorrencias !== 1) {
        throw new Error(`computar_indice: esperava uma prosa histórica e achei ${ocorrencias}.`);
      }
      sql = sql.replace(PORQUE_NO_REPOSITORIO, PORQUE_EM_PRODUCAO);
      origem += ' + prosa curta capturada no backup de 18/09';
    }
    return { arquivo: origem, sql };
  }
  throw new Error(`Não achei a definição atual de ${nome}.`);
}

async function main() {
  const modulos = await ondeEstaoOsModulos(opcoes(process.argv.slice(2)).modulos);
  if (process.getuid?.() === 0) throw new Error('Rode como usuário comum, sem root.');
  const require = createRequire(path.join(modulos, 'index.js'));
  const binarios = require(`@embedded-postgres/${process.platform}-${process.arch}`);
  const pg = require('pg');
  for (const nome of ['initdb', 'postgres', 'pg_ctl']) await chmod(binarios[nome], 0o755);
  const versao = (await executar(binarios.postgres, ['--version'])).trim();
  if (versao !== `postgres (PostgreSQL) ${VERSAO_ESPERADA}`) {
    throw new Error(`Versão inesperada: ${versao}`);
  }

  const raiz = await mkdtemp(path.join(os.tmpdir(), 'datadrobe-cap-'));
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
      await executar(binarios.pg_ctl, ['stop', '-D', dados, '-m', 'fast', '-w', '-t', '10'])
        .catch(() => processo.kill('SIGKILL'));
      if (processo.exitCode === null) await once(processo, 'exit');
    }
    await rm(raiz, { recursive: true, force: true });
  };

  try {
    await executar(binarios.initdb, ['-D', dados, '-U', 'lab', '--pwfile', senhaArquivo,
      '--auth=scram-sha-256', '--encoding=UTF8', '--no-locale']);
    processo = spawn(binarios.postgres, ['-D', dados, '-k', socket, '-h', '', '-p', '5432',
      '-c', 'listen_addresses=', '-c', 'fsync=off', '-c', 'log_min_messages=warning',
      '-c', 'track_counts=on'],
    { env: AMBIENTE, stdio: ['ignore', 'pipe', 'pipe'] });
    processo.stdout.resume();
    processo.stderr.resume();

    const conexao = { host: socket, port: 5432, user: 'lab', password: senha,
      database: 'postgres', connectionTimeoutMillis: 5_000 };
    for (let tentativa = 0; tentativa < 50 && !cliente; tentativa += 1) {
      const c = new pg.Client(conexao);
      try { await c.connect(); cliente = c; }
      catch { await new Promise(r => setTimeout(r, 200)); }
    }
    if (!cliente) throw new Error('O cluster não aceitou conexão.');
    cliente.on('notice', aviso => { if (aviso.message) console.log(aviso.message); });

    const aplicar = async (rotulo, sql) => {
      await cliente.query(sql);
      console.log(`aplicado ${rotulo}`);
    };

    // Um bloco `do $$ ... end $$;` por transação, como o motor faz: cada
    // publicação chama cada função uma vez. `computar_serie_varejo` cria uma
    // tabela temporária `on commit drop` e não pode ser chamada duas vezes na
    // mesma transação -- é assim em produção, e o laboratório não esconde isso.
    // Os contadores `pg_stat_get_xact_*` também são por transação, então cada
    // bloco mede só o que ele próprio escreveu.
    const porBloco = async (rotulo, sql) => {
      const blocos = sql.split(/^end \$\$;[ \t]*$/m)
        .map(b => b.trim()).filter(b => /\bdo \$\$/.test(b))
        .map(b => `${b.slice(b.search(/\bdo \$\$/))}\nend $$;`);
      for (const bloco of blocos) await cliente.query(bloco);
      console.log(`aplicado ${rotulo} (${blocos.length} blocos, um por transacao)`);
    };

    await aplicar('fixture.sql', await readFile(path.join(AQUI, 'fixture.sql'), 'utf8'));

    // O "antes": as definições que estão em produção hoje.
    const esperados = JSON.parse(
      await readFile(path.join(AQUI, 'hashes_de_producao.json'), 'utf8')).funcoes;
    for (const nome of ANTIGAS) {
      const { arquivo, sql } = await definicaoAtual(nome);
      await cliente.query(sql);
      const { rows } = await cliente.query(
        `select md5(regexp_replace(pg_get_functiondef('public.${nome}'::regproc),
                                   '\\s+', ' ', 'g')) as hash`);
      if (rows[0].hash !== esperados[nome]) {
        throw new Error(`${nome}: hash ${rows[0].hash} difere do medido em produção `
          + `(${esperados[nome]}). O "antes" do laboratório não é o código de produção.`);
      }
      console.log(`antes = producao  ${nome.padEnd(26)} ${rows[0].hash}  (${arquivo})`);
    }
    await cliente.query(
      'grant execute on function public.uso_do_banco() to service_role;');

    // O defeito, medido com o código antigo. As duas tabelas voltam vazias.
    await porBloco('linha_de_base.sql',
      await readFile(path.join(AQUI, 'linha_de_base.sql'), 'utf8'));
    await cliente.query(
      'truncate public.indices_semanais, public.series_semanais restart identity');

    for (const m of [P21, P22, P24, P25]) {
      await aplicar(`supabase/migrations/${m}`,
        await readFile(path.join(MIGRATIONS, m), 'utf8'));
    }
    await porBloco('assercoes.sql', await readFile(path.join(AQUI, 'assercoes.sql'), 'utf8'));
    console.log('LABORATORIO VERDE');
  } finally {
    await encerrar();
  }
}

main().catch(erro => {
  console.error(`FALHOU: ${erro.message}`);
  process.exit(1);
});
