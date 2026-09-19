-- PASSO 21 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo public.estado_dos_produtos_pkey
--
-- Alvo exato: o indice `public.estado_dos_produtos_pkey` e nada mais.
--
-- O que faz: reconstroi o indice do zero. O dado da tabela nao muda.
-- Medido em 18/09: 4.546.560 bytes; um btree recem-construido com as mesmas entradas
-- teria ~2,50 MB (111.390 entradas) (formula do inventario, consulta 4). Ganho estimado: ~2,0 MB.
--
-- Lock: ACCESS EXCLUSIVE no indice e SHARE na tabela `public.estado_dos_produtos` -- bloqueia
-- escritas e, como o planejador toca todos os indices da tabela, praticamente
-- toda consulta a ela durante a reconstrucao. Com a coleta parada, quem
-- espera e o app. Duracao esperada: 1 a 3 s.
-- Espaco temporario: o indice novo, ~3 MB, existe junto com o velho ate o fim.
--
-- Alternativa se houver trafego no app: `reindex index concurrently`, que
-- nao bloqueia leitura nem escrita, demora mais, usa o mesmo espaco e, se
-- falhar, deixa um indice invalido `*_ccnew` que precisa ser apagado a mao.
--
-- Abortar se: o executor acusar lock; o indice nao encolher.

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
              where l.relation = 'public.estado_dos_produtos'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em public.estado_dos_produtos';
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
reindex index public.estado_dos_produtos_pkey;
