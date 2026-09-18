-- PASSO 11 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo cron.job_run_details
--
-- Alvo exato: a tabela `cron.job_run_details` e o indice dela.
--
-- O que faz: reescreve a tabela so com as linhas que o passo 10 manteve e
-- devolve o resto ao sistema de arquivos. Ganho estimado: 16,67 MB -> ~2,5 MB
-- (uma semana de dispatcher), ~14 MB. A estimativa vem de 1.440 linhas/dia x
-- 7 dias x ~250 bytes por linha (16.670.720 / 65.811).
--
-- Permissao: o dono e supabase_admin, mas o PostgreSQL 17 aceita VACUUM de
-- quem tem MAINTAIN, e o papel postgres tem (medido em 18/09). Sem MAINTAIN o
-- PostgreSQL PULA a tabela com um aviso, sem erro -- por isso o executor
-- compara o tamanho antes e depois.
--
-- Lock: ACCESS EXCLUSIVE durante a reescrita. O pg_cron grava uma linha por
-- minuto aqui; ela espera ~1 s. Duracao esperada: 1 a 3 s.
-- Espaco temporario: a copia nova, ~3 MB.
--
-- Abortar se: o passo 10 nao rodou (a pre-condicao abaixo confere), ou o
-- tamanho nao cair depois (MAINTAIN ausente -- ver saida do executor).

-- PRE: nenhuma outra sessao segura lock na tabela. Com lock_timeout de 5 s a
-- acao nao ficaria presa, mas entrar na fila ja atrasaria quem le.
do $$ begin
  if exists (select 1 from pg_locks l
              where l.relation = 'cron.job_run_details'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em cron.job_run_details';
  end if;
end $$;

-- PRE: o passo 10 ja rodou. Compactar sem apagar antes nao devolve nada.
do $$ begin
  if exists (select 1 from cron.job_run_details
              where (end_time < now() - interval '7 days' and status = 'succeeded')
                 or end_time < now() - interval '30 days') then
    raise exception 'ABORTAR: rode o passo 10 antes';
  end if;
end $$;

-- PRE: disco. Cota + WAL + 2 x o espaco novo (a copia e o WAL dela) cabe em
-- 900 MB -- 90% do disco de 1 GB do plano Free. A copia nova existe junto
-- com a velha ate o commit.
do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  wal bigint := (select coalesce(sum(size), 0) from pg_ls_waldir());
  novo bigint := 3000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
vacuum full cron.job_run_details;
