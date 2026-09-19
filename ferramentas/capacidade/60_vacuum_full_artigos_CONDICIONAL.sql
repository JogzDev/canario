-- PASSO 60 · DEVOLVE ESPACO FISICO.
--
-- @espera_encolher
-- @alvo public.artigos
--
-- Alvo exato: a tabela `public.artigos`, o TOAST dela e os indices dela.
--
-- CONDICIONAL E EXCLUSIVO COM O 40 (ver passo 55). `VACUUM FULL` reescreve
-- a tabela e reconstroi todos os seus indices, portanto executar o 40 antes
-- repetiria a reconstrucao de `artigos_url_key`, o lock e o WAL.
--
-- O que faz: reescreve a tabela so com as linhas vivas, no fillfactor dela
-- (100), e reconstroi os indices. Nenhuma linha e apagada ou alterada.
-- Medido em 18/09: heap de 55,93 MB com 43,09 MB de dado vivo. Reescrito:
-- ~44,0 MB (inventario, consulta 3). Sem executar o 40 antes,
-- `artigos_url_key` cai de 42,0 para ~22,1 MB e `artigos_pkey`, de 7,7 para
-- ~3,9 MB. Ganho direto estimado: ~35,7 MB (heap ~12,0 + URL ~19,9 + chave
-- primaria ~3,9), levando a cota esperada de ~427,2 para ~391,5 MB.
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

-- PRE: aplica a decisao do passo 55. O 60 so roda se a cota estiver acima do
-- teto, o indice ainda estiver inchado e o ganho do 40 NAO bastar sozinho.
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
    raise exception 'ABORTAR: a folga de 20%% ja foi atingida (cota % <= teto %); este passo nao e necessario',
      cota, teto;
  end if;
  if url_atual <= url_recem * 1.10 then
    raise exception 'ABORTAR: artigos_url_key ja foi reconstruido (% contra % estimados); o 40 ou o 60 ja rodou -- parar e revisar',
      url_atual, url_recem;
  end if;
  if cota - ganho_40 <= teto then
    raise exception 'ABORTAR: o 40 sozinho basta (% - % <= %); use o 40', cota, ganho_40, teto;
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

-- PRE: o estado pode ter mudado desde a medicao de 18/09. Nao assuma o maior
-- lock do roteiro se a tabela e os dois btrees ja estiverem perto do tamanho
-- de uma reconstrucao nova. A estimativa usa o mesmo metodo auditado pelo
-- inventario: tuplas vivas + ponteiros, folhas dos btrees a 90% e 2%/1% de
-- perda de encaixe. Menos de 15% de ganho material exige nova decisao.
do $$
declare
  atual numeric := pg_total_relation_size('public.artigos');
  estimado numeric;
begin
  select
    1.02 * coalesce(sum(pg_column_size(a.*) + 4), 0)
    + 1.01 / 0.90 * coalesce(sum(20), 0)
    + 1.01 / 0.90 * coalesce(sum(
        ((8 + pg_column_size(a.url) + 7) / 8) * 8 + 4), 0)
  into estimado
  from public.artigos a;

  if atual <= estimado * 1.15 then
    raise exception
      'ABORTAR: ganho estimado de artigos abaixo de 15%% (atual %, novo ~%)',
      atual, round(estimado);
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
