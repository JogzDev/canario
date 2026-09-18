-- PASSO 40 · DEVOLVE ESPACO FISICO. EXCLUSIVO COM O 60 (ver passo 55).
--
-- @espera_encolher
-- @alvo public.artigos_url_key
--
-- Alvo exato: o indice `public.artigos_url_key` e nada mais.
--
-- MUTUAMENTE EXCLUSIVO COM O PASSO 60. A medicao do passo 55 escolhe o 40
-- somente quando o reindex sozinho basta para chegar a 400 MB. Se nao basta,
-- escolhe o 60, que reconstroi este indice junto com heap e chave primaria.
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

-- PRE: aplica a decisao do passo 55. O 40 so roda se a cota estiver acima
-- do teto, o indice ainda estiver inchado e seu ganho estimado bastar sozinho.
do $$
declare
  teto bigint := coalesce(nullif(current_setting('datadrobe.teto_bytes', true), '')::bigint,
                          400000000);
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  url_atual bigint := pg_relation_size('public.artigos_url_key');
  url_recem bigint := (select round(sum(((8 + pg_column_size(url) + 7) / 8) * 8 + 4)
                                    / 0.90 * 1.01)
                         from public.artigos);
  ganho_40 bigint := greatest(url_atual - url_recem, 0);
begin
  if cota <= teto then
    raise exception 'ABORTAR: a cota (%) ja esta dentro do teto (%): nem 40 nem 60', cota, teto;
  end if;
  if url_atual <= url_recem * 1.10 then
    raise exception 'ABORTAR: artigos_url_key ja foi reconstruido (% contra % estimados); o 40 ou o 60 ja rodou -- parar e revisar',
      url_atual, url_recem;
  end if;
  if cota - ganho_40 > teto then
    raise exception 'ABORTAR: o 40 sozinho nao basta (% - % > %); use o 60', cota, ganho_40, teto;
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
  novo bigint := 25000000;
begin
  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB', cota, wal, novo;
  end if;
end $$;

-- @acao
reindex index public.artigos_url_key;
