-- SOMENTE LEITURA. O executor passo.mjs protege cada consulta com READ ONLY.
-- Não compacta, não poda, não instala extensões e não altera a coorte.
-- Para repetir no SQL Editor, envolver em BEGIN TRANSACTION READ ONLY e
-- terminar com ROLLBACK. Os números de tuple e atualizações são estatísticas,
-- não contagens exatas nem atribuição de crescimento a uma execução.

set statement_timeout = '15s';

select now() as medido_em,
       (select sum(pg_database_size(oid)) from pg_database)::bigint as cota_bytes,
       pg_database_size(current_database()) as principal_bytes,
       (select stats_reset from pg_stat_database
         where datname = current_database()) as stats_reset,
       (select coalesce(sum(size), 0) from pg_ls_waldir())::bigint as wal_bytes;

select n.nspname || '.' || c.relname as tabela,
       pg_total_relation_size(c.oid) as total_bytes,
       pg_relation_size(c.oid) as heap_bytes,
       pg_indexes_size(c.oid) as indices_bytes,
       s.n_live_tup as vivas_estimadas, s.n_dead_tup as mortas_estimadas,
       s.n_tup_ins as insercoes, s.n_tup_upd as updates, s.n_tup_del as exclusoes
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_stat_all_tables s on s.relid = c.oid
where c.relkind = 'r' and n.nspname in ('public', 'cron')
order by pg_total_relation_size(c.oid) desc;

select data, count(*) as linhas, sum(pg_column_size(s.*) + 4) as bytes_logicos
from public.snapshots s group by data order by data;

-- Modelo de estimativa, NÃO garantia de tamanho após VACUUM FULL:
-- alinhamento de 8 bytes + ponteiro, 3% para páginas do heap; dois btrees
-- conhecidos com 90% de ocupação + 1% interno. O inventário dos índices abaixo
-- deve confirmar que continuam somente esses dois; TOAST/fillfactor podem
-- invalidar a estimativa. A prova definitiva requer ensaio e medição real.
select count(*) as linhas,
       ceil(sum(((pg_column_size(s.*) + 7) / 8) * 8 + 4) * 1.03)
         as heap_alinhado_estimado,
       ceil(count(*) * 20 / 0.90 * 1.01) as indice_id_estimado,
       ceil(count(*) * 28 / 0.90 * 1.01) as indice_produto_data_estimado
from public.snapshots s;

select indexname, indexdef,
       pg_relation_size((schemaname || '.' || indexname)::regclass) as bytes
from pg_indexes where schemaname = 'public' and tablename = 'snapshots';

select reloptions, pg_total_relation_size(reltoastrelid) as toast_bytes
from pg_class where oid = 'public.snapshots'::regclass;

-- Não deduzir frescor do sucesso do motor. O marco publicado pode não avançar.
select * from public.observacoes_publicadas_do_painel order by segmento;

-- Explica as condições persistidas da A58 para a data corrente. Uma recuperação
-- de outro dia deve usar sua DATA_OPERACIONAL no lugar de current_date.
-- Esta consulta é diagnóstico, não uma segunda implementação que autoriza
-- publicação. A função SQL canônica continua sendo a autoridade da cobertura.
select m.nome, s.visitados, s.alertas, h.media as media_positiva_7d,
       coalesce(s.visitados, 0) > 0
         and not (coalesce(s.alertas, '{}'::jsonb)
                    ?| array['truncou', 'faixas_truncadas'])
         and (h.media is null or s.visitados::numeric >= h.media * 0.30)
         as atende_volume_e_integridade
from public.marcas m
left join public.saude s
  on s.marca_id = m.id and s.fonte = 'varejo' and s.data = current_date
left join lateral (
  select avg(visitados) as media from public.saude
  where fonte = 'varejo' and marca_id = m.id
    and data >= current_date - 7 and data < current_date and visitados > 0
) h on true
where m.segmento = 'feminino_casual_br' and m.ativa is true
  and m.status_teste in ('vtex', 'shopify')
order by m.nome;
