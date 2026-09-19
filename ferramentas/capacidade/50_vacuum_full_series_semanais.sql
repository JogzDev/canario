-- PASSO 50 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo public.series_semanais
--
-- Alvo exato: a tabela `public.series_semanais`, o TOAST dela e os indices dela.
--
-- O que faz: reescreve a tabela so com as linhas vivas, no fillfactor dela
-- (70), e reconstroi os indices. Nenhuma linha e apagada ou alterada.
-- Medido em 18/09: heap de 73,83 MB com 22,62 MB de dado vivo. Reescrito:
-- ~33,0 MB (inventario, consulta 3). Indices: 5,2 MB hoje, ~2,7 MB reconstruidos. Ganho estimado total: ~43 MB. A P9 fez o mesmo em 18/08 (48,2 -> 26,6 MiB com 25.676 linhas); hoje sao 29.047.
-- Sem a P22 aplicada ANTES da proxima publicacao do motor, este ganho e
-- comido em dias: cada publicacao reescrevia ate ~46,7 mil linhas.
--
-- Lock: ACCESS EXCLUSIVE durante toda a reescrita -- ninguem le nem escreve
-- na tabela ate o fim. Duracao esperada: 5 a 20 s. `statement_timeout` de 180 s
-- e o teto; se estourar, a transacao desfaz tudo e a tabela fica como estava.
-- Espaco temporario: a copia nova e os indices novos, ~40 MB, existem
-- junto com os velhos ate o commit.
--
-- Abortar se: o executor acusar lock ou tempo; o tamanho nao cair.

-- PRE: nenhuma publicacao do motor em andamento. A coleta esta parada; se
-- alguem disparou o motor na mao, o passo espera.
do $$ begin
  if exists (select 1 from public.motor_execucoes
              where status in ('queued', 'running')) then
    raise exception 'ABORTAR: publicacao do motor em andamento';
  end if;
end $$;

-- PRE: nenhuma outra sessao segura lock na tabela. Com lock_timeout de 5 s a
-- acao nao ficaria presa, mas entrar na fila ja atrasaria quem le.
do $$ begin
  if exists (select 1 from pg_locks l
              where l.relation = 'public.series_semanais'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em public.series_semanais';
  end if;
end $$;

-- PRE: disco. Cota + WAL + 2 x o espaco novo (a copia e o WAL dela) cabe em
-- 900 MB -- 90% do disco de 1 GB do plano Free. A copia nova existe junto
-- com a velha ate o commit.
do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  wal bigint := (select coalesce(sum(size), 0) from pg_ls_waldir());
  novo bigint := 40000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
vacuum full public.series_semanais;
