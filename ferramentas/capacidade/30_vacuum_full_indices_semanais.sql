-- PASSO 30 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo public.indices_semanais
--
-- Alvo exato: a tabela `public.indices_semanais`, o TOAST dela e os indices dela.
--
-- O que faz: reescreve a tabela so com as linhas vivas, no fillfactor dela
-- (70), e reconstroi os indices. Nenhuma linha e apagada ou alterada.
-- Medido em 18/09: heap de 17,17 MB com 7,26 MB de dado vivo. Reescrito:
-- ~10,6 MB (inventario, consulta 3). Indices: 1,5 MB hoje. Ganho estimado total: ~7,5 MB.
-- `indices_semanais` tinha o mesmo padrao de reescrita da `series_semanais`
-- (610.443 updates em 9.897 linhas desde 15/07). A P25 corrige a causa: sem
-- ela, este ganho seria temporario e nao poderia contar como folga. A P25 entra
-- depois do passo 70 e antes da retomada; com os workflows desativados, nada
-- reescreve a tabela entre a compactacao e a prevencao.
--
-- Lock: ACCESS EXCLUSIVE durante toda a reescrita -- ninguem le nem escreve
-- na tabela ate o fim. Duracao esperada: 2 a 8 s. `statement_timeout` de 180 s
-- e o teto; se estourar, a transacao desfaz tudo e a tabela fica como estava.
-- Espaco temporario: a copia nova e os indices novos, ~12 MB, existem
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
              where l.relation = 'public.indices_semanais'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em public.indices_semanais';
  end if;
end $$;

-- PRE: disco. Cota + WAL + 2 x o espaco novo (a copia e o WAL dela) cabe em
-- 900 MB -- 90% do disco de 1 GB do plano Free. A copia nova existe junto
-- com a velha ate o commit.
do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  wal bigint := (select coalesce(sum(size), 0) from pg_ls_waldir());
  novo bigint := 12000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
vacuum full public.indices_semanais;
