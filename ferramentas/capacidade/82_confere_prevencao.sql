-- PASSO 82 · SO LEITURA. Depois de P21, P22, P23, P24 e P25.

do $$
declare
  e record;
  oid regprocedure;
  obtido text;
begin
  for e in select * from (values
    ('public.uso_do_banco()', 'f43c92f16ab1b3be15fda0ee511a7932'),
    ('public.computar_serie_varejo()', '3b25ccaf63e5ca43755a05af79ee7b3c'),
    ('public.computar_serie_editorial()', '9d9232927a3b38bcf1c6dc85896f1cc4'),
    ('public.computar_z()', '679f9c15255a939942e7240f46216f87'),
    ('public.podar_snapshots(integer)', 'ecb5b467106ad7657bea380056a4bbc2'),
    ('public.computar_indice()', 'f5a3bd9e528f333242d1877dd8666176')
  ) as x(assinatura, hash)
  loop
    oid := to_regprocedure(e.assinatura);
    if oid is null then raise exception 'ABORTAR: funcao ausente: %', e.assinatura; end if;
    select md5(regexp_replace(pg_get_functiondef(oid), '\s+', ' ', 'g')) into obtido;
    if obtido <> e.hash then
      raise exception 'ABORTAR: % tem hash %, esperado %', e.assinatura, obtido, e.hash;
    end if;
  end loop;
  raise notice 'prevencao: as seis funcoes batem por assinatura e hash';
end $$;

do $$
declare
  n integer;
  exatos integer;
  esperado constant text := 'delete from cron.job_run_details where end_time < now() - interval ''7 days'' and status = ''succeeded''; delete from cron.job_run_details where end_time < now() - interval ''30 days'';';
begin
  select count(*) into n from cron.job
   where jobname = 'canario-retencao-do-log-do-cron';
  select count(*) into exatos from cron.job
   where jobname = 'canario-retencao-do-log-do-cron'
     and schedule = '17 4 * * *' and active
     and username = 'postgres' and database = current_database()
     and btrim(regexp_replace(command, '\s+', ' ', 'g')) = esperado;
  if n <> 1 or exatos <> 1 then
    raise exception 'ABORTAR: job P23 divergiu (total %, exatos %)', n, exatos;
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'canario-motor-dispatcher' and active) then
    raise exception 'ABORTAR: dispatcher do motor sumiu ou foi desativado';
  end if;
end $$;

do $$
declare n integer;
begin
  select count(*) into n from supabase_migrations.schema_migrations
   where version in ('20260917200000','20260917201000','20260917202000',
                     '20260917203000','20260917204000');
  if n <> 5 then raise exception 'ABORTAR: esperava 5 versoes no ledger e ha %', n; end if;
end $$;

do $$
declare u jsonb := public.uso_do_banco();
begin
  if (u->>'bytes_da_cota')::bigint <> (select sum(pg_database_size(oid)) from pg_database)
     or (u->>'banco_principal_bytes')::bigint + (u->>'overhead_interno_bytes')::bigint
        <> (u->>'bytes_da_cota')::bigint then
    raise exception 'ABORTAR: uso_do_banco nao fecha: %', u;
  end if;
end $$;
