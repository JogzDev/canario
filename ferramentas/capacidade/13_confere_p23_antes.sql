-- PASSO 13 · SO LEITURA. Preflight específico da P23, logo após o passo 11.
-- A migration repete estas travas dentro da própria transação; este passo
-- existe para mostrar o estado antes e interromper o roteiro com diagnóstico.

do $$
declare
  job regclass := to_regclass('cron.job');
  detalhes regclass := to_regclass('cron.job_run_details');
  colunas integer;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'ABORTAR: pg_cron nao esta instalado';
  end if;
  if current_user <> 'postgres'
     or not coalesce((select rolcanlogin and (rolsuper or rolbypassrls)
                      from pg_roles where rolname = current_user), false) then
    raise exception 'ABORTAR: exige postgres com LOGIN e visibilidade global do cron';
  end if;
  if job is null or detalhes is null then
    raise exception 'ABORTAR: cron.job ou cron.job_run_details ausente';
  end if;
  select count(*) into colunas from pg_attribute
   where attrelid = job and not attisdropped
     and attname::text = any(array['jobid','jobname','schedule','command','database','username','active']);
  if colunas <> 7 then raise exception 'ABORTAR: contrato de cron.job divergiu'; end if;
  select count(*) into colunas from pg_attribute
   where attrelid = detalhes and not attisdropped
     and attname::text = any(array['end_time','status']);
  if colunas <> 2 then raise exception 'ABORTAR: contrato de cron.job_run_details divergiu'; end if;
  if to_regprocedure('cron.schedule(text,text,text)') is null
     or to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null then
    raise exception 'ABORTAR: assinaturas do pg_cron divergiram';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = job and contype = 'u'
                    and conname = 'jobname_username_uniq') then
    raise exception 'ABORTAR: unicidade de job por nome e usuario ausente';
  end if;
  if not has_schema_privilege('postgres', 'cron', 'usage')
     or not has_function_privilege('postgres', 'cron.schedule(text,text,text)', 'execute')
     or not has_function_privilege('postgres', 'cron.alter_job(bigint,text,text,text,text,boolean)', 'execute')
     or not has_table_privilege('postgres', 'cron.job', 'select')
     or not has_table_privilege('postgres', 'cron.job_run_details', 'select')
     or not has_table_privilege('postgres', 'cron.job_run_details', 'delete') then
    raise exception 'ABORTAR: privilegios exigidos pela P23 ausentes';
  end if;
  if exists (select 1 from cron.job
              where jobname = 'canario-retencao-do-log-do-cron'
                and username <> 'postgres') then
    raise exception 'ABORTAR: job homonimo pertence a outro papel';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
              where version = '20260917202000') then
    raise exception 'ABORTAR: P23 ja consta no ledger';
  end if;
  raise notice 'P23 pronta: extensao, contratos, papel, privilegios e nome conferidos';
end $$;

select jobid, jobname, schedule, database, username, active
from cron.job
where jobname = 'canario-retencao-do-log-do-cron';
