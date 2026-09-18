-- PASSO 40 · ALTERNATIVA PARCIAL; NAO FAZ PARTE DA SEQUENCIA NORMAL.
--
-- @espera_encolher
-- @alvo public.artigos_url_key
--
-- Alvo exato: o indice `public.artigos_url_key` e nada mais.
--
-- MUTUAMENTE EXCLUSIVO COM O PASSO 60. O caminho normal mede depois do 50
-- e, se a cota ainda estiver acima de 400 MB, pula este arquivo e vai direto
-- ao `VACUUM FULL artigos`: ele ja reconstroi este indice. Rodar 40 e depois
-- 60 repetiria o mesmo trabalho, o lock e o WAL sem recuperar um byte a mais.
--
-- Este arquivo so existe como recuperacao PARCIAL se o 60 tiver sido
-- descartado por sua janela de lock ou pelo espaco temporario. Pelas medidas
-- de 18/09, sozinho ele levaria a cota esperada de ~427,2 para ~407,3 MB, sem
-- atingir a meta de 400 MB. Depois dele, rode o 70; se falhar, pare e revise.
-- Nao prossiga para o 60 na mesma execucao.
--
-- O que faz: reconstroi o indice do zero. O dado da tabela nao muda.
-- Medido em 18/09: 41.951.232 bytes; um btree recem-construido com as mesmas entradas
-- teria ~22,09 MB (172.649 URLs) (formula do inventario, consulta 4). Ganho estimado: ~19,9 MB. E o indice unico que o `on_conflict=url` da coleta editorial percorre; as 828.725 atualizacoes de `artigos` (4,7% HOT) deixaram entradas mortas em todas as paginas.
--
-- Lock: ACCESS EXCLUSIVE no indice e SHARE na tabela `public.artigos` -- bloqueia
-- escritas e, como o planejador toca todos os indices da tabela, praticamente
-- toda consulta a ela durante a reconstrucao. Com a coleta parada, quem
-- espera e o app. Duracao esperada: 3 a 15 s.
-- Espaco temporario: o indice novo, ~25 MB, existe junto com o velho ate o fim.
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
  novo bigint := 25000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
reindex index public.artigos_url_key;
