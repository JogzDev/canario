-- P23: o log do pg_cron deixa de crescer para sempre.
--
-- POR QUE
-- =======
--
-- `canario-motor-dispatcher` roda a cada minuto (P0, 03/08/2026) e cada
-- execucao grava uma linha em `cron.job_run_details`. Nada apaga essas linhas.
-- Medido em 18/09/2026, em leitura:
--
--   65.811 linhas, de 03/08 a 18/09     16.670.720 bytes
--   1.440 linhas por dia                 ~360 KB por dia
--
-- E o crescimento que continua com a coleta PARADA. Entre 02:33 e 12:37 UTC
-- de 18/09 o banco principal cresceu 180.224 bytes -- ~430 KB por dia no
-- mesmo ritmo, compativel com os ~360 KB/dia deste log somados ao que o
-- autovacuum e as estatisticas escrevem.
--
-- Nada no projeto le esse log -- o estado das publicacoes vive em
-- `motor_execucoes` (conferido em supabase/migrations, coletor/, ferramentas/ e
-- .github/ em 18/09). Ele e diagnostico do pg_cron, e diagnostico de mais de
-- uma semana nao responde pergunta nenhuma que `motor_execucoes` nao responda.
--
-- O QUE ESTE JOB FAZ
-- ==================
--
-- Uma vez por dia, as 04:17 UTC -- fora da janela do pipeline, que comeca as
-- 06:00 UTC --, apaga:
--
--   execucoes bem-sucedidas com mais de 7 dias
--   qualquer execucao com mais de 30 dias
--
-- Falha fica quatro vezes mais tempo porque e a que alguem vai querer ler.
-- Execucao em andamento tem `end_time` nulo e nunca e apagada.
--
-- Regime esperado: ~10 mil linhas, ~2,5 MB.
--
-- O QUE ESTE JOB NAO FAZ
-- ======================
--
-- `delete` nao devolve espaco fisico: ele libera paginas para a propria tabela
-- reusar. Os 16,7 MB que ja existem so voltam com uma acao fisica unica
-- (TRUNCATE ou VACUUM FULL da tabela), que esta no roteiro da etapa 1 com
-- escopo, lock e consequencia -- e nao aqui. Esta migration e so a prevencao:
-- sem ela, qualquer limpeza volta a crescer ~11 MB por mes.
--
-- `cron.schedule` com nome faz upsert pela dupla (jobname, username), nao pelo
-- nome global. Por isso esta migration exige o papel canonico `postgres`, com
-- BYPASSRLS, e recusa um homonimo pertencente a outro papel: sem isso dois
-- jobs poderiam executar a mesma retencao. O pg_cron tambem nao reativa no
-- upsert um job que alguem tenha desativado; a migration chama alter_job e
-- confere o catalogo inteiro depois. Tudo acontece no mesmo DO; qualquer
-- precondicao ou pos-condicao que falhe desfaz o agendamento.

do $migration$
declare
  v_nome constant text := 'canario-retencao-do-log-do-cron';
  v_agenda constant text := '17 4 * * *';
  v_comando constant text := $comando$delete from cron.job_run_details
     where end_time < now() - interval '7 days'
       and status = 'succeeded';
    delete from cron.job_run_details
     where end_time < now() - interval '30 days';$comando$;
  v_banco constant text := current_database();
  v_usuario constant text := 'postgres';
  v_jobid bigint;
  v_total integer;
  v_exatos integer;
  v_outros integer;
  v_colunas integer;
  v_job regclass;
  v_detalhes regclass;
