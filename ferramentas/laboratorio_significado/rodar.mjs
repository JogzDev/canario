#!/usr/bin/env node
/**
 * Laboratório de significado: roda P24, A57, A58, A60, A61, A62, as duas
 * A64 (cobertura e leitura), A65, A66 e A68 num PostgreSQL 17.10 real,
 * descartável, acessível somente pelo socket deste processo. A A62 e a A68
 * são provadas também por mutação: cada regra delas é retirada por vez, e as
 * asserções precisam reprovar todas as versões mutantes.
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
  // Ordem real do rollout: a guarda transitória entra antes de a A58 criar e
  // preencher `sortimento_diario`; só então a poda volta a agir normalmente.
  'supabase/migrations/20260917203000_p24_poda_espera_o_denominador.sql',
  'supabase/migrations/20260917210000_a57_frescor_ancorado_no_dado.sql',
  'supabase/migrations/20260917211000_a58_significado_da_capa_e_busca_editorial.sql',
];
const A60 = 'supabase/migrations/20260923031907_a60_cobertura_unica_da_publicacao.sql';
const A61 = 'supabase/migrations/20260923131757_a61_troca_de_catalogo.sql';
const A62 = 'supabase/migrations/20260923154011_a62_curva_so_com_produtos_ativos.sql';
const A64 = 'supabase/migrations/20260924012854_a64_candidatas_e_fatos_da_leitura.sql';
const A65 = 'supabase/migrations/20260924013846_a65_novidade_nao_e_estreia_de_catalogo.sql';
const A66 = 'supabase/migrations/20260924014452_a66_atributos_da_taxonomia_na_leitura.sql';
const A68 = 'supabase/migrations/20260924015133_a68_curva_mede_a_janela_observada.sql';
// O "antes" da A62 é o que está em produção: a curva da P0 e a ordem da grade
// da F4. `linha_de_base_a62.sql` confere o md5 de cada corpo.
const ANTES_DA_A62 = [
  ['supabase/migrations/20260801045954_f4_ordem_do_tamanho_zeros.sql', 'ordem_do_tamanho'],
  ['supabase/migrations/20260803223000_p0_motor_sem_spill_de_disco.sql', 'computar_curva_tamanhos'],
];
// Cada mutação tira ou afrouxa UMA regra da A62. Se `assercoes_a62.sql`
// continuar verde com ela, a regra não está provada por ninguém.
const MUTACOES_A62 = [
  ['sem a janela de sete dias',
    'ep.ultimo_avistamento_em >= a.observado_em - 7', 'true'],
  ['janela de oito dias', 'a.observado_em - 7', 'a.observado_em - 8'],
  ['âncora no calendário',
    'ep.ultimo_avistamento_em >= a.observado_em - 7',
    'ep.ultimo_avistamento_em >= current_date - 7'],
  ['âncora única para todos os segmentos',
    'join _curva_ancora a on a.segmento = p.segmento',
    'cross join (select max(observado_em) as observado_em from _curva_ancora) a'],
  ['segmento parado ganha a semana nova',
    '\n  having max(ep.ultimo_avistamento_em) > (semana_alvo + 6) - janela_dias;', ';'],
  ['catálogo aposentado na base', 'where ca.produto_id = p.id)', 'where false)'],
  ['só o ofertável de hoje',
    'or exists (select 1 from snapshots s',
    'or false and exists (select 1 from snapshots s'],
  ['toda peça listada, esgotada ou não', '(ep.ofertavel is true', '(true'],
  ['qualquer snapshot na janela, com ou sem oferta', 'and s.ofertavel is true', 'and true'],
  ['semana alvo sem apagar o que sumiu',
    'where c.semana = semana_alvo', 'where false and c.semana = semana_alvo'],
  ['apaga também as semanas já publicadas', 'where c.semana = semana_alvo', 'where true'],
];
// Duas migrations nasceram com o rótulo A64 na noite de 23/09. Esta é a da
// cobertura de publicação; a `A64` acima é a da leitura específica.
const COBERTURA_NUVEMSHOP =
  'supabase/migrations/20260924013645_a64_cobertura_espera_a_nuvemshop.sql';
// Cada mutação tira ou afrouxa UMA regra da A68. O `visitados > 0` não está
// aqui: com histórico positivo nos sete dias, o piso de 30% já barra o dia
// zerado, e sem histórico a marca não tem outro dia na janela. Fica por
// paridade com a linha saudável da A60.
const MUTACOES_A68 = [
  ['início sem limite de idade da foto', 'and s.data > m.inicio - 7', 'and true'],
  ['peça não vista no início também conta',
    'where ep.ultimo_avistamento_em >= mj.inicio', 'where true'],
  ['início estrito, antes do primeiro dia observado',
    'where s.data <= m.inicio', 'where s.data < m.inicio'],
  ['início pela foto mais recente da janela',
    'where s.data <= m.inicio', 'where s.data <= m.fim'],
  ['marca de uma coleta só ganha janela', '\n  having max(data) > min(data);', ';'],
  ['coleta truncada conta como observação',
    "and not (l.alertas ?| array['truncou', 'faixas_truncadas'])", 'and true'],
  ['coleta parcial conta como observação',
    'or l.visitados::numeric >= historico.media_positiva_7d * 0.30)', 'or true)'],
  ['janela declarada nos 14 dias nominais',
    "'dias', js.fim - js.inicio,", "'dias', janela_dias,"],
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

    // A A60 entra DEPOIS do portão 87 e das asserções 1-24: o 87 confere o
    // hash que a A58 deixou em produção, e as 24 provam o contrato da A58. Só
    // então a regra única de cobertura substitui o motor e é provada de novo.
    const arquivos = [
      path.join(AQUI, 'fixture.sql'),
      ...MIGRATIONS.map(m => path.join(REPOSITORIO, m)),
      path.join(REPOSITORIO, 'ferramentas/capacidade/87_confere_depois_da_a57_a58.sql'),
      path.join(AQUI, 'assercoes.sql'),
      path.join(REPOSITORIO, A60),
      path.join(AQUI, 'assercoes_a60.sql'),
      // A A61 troca tres passos que a fixture base deixa como talos. A
      // fixture dela acrescenta so o que as versoes reais leem.
      path.join(AQUI, 'fixture_a61.sql'),
      path.join(REPOSITORIO, A61),
      path.join(AQUI, 'assercoes_a61.sql'),
    ];
    let silencio = false;
    cliente.on('notice', aviso => {
      if (aviso.message && !silencio) console.log(aviso.message);
    });
    const aplicar = async arquivo => {
      const sql = await readFile(arquivo, 'utf8');
      await cliente.query(sql);
      const nome = path.basename(arquivo);
      const migration = nome.match(/^(\d{14})_([a-z0-9_]+)\.sql$/);
      if (migration) {
        await cliente.query(
          'insert into supabase_migrations.schema_migrations(version,name,statements) '
          + 'values ($1,$2,array[$3])', [migration[1], migration[2], sql]);
      }
      console.log(`aplicado ${path.relative(REPOSITORIO, arquivo)}`);
    };
    for (const arquivo of arquivos) await aplicar(arquivo);

    // Uma prova só vale se reprova o defeito que diz pegar. `preparo` (uma
    // migration mutante, ou nada) e as asserções rodam numa transação desfeita
    // no fim, e só uma asserção (P0004) conta como reprovação: erro de
    // sintaxe ou de execução seria uma morte falsa.
    const exigirReprovacao = async (rotulo, preparo, assercoes) => {
      await cliente.query('begin');
      silencio = true;
      try {
        if (preparo) {
          try {
            await cliente.query(preparo);
          } catch (erro) {
            throw new Error(`${rotulo} não se aplica: ${erro.message}`);
          }
        }
        try {
          await cliente.query(assercoes);
        } catch (erro) {
          if (erro.code !== 'P0004') {
            throw new Error(`${rotulo} quebrou sem asserção: ${erro.message}`);
          }
          return erro.message;
        }
        throw new Error(`${rotulo} passou nas asserções`);
      } finally {
        silencio = false;
        await cliente.query('rollback');
      }
    };

    // A64 da cobertura. Sem ela, a regra da A60 deixa a marca da Nuvemshop
    // fora da coorte: a asserção 59 tem de reprovar antes e passar depois.
    const assercoesCobertura = await readFile(
      path.join(AQUI, 'assercoes_cobertura_nuvemshop.sql'), 'utf8');
    const antesDaCobertura = await exigirReprovacao(
      'antes da cobertura com a Nuvemshop', null, assercoesCobertura);
    console.log(`ok 59 antes: a cobertura da A60 ignora a Nuvemshop: ${antesDaCobertura}`);
    await aplicar(path.join(REPOSITORIO, COBERTURA_NUVEMSHOP));
    await aplicar(path.join(AQUI, 'assercoes_cobertura_nuvemshop.sql'));

    // A62. O antes entra como função solta, não como migration: a P0 e a F4
    // já estão no histórico de produção e não se reaplicam por inteiro.
    await aplicar(path.join(AQUI, 'fixture_a62.sql'));
    for (const [arquivo, nome] of ANTES_DA_A62) {
      await cliente.query(await definicaoNaMigration(arquivo, nome));
      console.log(`aplicado ${nome} de ${arquivo}`);
    }
    await aplicar(path.join(AQUI, 'linha_de_base_a62.sql'));

    // As mutações rodam ANTES da A62 verdadeira, cada uma sobre a semana que
    // a P0 deixou.
    const a62 = await readFile(path.join(REPOSITORIO, A62), 'utf8');
    const assercoesA62 = await readFile(path.join(AQUI, 'assercoes_a62.sql'), 'utf8');
    for (const [indice, [nome, trecho, troca]] of MUTACOES_A62.entries()) {
      const ocorrencias = a62.split(trecho).length - 1;
      if (ocorrencias !== 1) {
        throw new Error(`mutação "${nome}": o trecho aparece ${ocorrencias} vezes na A62`);
      }
      const motivo = await exigirReprovacao(
        `mutação "${nome}"`, a62.replace(trecho, () => troca), assercoesA62);
      console.log(`ok ${48 + indice} mutação reprovada (${nome}): ${motivo}`);
    }

    await aplicar(path.join(REPOSITORIO, A62));
    await aplicar(path.join(AQUI, 'assercoes_a62.sql'));
    // A64: candidatas e fatos da leitura especifica, sobre o painel que a
    // A62 deixou publicado.
    await aplicar(path.join(AQUI, 'fixture_a64.sql'));
    await aplicar(path.join(REPOSITORIO, A64));
    await aplicar(path.join(AQUI, 'assercoes_a64.sql'));
    await aplicar(path.join(AQUI, 'fixture_a65.sql'));
    await aplicar(path.join(REPOSITORIO, A65));
    await aplicar(path.join(AQUI, 'assercoes_a65.sql'));
    await aplicar(path.join(AQUI, 'fixture_a66.sql'));
    await aplicar(path.join(REPOSITORIO, A66));
    await aplicar(path.join(AQUI, 'assercoes_a66.sql'));

    // A68: a curva mede a janela que observou. A fixture dá às marcas da A62
    // os dias de coleta que as contas dela pedem; depois da A68 verdadeira, as
    // asserções da A62 rodam de novo, inteiras: a base e a vitrine não mudam.
    await aplicar(path.join(AQUI, 'fixture_a68.sql'));
    const a68 = await readFile(path.join(REPOSITORIO, A68), 'utf8');
    const assercoesA68 = await readFile(path.join(AQUI, 'assercoes_a68.sql'), 'utf8');
    for (const [indice, [nome, trecho, troca]] of MUTACOES_A68.entries()) {
      const ocorrencias = a68.split(trecho).length - 1;
      if (ocorrencias !== 1) {
        throw new Error(`mutação "${nome}": o trecho aparece ${ocorrencias} vezes na A68`);
      }
      const motivo = await exigirReprovacao(
        `mutação "${nome}"`, a68.replace(trecho, () => troca), assercoesA68);
      console.log(`ok ${86 + indice} mutação reprovada (${nome}): ${motivo}`);
    }
    await aplicar(path.join(REPOSITORIO, A68));
    await aplicar(path.join(AQUI, 'assercoes_a68.sql'));
    await aplicar(path.join(AQUI, 'assercoes_a62.sql'));
    // A consulta de capacidade/cobertura também precisa executar de verdade.
    // READ ONLY torna uma escrita acidental uma falha do laboratório.
    const diagnostico = await readFile(path.join(REPOSITORIO,
      'ferramentas/capacidade/91_diagnostico_pos_poda.sql'), 'utf8');
    await cliente.query('begin transaction read only');
    try {
      const resultados = await cliente.query(diagnostico);
      const selects = [].concat(resultados).filter(r => r.command === 'SELECT');
      if (selects.length !== 8) throw new Error('diagnóstico 91 perdeu uma consulta');
      if (!selects[0].rows[0]?.cota_bytes
          || !selects[1].rows.some(r => r.tabela === 'public.snapshots')
          || !selects[6].rows.some(r => r.segmento === 'feminino_casual_br')
          || selects[7].rows.length === 0) {
        throw new Error('diagnóstico 91 não devolveu capacidade/cobertura esperadas');
      }
      console.log('ok 25 diagnóstico pós-poda: oito consultas executadas em READ ONLY');
    } finally {
      await cliente.query('rollback');
    }
    console.log('LABORATORIO VERDE');
  } finally {
    await encerrar();
  }
}

/**
 * A última definição de `public.<nome>` num arquivo de migration, do `create`
 * ao fecho das aspas: é o que aquela migration deixou instalado.
 */
async function definicaoNaMigration(arquivo, nome) {
  const texto = await readFile(path.join(REPOSITORIO, arquivo), 'utf8');
  const inicio = texto.toLowerCase().lastIndexOf(`create or replace function public.${nome}(`);
  if (inicio < 0) throw new Error(`${nome} não está em ${arquivo}`);
  const aspas = /\nas (\$[a-z_]*\$)/i.exec(texto.slice(inicio));
  if (!aspas) throw new Error(`${nome} sem corpo em ${arquivo}`);
  const corpo = inicio + aspas.index + aspas[0].length;
  const fim = texto.indexOf(aspas[1], corpo);
  if (fim < 0) throw new Error(`${nome} sem fecho em ${arquivo}`);
  return `${texto.slice(inicio, fim + aspas[1].length)};`;
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
