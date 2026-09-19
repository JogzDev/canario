-- PASSO 92 · COMPACTA `snapshots` DEPOIS DA PODA JÁ CONCLUÍDA.
--
-- @espera_encolher
-- @alvo public.snapshots
--
-- Este passo NÃO apaga nem altera linhas. `VACUUM FULL` cria uma cópia física
-- apenas com as tuplas vivas e reconstrói os índices. A medição de 19/09
-- encontrou 83.400 linhas, 73,14 MB físicos e ~17,95 MB reconstruídos.
--
-- Lock: ACCESS EXCLUSIVE. O executor limita a espera por lock a 5 s e a ação
-- inteira a 180 s. Se qualquer pré-condição falhar, a ação não é enviada.

-- PRE: a relação certa existe, contém a observação de hoje e ainda tem volume
-- compatível com a medição. O mínimo só pode ser reduzido no laboratório.
do $$
declare
  minimo bigint := coalesce(
    nullif(current_setting('datadrobe.min_snapshots', true), '')::bigint,
    80000);
  n bigint;
  primeira date;
  ultima date;
begin
  select count(*), min(data), max(data) into n, primeira, ultima
  from public.snapshots;
  if n < minimo then
    raise exception 'ABORTAR: snapshots tem % linhas; minimo esperado %', n, minimo;
  end if;
  if primeira is null or ultima <> current_date then
    raise exception
      'ABORTAR: periodo de snapshots divergiu (primeira %, ultima %, hoje %)',
      primeira, ultima, current_date;
  end if;
end $$;

-- PRE: nenhuma publicação do motor pode concorrer com a reescrita.
do $$ begin
  if exists (select 1 from public.motor_execucoes
              where status in ('queued', 'running')) then
    raise exception 'ABORTAR: publicacao do motor em andamento';
  end if;
end $$;

-- PRE: o inventário continua sendo exatamente chave primária + unicidade de
-- produto/data, ambos prontos e válidos. Índice inesperado muda custo/risco.
do $$
declare
  total integer;
  corretos integer;
begin
  select count(*), count(*) filter (where
    (i.relname = 'snapshots_pkey' and x.indisprimary and x.indisunique)
    or
    (i.relname = 'snapshots_produto_id_data_key'
      and not x.indisprimary and x.indisunique))
  into total, corretos
  from pg_index x
  join pg_class i on i.oid = x.indexrelid
  where x.indrelid = 'public.snapshots'::regclass
    and x.indisvalid and x.indisready;

  if total <> 2 or corretos <> 2 then
    raise exception
      'ABORTAR: inventario de indices de snapshots divergiu (validos %, esperados %)',
      total, corretos;
  end if;
end $$;

-- PRE: nenhuma outra sessão segura lock na relação. Além do lock curto do
-- executor, isto impede que a manutenção entre numa fila que atrase leitores.
do $$ begin
  if exists (select 1 from pg_locks l
              where l.relation = 'public.snapshots'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em public.snapshots';
  end if;
end $$;

-- PRE: o ganho ainda é material. A estimativa é conservadora e serve somente
-- como portão; a medição física posterior é a autoridade.
do $$
declare
  atual bigint := pg_total_relation_size('public.snapshots');
  estimado numeric;
begin
  select
    ceil(sum(((pg_column_size(s.*) + 7) / 8) * 8 + 4) * 1.03)
    + ceil(count(*) * 20 / 0.90 * 1.01)
    + ceil(count(*) * 28 / 0.90 * 1.01)
    + pg_total_relation_size(c.reltoastrelid)
  into estimado
  from public.snapshots s
  cross join pg_class c
  where c.oid = 'public.snapshots'::regclass
  group by c.reltoastrelid;

  if atual <= estimado * 1.50 then
    raise exception
      'ABORTAR: ganho estimado de snapshots abaixo de 33%% (atual %, novo ~%)',
      atual, round(estimado);
  end if;
end $$;

-- PRE: a cópia nova e o WAL estimado cabem com larga margem no disco físico.
do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  wal bigint := (select coalesce(sum(size), 0) from pg_ls_waldir());
  novo bigint;
begin
  select greatest(25000000::bigint,
    ceil(sum(((pg_column_size(s.*) + 7) / 8) * 8 + 4) * 1.03
      + count(*) * 48 / 0.90 * 1.01)::bigint)
  into novo from public.snapshots s;

  if cota + wal + 2 * novo > 900000000 then
    raise exception 'ABORTAR: cota % + WAL % + 2 x % passa de 900 MB',
      cota, wal, novo;
  end if;
end $$;

-- Evidência anterior: contagem, período e hash determinístico de todas as
-- linhas. O passo 93 repete exatamente esta assinatura depois da ação.
select count(*)::bigint as linhas,
       min(data) as primeira_data,
       max(data) as ultima_data,
       md5(string_agg(md5(to_jsonb(s)::text), '' order by id)) as assinatura
from public.snapshots s;

-- @acao
vacuum full public.snapshots;
