#!/usr/bin/env node
/**
 * Ensaio do roteiro da etapa 1 num PostgreSQL 17.10 descartável.
 *
 * Os arquivos são exercitados pelo MESMO executor que rodaria em produção
 * (`passo.mjs`), como subprocesso, conectado como um papel que imita o
 * `postgres` do Supabase: sem superusuário, dono das tabelas de `public`,
 * membro de `pg_read_all_stats` e `pg_monitor`, e sem ser dono do log do
 * pg_cron -- onde só tem MAINTAIN e DELETE, como em produção. O teto 40/60 é
 * deslocado apenas no socket local por uma opção recusada em produção.
 *
 * O que ele prova:
 *   - o ensaio (sem --executar) não escreve nada;
 *   - cada ação encolhe o alvo e não perde nenhuma linha;
 *   - o 60 direto reconstrói heap, chave primária e índice único de URL;
 *   - 40 e 60 são ramos separados, nunca uma sequência;
 *   - cada pré-condição aborta ANTES da ação quando deve;
 *   - o TRUNCATE alternativo vem desarmado;
 *   - VACUUM sem MAINTAIN é pego pela checagem de encolhimento.
 *
 * O que ele NÃO prova: tempo e espaço de produção. As tabelas daqui são
 * pequenas; o disco é outro. Os números de produção vêm do inventário.
 */
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORIO = path.resolve(AQUI, '../..');
const MIGRATIONS = path.join(REPOSITORIO, 'supabase/migrations');
const AMBIENTE = { PATH: '/usr/local/bin:/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', TZ: 'UTC' };
const MODULOS = [
  path.join(os.homedir(), '.canario/laboratorio-capacidade/node_modules'),
  path.join(os.homedir(), '.canario/laboratorio-significado/node_modules'),
].find(c => { try { createRequire(path.join(c, 'index.js')).resolve('pg'); return true; } catch { return false; } });

let falhas = 0;
function conferir(condicao, mensagem) {
  if (condicao) console.log(`ok  ${mensagem}`);
  else { console.log(`FALHOU  ${mensagem}`); falhas += 1; }
}

