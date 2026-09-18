-- PASSO 60 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo public.artigos
--
-- Alvo exato: a tabela `public.artigos`, o TOAST dela e os indices dela.
--
-- O que faz: reescreve a tabela so com as linhas vivas, no fillfactor dela
-- (100), e reconstroi os indices. Nenhuma linha e apagada ou alterada.
-- Medido em 18/09: heap de 55,93 MB com 43,09 MB de dado vivo. Reescrito:
-- ~44,0 MB (inventario, consulta 3). Indices: `artigos_url_key` ja reconstruido no passo 40; `artigos_pkey` cai de 7,7 para ~3,9 MB. Ganho estimado total: ~15,8 MB.
-- CONDICIONAL: so roda se a folga ainda estiver abaixo de 20% depois do
-- passo 50 (a primeira pre-condicao confere). E o passo de maior espaco
-- temporario (~70 MB) e o de menor razao ganho/custo, por isso e o ultimo.
--
-- Lock: ACCESS EXCLUSIVE durante toda a reescrita -- ninguem le nem escreve
-- na tabela ate o fim. Duracao esperada: 10 a 40 s. `statement_timeout` de 180 s
-- e o teto; se estourar, a transacao desfaz tudo e a tabela fica como estava.
-- Espaco temporario: a copia nova e os indices novos, ~75 MB, existem
-- junto com os velhos ate o commit.
--
-- Abortar se: o executor acusar lock ou tempo; o tamanho nao cair.

-- PRE: so e necessario se a cota ainda estiver acima de 400 MB (80%).
do $$ begin
  if (select sum(pg_database_size(oid)) from pg_database) <= 400000000 then
    raise exception 'ABORTAR: a folga de 20%% ja foi atingida; este passo nao e necessario';
  end if;
end $$;

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
              where l.relation = 'public.artigos'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em public.artigos';
  end if;
end $$;

-- PRE: disco. Cota + WAL + 2 x o espaco novo (a copia e o WAL dela) cabe em
-- 900 MB -- 90% do disco de 1 GB do plano Free. A copia nova existe junto
-- com a velha ate o commit.
do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  wal bigint := (select coalesce(sum(size), 0) from pg_ls_waldir());
  novo bigint := 75000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
vacuum full public.artigos;
