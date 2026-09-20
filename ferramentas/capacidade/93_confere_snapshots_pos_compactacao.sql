-- SOMENTE LEITURA. Deve rodar imediatamente depois do passo 92.
-- A contagem, o período e a assinatura precisam ser idênticos à evidência
-- anterior impressa pelo passo 92; os dois índices precisam seguir válidos.

set statement_timeout = '30s';

select now() as medido_em,
       (select sum(pg_database_size(oid)) from pg_database)::bigint as cota_bytes,
       pg_database_size(current_database())::bigint as principal_bytes,
       (select coalesce(sum(size), 0) from pg_ls_waldir())::bigint as wal_bytes,
       pg_total_relation_size('public.snapshots')::bigint as snapshots_total_bytes,
       pg_relation_size('public.snapshots')::bigint as snapshots_heap_bytes,
       pg_indexes_size('public.snapshots')::bigint as snapshots_indices_bytes;

select count(*)::bigint as linhas,
       min(data) as primeira_data,
       max(data) as ultima_data,
       md5(string_agg(md5(to_jsonb(s)::text), '' order by id)) as assinatura
from public.snapshots s;

select i.relname as indice,
       x.indisprimary as primario,
       x.indisunique as unico,
       x.indisvalid as valido,
       x.indisready as pronto,
       pg_relation_size(i.oid)::bigint as bytes
from pg_index x
join pg_class i on i.oid = x.indexrelid
where x.indrelid = 'public.snapshots'::regclass
order by i.relname;

select count(*) filter (where status in ('queued', 'running'))::integer
         as motor_em_andamento
from public.motor_execucoes;