begin
  -- Falhar aqui e melhor do que aceitar uma migration "verde" que nao
  -- instalou prevencao nenhuma. A assinatura text,text,text existe desde o
  -- pg_cron 1.4, e alter_job e necessario para tornar a reaplicacao tambem
  -- idempotente quando o job existente estiver inativo.
  if not exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    raise exception 'P23 requer a extensao pg_cron';
  end if;

  if current_user <> v_usuario then
    raise exception
      'P23 deve ser aplicada pelo papel canonico postgres; papel atual: %',
      current_user;
  end if;

  v_job := pg_catalog.to_regclass('cron.job');
  v_detalhes := pg_catalog.to_regclass('cron.job_run_details');
  if v_job is null or v_detalhes is null then
    raise exception 'P23 requer cron.job e cron.job_run_details';
  end if;

  select count(*) into v_colunas
  from pg_catalog.pg_attribute a
  where a.attrelid = v_job
    and not a.attisdropped
    and a.attname::text = any (array[
      'jobid', 'jobname', 'schedule', 'command',
      'database', 'username', 'active'
    ]);
  if v_colunas <> 7 then
    raise exception 'P23: cron.job nao tem o contrato de sete colunas esperado';
  end if;

  select count(*) into v_colunas
  from pg_catalog.pg_attribute a
  where a.attrelid = v_detalhes
    and not a.attisdropped
    and a.attname::text = any (array['end_time', 'status']);
  if v_colunas <> 2 then
    raise exception
      'P23: cron.job_run_details nao tem end_time e status';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = v_job
      and c.contype = 'u'
      and c.conname = 'jobname_username_uniq'
  ) then
    raise exception 'P23 requer unicidade de cron.job por nome e usuario';
  end if;

  if pg_catalog.to_regprocedure('cron.schedule(text,text,text)') is null
     or pg_catalog.to_regprocedure(
       'cron.alter_job(bigint,text,text,text,text,boolean)') is null then
    raise exception 'P23 requer cron.schedule nomeado e cron.alter_job';
  end if;

  if not pg_catalog.has_schema_privilege(v_usuario, 'cron', 'usage')
     or not pg_catalog.has_function_privilege(
       v_usuario, 'cron.schedule(text,text,text)', 'execute')
     or not pg_catalog.has_function_privilege(
       v_usuario,
       'cron.alter_job(bigint,text,text,text,text,boolean)', 'execute')
     or not pg_catalog.has_table_privilege(
       v_usuario, 'cron.job', 'select')
     or not pg_catalog.has_table_privilege(
       v_usuario, 'cron.job_run_details', 'select')
     or not pg_catalog.has_table_privilege(
       v_usuario, 'cron.job_run_details', 'delete') then
    raise exception
      'P23 requer USAGE em cron, EXECUTE nas funcoes e SELECT/DELETE nos catalogos';
  end if;

  if not coalesce((
    select r.rolcanlogin and (r.rolsuper or r.rolbypassrls)
    from pg_catalog.pg_roles r
    where r.rolname = v_usuario
  ), false) then
    raise exception
      'P23 requer papel canonico com LOGIN e visibilidade global do cron: %',
      v_usuario;
  end if;

  -- A constraint do pg_cron so protege (nome, usuario). Como `postgres`
  -- ignora a RLS de cron.job, esta conta tambem enxerga jobs de outros papeis.
  select count(*) into v_outros
  from cron.job j
  where j.jobname::text = v_nome
    and j.username <> v_usuario;
  if v_outros <> 0 then
    raise exception
      'P23: existe(m) % job(s) homonimo(s) pertencente(s) a outro papel',
      v_outros;
  end if;

  -- A funcao nomeada atualiza agenda, comando e banco do job deste usuario.
  -- `alter_job` cobre a unica coluna que o upsert do pg_cron nao reativa.
  v_jobid := cron.schedule(v_nome, v_agenda, v_comando);
  if v_jobid is null then
    raise exception 'P23: cron.schedule nao devolveu jobid';
  end if;
  perform cron.alter_job(v_jobid, active => true);

  -- A primeira conta prova a cardinalidade; a segunda prova o contrato
  -- inteiro. Se qualquer detalhe divergir, o erro reverte schedule/alter_job.
  select count(*) into v_total
  from cron.job j
  where j.jobname::text = v_nome;

  select count(*) into v_exatos
  from cron.job j
  where j.jobid = v_jobid
    and j.jobname::text = v_nome
    and j.schedule = v_agenda
    and j.command = v_comando
    and j.database = v_banco
    and j.username = v_usuario
    and j.active is true;

  if v_total <> 1 or v_exatos <> 1 then
    raise exception
      'P23: pos-condicao falhou (jobs do usuario %, exatos %)',
      v_total, v_exatos;
  end if;
end;
$migration$;
