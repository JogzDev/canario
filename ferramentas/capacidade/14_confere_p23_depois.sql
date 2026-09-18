-- PASSO 14 · SO LEITURA. Pós-condição imediata da P23.

do $$
declare
  total integer;
  exatos integer;
  esperado constant text := 'delete from cron.job_run_details where end_time < now() - interval ''7 days'' and status = ''succeeded''; delete from cron.job_run_details where end_time < now() - interval ''30 days'';';
begin
  select count(*) into total from cron.job
   where jobname = 'canario-retencao-do-log-do-cron';
  select count(*) into exatos from cron.job
   where jobname = 'canario-retencao-do-log-do-cron'
     and schedule = '17 4 * * *' and active
     and username = 'postgres' and database = current_database()
     and btrim(regexp_replace(command, '\s+', ' ', 'g')) = esperado;
  if total <> 1 or exatos <> 1 then
    raise exception 'ABORTAR: job P23 divergiu (total %, exatos %)', total, exatos;
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'canario-motor-dispatcher' and active) then
    raise exception 'ABORTAR: dispatcher do motor sumiu ou foi desativado';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations
                  where version = '20260917202000') then
    raise exception 'ABORTAR: P23 nao consta no ledger';
  end if;
  raise notice 'P23 conferida: um job exato, ativo, no ledger; dispatcher intacto';
end $$;