async function main() {
  if (!MODULOS) throw new Error('Instale o laboratório de capacidade (ver README).');
  const require = createRequire(path.join(MODULOS, 'index.js'));
  const b = require(`@embedded-postgres/${process.platform}-${process.arch}`);
  const pg = require('pg');
  for (const n of ['initdb', 'postgres', 'pg_ctl']) await chmod(b[n], 0o755);

  const raiz = await mkdtemp(path.join(os.tmpdir(), 'datadrobe-rot-'));
  await chmod(raiz, 0o700);
  const dados = path.join(raiz, 'd');
  const sock = path.join(raiz, 's');
  await mkdir(sock, { mode: 0o700 });
  // `trust` só no socket, numa pasta 0700 deste processo: é o que deixa o
  // executor conectar como papel comum sem senha no laboratório.
  spawnSync(b.initdb, ['-D', dados, '-U', 'lab', '--auth=trust', '--no-locale',
    '--encoding=UTF8'], { env: AMBIENTE });
  const servidor = spawn(b.postgres, ['-D', dados, '-k', sock, '-h', '',
    '-c', 'listen_addresses=', '-c', 'fsync=off', '-c', 'autovacuum=off'],
  { env: AMBIENTE, stdio: 'ignore' });

  const conectar = async (usuario) => {
    for (let t = 0; t < 50; t += 1) {
      const c = new pg.Client({ host: sock, user: usuario, database: 'postgres' });
      // Sem isto, o desligamento do cluster no `finally` derruba o processo
      // antes de ele imprimir o erro que levou até lá.
      c.on('error', () => {});
      try { await c.connect(); return c; } catch { await new Promise(r => setTimeout(r, 200)); }
    }
    throw new Error('o cluster não aceitou conexão');
  };
  const admin = await conectar('lab');

  const passo = (arquivo, ...extra) => {
    const caminho = path.isAbsolute(arquivo) ? arquivo : path.join(AQUI, arquivo);
    const r = spawnSync(process.execPath, [path.join(AQUI, 'passo.mjs'),
      caminho, '--socket', sock, '--usuario', 'operador',
      '--senha-vazia', '--modulos', MODULOS, ...extra], { encoding: 'utf8' });
    return { codigo: r.status, saida: `${r.stdout}${r.stderr}` };
  };
  const tamanho = async (rel) => Number((await admin.query(
    'select pg_total_relation_size($1::regclass) as n', [rel])).rows[0].n);
  const linhas = async (rel) => Number((await admin.query(
    `select count(*) as n from ${rel}`)).rows[0].n);
  const tamanhoRelacao = async (rel) => Number((await admin.query(
    'select pg_relation_size($1::regclass) as n', [rel])).rows[0].n);

  try {
    // Papéis no formato de produção.
    await admin.query(`
      create role operador login in role pg_read_all_stats, pg_monitor;
      create role admin_da_plataforma nologin;
      create role service_role nologin;
      create role anon nologin;
      create role authenticated nologin;
      grant create on schema public to operador;
      create schema cron authorization admin_da_plataforma;
      grant usage on schema cron to operador;
      create schema supabase_migrations;
      create table supabase_migrations.schema_migrations (version text primary key,
        statements text[], name text, created_by text, idempotency_key text,
        rollback text[]);
      grant usage on schema supabase_migrations to operador;
      grant select, insert on supabase_migrations.schema_migrations to operador;`);

    // Tabelas de public, criadas pelo operador -- ele é o dono, como o
    // `postgres` é em produção.
    const op = await conectar('operador');
    await op.query(`
      create table public.motor_execucoes (execucao uuid, status text,
        iniciado_em timestamptz, concluido_em timestamptz, resultado jsonb);
      create table public.series_semanais (id bigint generated by default as identity primary key,
        termo_id text, segmento text, fonte text, semana date, valor_bruto numeric,
        z numeric, n_amostra int, meta jsonb, unique (termo_id, segmento, fonte, semana))
        with (fillfactor = 70);
      create table public.indices_semanais (id bigint generated by default as identity primary key,
        termo_id text, segmento text, semana date, indice numeric,
        estado text, pernas_ativas text[], n_pernas integer, meta jsonb,
        computado_em timestamptz not null default now(),
        unique (termo_id, segmento, semana)) with (fillfactor = 70);
      create table public.artigos (id bigint generated by default as identity primary key,
        url text unique, titulo text);
      create table public.estado_dos_produtos (produto_id bigint primary key,
        ultimo_avistamento_em date, ofertavel boolean);
      create index estado_produtos_oferta_recente on public.estado_dos_produtos
        (ultimo_avistamento_em desc, produto_id) where ofertavel is true;
      create table public.snapshots (id bigint generated by default as identity primary key,
        produto_id bigint, data date, ofertavel boolean, unique (produto_id, data));
      create table public.produtos (id bigint primary key);`);

    // Inchaço fabricado do mesmo jeito que em produção: reescrita repetida.
    await op.query(`
      insert into public.series_semanais (termo_id, segmento, fonte, semana, valor_bruto, meta)
      select 't' || (n % 200), 'feminino_casual_br', 'busca', date '2026-01-05' + 7 * (n / 200),
             n, jsonb_build_object('x', repeat('m', 300))
      from generate_series(1, 8000) n;
      insert into public.indices_semanais (termo_id, segmento, semana, indice, meta)
      select 't' || (n % 200), 'feminino_casual_br', date '2026-01-05' + 7 * (n / 200), n,
             jsonb_build_object('x', repeat('i', 300))
      from generate_series(1, 4000) n;
      insert into public.artigos (url, titulo)
      select 'https://exemplo.invalid/materia/' || n || '/' || md5(n::text), 'titulo ' || n
      from generate_series(1, 20000) n;
      insert into public.estado_dos_produtos
      select n, date '2026-08-01', true from generate_series(1, 10000) n;
      insert into public.snapshots (produto_id, data, ofertavel)
      select n, date '2026-08-12' + (n % 22), true from generate_series(1, 5000) n;`);
    for (let i = 0; i < 6; i += 1) {
      await op.query('update public.series_semanais set z = coalesce(z, 0) + 1');
      await op.query('update public.indices_semanais set indice = indice + 1');
      await op.query(`update public.estado_dos_produtos
                         set ultimo_avistamento_em = ultimo_avistamento_em + 1`);
    }
    await op.query('update public.artigos set titulo = titulo || \'.\'');
    await op.query('delete from public.artigos where id % 2 = 0');
    await op.query('vacuum public.series_semanais, public.indices_semanais, '
      + 'public.artigos, public.estado_dos_produtos');

    // O log do pg_cron: dono é a plataforma; o operador tem MAINTAIN e DELETE.
    await admin.query(`
      create table cron.job_run_details (runid bigint primary key, jobid bigint,
        status text, command text, return_message text,
        start_time timestamptz, end_time timestamptz);
      alter table cron.job_run_details owner to admin_da_plataforma;
      create table cron.job (jobid bigint, jobname text, schedule text, active boolean);
      alter table cron.job owner to admin_da_plataforma;
      grant select on cron.job to operador;
      grant select, delete on cron.job_run_details to operador;
      insert into cron.job_run_details
      select n, 2, case when n % 50 = 0 then 'failed' else 'succeeded' end,
             'select public.executar_proxima_publicacao_motor();', '1 row',
             now() - (n || ' minutes')::interval, now() - (n || ' minutes')::interval
      from generate_series(1, 30000) n
      -- Nenhuma linha a menos de 10 minutos da fronteira de 7 dias: o ensaio
      -- leva segundos, e uma linha na fronteira mudaria de lado no meio dele.
      where n not between 10070 and 10090;`);

    // 00: inventário roda inteiro em leitura. As consultas 3 e 4 leem
    // tabelas que este ensaio não cria completas; o que se testa aqui é o
    // executor, então o inventário de produção fica para a consulta real.
    const semAcao = passo('70_confere_folga.sql');
    conferir(semAcao.codigo === 0 && /passo sem ação/.test(semAcao.saida),
      '70 roda só leitura e passa com o banco pequeno do laboratório');

    // O cluster descartável é muito menor que 400 MB. Para provar também o
    // ramo de rejeição sem fabricar 400 MB de lixo, a fixture é derivada do
    // arquivo de produção e troca somente a meta por 1 byte. O SQL de
    // produção permanece intacto e roda acima com a meta real.
    const texto70 = await readFile(path.join(AQUI, '70_confere_folga.sql'), 'utf8');
    const limite70 = 'if cota > 400000000 then';
    if (texto70.split(limite70).length !== 2) {
      throw new Error('a fixture do 70 esperava uma única comparação de cota');
    }
    const fixture70 = path.join(raiz, '70_cota_acima_fixture.sql');
    await writeFile(fixture70, texto70.replace(limite70, 'if cota > 1 then'),
      { mode: 0o600 });
    const semFolga = passo(fixture70);
    conferir(semFolga.codigo === 1 && /FOLGA INSUFICIENTE/.test(semFolga.saida),
      '70 rejeita cota acima da meta (limite escalado só na fixture local)');

    // 11 antes de 10: aborta.
    let r = passo('11_log_do_cron_compactar.sql', '--executar');
    conferir(r.codigo === 1 && /rode o passo 10 antes/.test(r.saida),
      '11 recusa compactar antes de apagar');

    // 10 em ensaio: nada muda.
    const cronAntes = await linhas('cron.job_run_details');
    r = passo('10_log_do_cron_apagar_antigos.sql');
    conferir(r.codigo === 0 && /ENSAIO/.test(r.saida)
      && await linhas('cron.job_run_details') === cronAntes,
      '10 em ensaio não apaga nada');

    // 10 de verdade: só o que passou da retenção.
    r = passo('10_log_do_cron_apagar_antigos.sql', '--executar');
    const esperado = Number((await admin.query(`select count(*) as n from
      generate_series(1, 30000) n where n not between 10070 and 10090 and not (
        (n * interval '1 minute' > interval '7 days' and n % 50 <> 0)
        or n * interval '1 minute' > interval '30 days')`)).rows[0].n);
    const cronDepois = await linhas('cron.job_run_details');
    conferir(r.codigo === 0 && cronDepois === esperado,
      `10 apaga só o que passou da retenção (${cronAntes} -> ${cronDepois})`);

    // 11 sem MAINTAIN: o PostgreSQL pula a tabela com aviso; o executor pega.
    r = passo('11_log_do_cron_compactar.sql', '--executar');
    conferir(r.codigo === 1 && /não encolheu/.test(r.saida),
      '11 sem MAINTAIN falha pela checagem de encolhimento, não em silêncio');

    // 11 com MAINTAIN, como em produção.
    await admin.query('grant maintain on cron.job_run_details to operador');
    const cronTamanho = await tamanho('cron.job_run_details');
    r = passo('11_log_do_cron_compactar.sql', '--executar');
    conferir(r.codigo === 0 && await tamanho('cron.job_run_details') < cronTamanho
      && await linhas('cron.job_run_details') === cronDepois,
      '11 com MAINTAIN devolve espaço e não perde linha');

    // 12 vem desarmado.
    r = passo('12_log_do_cron_truncate_ALTERNATIVA.sql', '--executar');
    conferir(r.codigo === 1 && /desarmada/.test(r.saida)
      && await linhas('cron.job_run_details') === cronDepois,
      '12 (TRUNCATE) recusa sempre até ser armado à mão');

    // Pré-condição do motor.
    await admin.query("insert into public.motor_execucoes (status) values ('running')");
    const serieAntes = await tamanho('public.series_semanais');
    r = passo('50_vacuum_full_series_semanais.sql', '--executar');
    conferir(r.codigo === 1 && /motor em andamento/.test(r.saida)
      && await tamanho('public.series_semanais') === serieAntes,
      '50 aborta com o motor rodando, antes da ação');
    await admin.query("update public.motor_execucoes set status = 'success'");

    // Pré-condição de lock: outra sessão lendo a tabela numa transação aberta.
    const leitor = await conectar('lab');
    await leitor.query('begin');
    await leitor.query('select count(*) from public.series_semanais');
    r = passo('50_vacuum_full_series_semanais.sql', '--executar');
    conferir(r.codigo === 1 && /outra sessao segura lock/.test(r.saida)
      && await tamanho('public.series_semanais') === serieAntes,
      '50 aborta com outra sessão segurando lock, antes da ação');
    await leitor.query('rollback');
    await leitor.end();

    // As ações de verdade: cada alvo encolhe e nenhuma linha some.
    const casos = [
      ['20_reindex_estado_produtos_oferta_recente.sql', 'public.estado_produtos_oferta_recente', 'public.estado_dos_produtos'],
      ['21_reindex_estado_dos_produtos_pkey.sql', 'public.estado_dos_produtos_pkey', 'public.estado_dos_produtos'],
      ['30_vacuum_full_indices_semanais.sql', 'public.indices_semanais', 'public.indices_semanais'],
      ['50_vacuum_full_series_semanais.sql', 'public.series_semanais', 'public.series_semanais'],
    ];
    const snapshots = await linhas('public.snapshots');
    for (const [arquivo, alvo, tabela] of casos) {
      const ensaio = passo(arquivo);
      const antes = await tamanho(alvo);
      const n = await linhas(tabela);
      conferir(ensaio.codigo === 0 && /ENSAIO/.test(ensaio.saida)
        && await tamanho(alvo) === antes, `${arquivo.slice(0, 2)} em ensaio não mexe no alvo`);
      r = passo(arquivo, '--executar');
      const depois = await tamanho(alvo);
      conferir(r.codigo === 0 && depois < antes && await linhas(tabela) === n,
        `${arquivo.slice(0, 2)} encolhe ${alvo} (${antes} -> ${depois}) sem perder linha`);
    }

    conferir(await linhas('public.snapshots') === snapshots,
      'nenhum passo físico tocou nos snapshots que a A58 precisa');

    // GRAFO 40/60. `--definir` só funciona no socket local e permite testar
    // os três ramos sem fabricar 400 MB de lixo.
    const reinchar = async () => {
      await op.query(`insert into public.artigos (url, titulo)
        select 'https://exemplo.invalid/reinchaco/' || n || '/' || md5(random()::text), 't'
        from generate_series(1, 20000) n`);
      await op.query("delete from public.artigos where url like '%/reinchaco/%'");
      await op.query('vacuum public.artigos');
    };
    const estimativa = async () => {
      const { rows: [e] } = await admin.query(`select
        (select sum(pg_database_size(oid)) from pg_database)::bigint as cota,
        pg_relation_size('public.artigos_url_key')::bigint as url_atual,
        (select round(sum(((8 + pg_column_size(url) + 7) / 8) * 8 + 4) / 0.90 * 1.01)
           from public.artigos)::bigint as url_recem`);
      return { cota: Number(e.cota), ganho40: Number(e.url_atual) - Number(e.url_recem) };
    };
    const comTeto = (arquivo, teto, ...extra) =>
      passo(arquivo, '--definir', `datadrobe.teto_bytes=${teto}`, ...extra);

    await reinchar();
    let e = await estimativa();
    conferir(e.ganho40 > 0, `índice de URL inchado para o teste (${e.ganho40} bytes)`);
    let urlAntes = await tamanhoRelacao('public.artigos_url_key');
    r = comTeto('55_decide_40_ou_60.sql', e.cota + 1_000_000);
    conferir(r.codigo === 0 && /DECISAO 40\/60: NENHUM/.test(r.saida),
      '55 decide NENHUM com a cota dentro do teto');
    const r40n = comTeto('40_reindex_artigos_url_key.sql', e.cota + 1_000_000, '--executar');
    const r60n = comTeto('60_vacuum_full_artigos_CONDICIONAL.sql', e.cota + 1_000_000, '--executar');
    conferir(r40n.codigo === 1 && r60n.codigo === 1
      && await tamanhoRelacao('public.artigos_url_key') === urlAntes,
      'ramo NENHUM: 40 e 60 recusam, nada muda');

    let teto = e.cota - Math.floor(e.ganho40 / 2);
    r = comTeto('55_decide_40_ou_60.sql', teto);
    conferir(r.codigo === 0 && /DECISAO 40\/60: PASSO 40/.test(r.saida),
      '55 decide 40 quando o reindex basta');
    const r60antes = comTeto('60_vacuum_full_artigos_CONDICIONAL.sql', teto, '--executar');
    conferir(r60antes.codigo === 1 && /o 40 sozinho basta/.test(r60antes.saida),
      'ramo 40: o 60 recusa antes do 40');
    const artigosLinhas = await linhas('public.artigos');
    r = comTeto('40_reindex_artigos_url_key.sql', teto, '--executar');
    conferir(r.codigo === 0 && await tamanhoRelacao('public.artigos_url_key') < urlAntes
      && await linhas('public.artigos') === artigosLinhas,
      'ramo 40: encolhe o índice e não perde linha');
    const totalDepois40 = await tamanho('public.artigos');
    r = comTeto('60_vacuum_full_artigos_CONDICIONAL.sql', 1, '--executar');
    conferir(r.codigo === 1 && /ja foi reconstruido/.test(r.saida)
      && await tamanho('public.artigos') === totalDepois40,
      'ramo 40: depois do 40, o 60 recusa');

    await reinchar();
    e = await estimativa();
    urlAntes = await tamanhoRelacao('public.artigos_url_key');
    teto = e.cota - e.ganho40 - 1_000_000;
    r = comTeto('55_decide_40_ou_60.sql', teto);
    conferir(r.codigo === 0 && /DECISAO 40\/60: PASSO 60/.test(r.saida),
      '55 decide 60 quando o reindex não basta');
    const r40antes = comTeto('40_reindex_artigos_url_key.sql', teto, '--executar');
    conferir(r40antes.codigo === 1 && /o 40 sozinho nao basta/.test(r40antes.saida),
      'ramo 60: o 40 recusa antes do 60');
    const totalAntes60 = await tamanho('public.artigos');
    r = comTeto('60_vacuum_full_artigos_CONDICIONAL.sql', teto, '--executar');
    conferir(r.codigo === 0 && await tamanho('public.artigos') < totalAntes60
      && await tamanhoRelacao('public.artigos_url_key') < urlAntes
      && await linhas('public.artigos') === artigosLinhas,
      'ramo 60: reescreve heap e índices uma vez, sem perder linha');
    const urlDepois60 = await tamanhoRelacao('public.artigos_url_key');
    const r40depois = comTeto('40_reindex_artigos_url_key.sql', 1, '--executar');
    conferir(r40depois.codigo === 1
      && await tamanhoRelacao('public.artigos_url_key') === urlDepois60,
      'ramo 60: depois do 60, o 40 recusa');

    const texto60 = await readFile(path.join(AQUI,
      '60_vacuum_full_artigos_CONDICIONAL.sql'), 'utf8');
    conferir(/estimado \* 1\.15/.test(texto60),
      '60 preserva o portão adicional de ganho material mínimo de 15%');
    conferir(await linhas('public.snapshots') === snapshots,
      'nenhum ramo 40/60 tocou nos snapshots que a A58 precisa');

    // 80: com as funções de produção carregadas, confere; com uma diferente,
    // aborta; com uma faltando, aborta.
    const arquivos = (await readdir(MIGRATIONS)).filter(a => a.endsWith('.sql')
      && a < '20260917200000').sort().reverse();
    const carregar = async (nome) => {
      if (nome === 'computar_indice') {
        const texto = await readFile(path.join(REPOSITORIO,
          'ferramentas/laboratorio_capacidade/producao/computar_indice.sql'), 'utf8');
        const i = texto.indexOf('create or replace function public.computar_indice(');
        const f = texto.indexOf('$function$;', texto.indexOf('$function$', i) + 10);
        await op.query(texto.slice(i, f + '$function$;'.length));
        return;
      }
      for (const a of arquivos) {
        const texto = await readFile(path.join(MIGRATIONS, a), 'utf8');
        const i = texto.toLowerCase().lastIndexOf(`create or replace function public.${nome}(`);
        if (i < 0) continue;
        const f = texto.indexOf('$function$;', texto.indexOf('$function$', i) + 10);
        await op.query(texto.slice(i, f + '$function$;'.length));
        return;
      }
    };
    await op.query('create table public.denominador_editorial (fonte text, semana date, total_janela_4sem numeric)');
    for (const nome of ['computar_serie_varejo', 'computar_serie_editorial',
      'computar_z', 'computar_indice', 'uso_do_banco']) await carregar(nome);
    r = passo('80_confere_antes_das_migrations.sql');
    conferir(r.codigo === 1 && /funcao ausente: public\.podar_snapshots/.test(r.saida),
      '80 aborta com uma função faltando');
    await carregar('podar_snapshots');
    r = passo('80_confere_antes_das_migrations.sql');
    conferir(r.codigo === 0 && /medidas em 18\/09/.test(r.saida),
      '80 passa com as seis funções idênticas às capturadas em produção');
    await op.query(`create or replace function public.computar_z() returns integer
      language sql as 'select 0'`);
    r = passo('80_confere_antes_das_migrations.sql');
    conferir(r.codigo === 1 && /computar_z\(\) mudou desde 18\/09/.test(r.saida),
      '80 aborta quando uma função diverge da medida');
    await carregar('computar_z');

    // O executor aplica uma migration e seu ledger na mesma transação.
    const mig = (arquivo, ...extra) => {
      const x = spawnSync(process.execPath, [path.join(AQUI, 'passo.mjs'),
        '--migracao', path.join(MIGRATIONS, arquivo), '--socket', sock,
        '--usuario', 'operador', '--senha-vazia', '--modulos', MODULOS, ...extra],
      { encoding: 'utf8' });
      return { codigo: x.status, saida: `${x.stdout}${x.stderr}` };
    };
    const ledger = async () => (await admin.query(
      'select version from supabase_migrations.schema_migrations order by 1')).rows
      .map(x => x.version);

    // P23 depende de pg_cron real: sem a extensão, falha fechada e não deixa
    // migration parcialmente aplicada nem versão órfã no ledger.
    r = passo('13_confere_p23_antes.sql');
    conferir(r.codigo === 1 && /pg_cron nao esta instalado/.test(r.saida),
      '13 recusa quando pg_cron não existe no laboratório');
    r = mig('20260917202000_p23_retencao_do_log_do_cron.sql', '--executar');
    conferir(r.codigo === 1 && /desfeita inteira/.test(r.saida)
      && /requer a extensao pg_cron/.test(r.saida) && (await ledger()).length === 0,
      'P23 falha fechada sem pg_cron e não grava ledger');

    r = mig('20260917201000_p22_series_sem_reescrita_identica.sql');
    conferir(r.codigo === 0 && /ENSAIO/.test(r.saida) && (await ledger()).length === 0,
      'migration em ensaio não aplica nem registra');

    for (const m of ['20260917200000_p21_uso_do_banco_mede_a_cota.sql',
      '20260917201000_p22_series_sem_reescrita_identica.sql',
      '20260917203000_p24_poda_espera_o_denominador.sql',
      '20260917204000_p25_indices_sem_reescrita_identica.sql']) {
      r = mig(m, '--executar');
      conferir(r.codigo === 0 && /registrada como/.test(r.saida),
        `${m.slice(15, 18)} aplicada e registrada`);
    }
    conferir(JSON.stringify(await ledger()) === JSON.stringify(
      ['20260917200000', '20260917201000', '20260917203000', '20260917204000']),
      'ledger tem exatamente as quatro migrations aplicáveis no laboratório');
    r = mig('20260917201000_p22_series_sem_reescrita_identica.sql', '--executar');
    conferir(r.codigo === 1 && /já está no ledger/.test(r.saida),
      'reaplicar migration é recusado pelo ledger');

    // 90 roda depois da A58 em produção; a relação mínima preserva o mesmo
    // chão para este ensaio do executor.
    await op.query('create table public.sortimento_diario (data date)');
    r = passo('90_observacao.sql');
    conferir(r.codigo === 0 && /cota_bytes/.test(r.saida), '90 mede em leitura');

    // Pós-poda: ensaio LOCAL da hipótese medida em 19/09. Não acrescenta
    // manutenção ao executor de produção nem muda retenção. As remoções
    // abaixo fabricam espaço vazio só neste cluster descartável.
    await op.query(`alter table public.snapshots
      add column preco_atual numeric(10,2), add column composicao text,
      add column grade_por_tamanho jsonb;
      insert into public.snapshots
        (produto_id, data, ofertavel, preco_atual, composicao, grade_por_tamanho)
      select 10000+n, current_date, true, 99.90, repeat('algodao ',12),
             '{"P":true,"M":false,"G":true}'::jsonb
      from generate_series(1,90000) n;
      delete from public.snapshots where produto_id>10000 and produto_id%3<>0;`);
    await op.query('vacuum public.snapshots');
    const assinaturaSnapshots = async () => (await op.query(`select
      count(*)::int as linhas,
      md5(string_agg(to_jsonb(s)::text, E'\\n' order by id)) as conteudo
      from public.snapshots s`)).rows[0];
    const antesCompactacao = await assinaturaSnapshots();
    const bytesAntesCompactacao = await tamanho('public.snapshots');
    await op.query('vacuum full public.snapshots');
    const depoisCompactacao = await assinaturaSnapshots();
    const bytesDepoisCompactacao = await tamanho('public.snapshots');
    conferir(JSON.stringify(antesCompactacao) === JSON.stringify(depoisCompactacao),
      'snapshots pós-poda: compactação local preserva contagem e hash de todas as linhas');
    conferir(bytesDepoisCompactacao < bytesAntesCompactacao,
      `snapshots pós-poda: espaço físico ${bytesAntesCompactacao} -> ${bytesDepoisCompactacao} bytes`);
    const indicesSnapshots = (await op.query(`select count(*)::int as n,
      bool_and(indisvalid and indisready) as validos from pg_index
      where indrelid='public.snapshots'::regclass`)).rows[0];
    conferir(indicesSnapshots.n === 2 && indicesSnapshots.validos,
      'snapshots pós-poda: os dois índices permanecem válidos');

    // A porta do pooler de transação é recusada antes de conectar.
    const recusa = spawnSync(process.execPath, [path.join(AQUI, 'passo.mjs'),
      path.join(AQUI, '90_observacao.sql'), '--host', 'exemplo.invalid',
      '--porta', '6543', '--usuario', 'x', '--senha-vazia'], { encoding: 'utf8' });
    conferir(recusa.status === 1 && /pooler de transação/.test(recusa.stderr),
      'a porta 6543 é recusada');

    await op.end();
  } finally {
    await admin.end().catch(() => {});
    spawnSync(b.pg_ctl, ['stop', '-D', dados, '-m', 'fast', '-w'], { env: AMBIENTE });
    if (servidor.exitCode === null) await once(servidor, 'exit').catch(() => {});
    await rm(raiz, { recursive: true, force: true });
  }
  if (falhas) throw new Error(`${falhas} verificação(ões) falharam`);
  console.log('ROTEIRO VERDE');
}

main().catch(e => { console.error(`FALHOU: ${e.message}`); process.exit(1); });
