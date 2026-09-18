-- INVENTARIO, SOMENTE LEITURA. Nao tem `-- @acao`: o executor roda cada
-- consulta dentro de `begin transaction read only`, e nada aqui escreve.
--
-- Rode antes de qualquer acao, depois de cada passo e todo dia da janela de
-- observacao. As colunas sao as que sustentam os alvos do roteiro.

-- 1. A cota como a plataforma mede, separada em principal e overhead.
select now() as medido_em,
       (select sum(pg_database_size(oid)) from pg_database)::bigint as cota_bytes,
       round(100.0 * (select sum(pg_database_size(oid)) from pg_database) / 500000000, 2)
         as cota_pct,
       pg_database_size(current_database()) as principal_bytes,
       (select sum(pg_database_size(oid)) from pg_database
         where datname <> current_database())::bigint as overhead_bytes,
       (select jsonb_object_agg(datname, pg_database_size(oid)) from pg_database) as por_banco,
       (select coalesce(sum(size), 0) from pg_ls_waldir())::bigint as wal_bytes,
       current_setting('default_transaction_read_only') as somente_leitura,
       current_setting('server_version') as versao;

-- 2. As 20 maiores relacoes, com o que diz se o espaco e dado ou folga.
select n.nspname || '.' || c.relname as tabela,
       pg_relation_size(c.oid, 'main') as heap,
       pg_table_size(c.oid) - pg_relation_size(c.oid, 'main') as toast_fsm_vm,
       pg_indexes_size(c.oid) as indices,
       pg_total_relation_size(c.oid) as total,
       s.n_live_tup as vivas, s.n_dead_tup as mortas,
       s.n_tup_upd as updates, s.n_tup_hot_upd as hot,
       s.last_autovacuum, s.last_vacuum,
       array_to_string(c.reloptions, ',') as opcoes
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_stat_all_tables s on s.relid = c.oid
where c.relkind in ('r', 'm', 'p')
order by pg_total_relation_size(c.oid) desc
limit 20;

-- 3. Dado vivo nas tabelas-alvo e o tamanho estimado depois de reescritas no
-- fillfactor delas: bytes vivos (tupla + ponteiro de 4 bytes) / fillfactor,
-- com 2% de perda de encaixe na pagina. E estimativa com metodo declarado; a
-- verdade e a medida depois de cada passo.
with vivas as (
  select 'public.series_semanais' as tabela, sum(pg_column_size(t.*) + 4) as bytes
    from public.series_semanais t
  union all select 'public.artigos', sum(pg_column_size(t.*) + 4) from public.artigos t
  union all select 'public.indices_semanais', sum(pg_column_size(t.*) + 4)
    from public.indices_semanais t
  union all select 'public.produtos', sum(pg_column_size(t.*) + 4) from public.produtos t
  union all select 'public.snapshots', sum(pg_column_size(t.*) + 4) from public.snapshots t
)
select v.tabela, v.bytes as bytes_vivos,
       pg_relation_size(v.tabela::regclass, 'main') as heap_atual,
       coalesce((regexp_match(array_to_string(c.reloptions, ','),
                              'fillfactor=(\d+)'))[1]::int, 100) as fillfactor,
       round(v.bytes / (coalesce((regexp_match(array_to_string(c.reloptions, ','),
                              'fillfactor=(\d+)'))[1]::int, 100) / 100.0) * 1.02)
         as heap_reescrito_estimado,
       pg_relation_size(v.tabela::regclass, 'main')
         - round(v.bytes / (coalesce((regexp_match(array_to_string(c.reloptions, ','),
                              'fillfactor=(\d+)'))[1]::int, 100) / 100.0) * 1.02)
         as ganho_heap_estimado
from vivas v join pg_class c on c.oid = v.tabela::regclass
order by ganho_heap_estimado desc;

-- 4. Indices-alvo contra um btree recem-construido: por entrada,
-- MAXALIGN(8 de cabecalho + chave) + 4 de ponteiro, folhas a 90%, +1% de
-- paginas internas. Calibrado em 18/09 em `produto_termos_pkey`, que nao tem
-- inchaco: 11,86 MB estimados contra 11,91 MB medidos.
with e as (
  select 'public.artigos_url_key' as indice,
         sum(((8 + pg_column_size(url) + 7) / 8) * 8 + 4) as entradas from public.artigos
  union all select 'public.artigos_pkey', sum(20) from public.artigos
  union all select 'public.estado_produtos_oferta_recente', sum(28) filter (where ofertavel is true)
    from public.estado_dos_produtos
  union all select 'public.estado_dos_produtos_pkey', sum(20) from public.estado_dos_produtos
  union all select 'public.snapshots_produto_id_data_key', sum(28) from public.snapshots
  union all select 'public.snapshots_pkey', sum(20) from public.snapshots
  union all select 'public.produto_termos_pkey',
         sum(((8 + 8 + pg_column_size(termo_id) + pg_column_size(origem) + 7) / 8) * 8 + 4)
    from public.produto_termos
)
select indice, pg_relation_size(indice::regclass) as atual,
       round(entradas / 0.90 * 1.01) as recem_construido_estimado,
       pg_relation_size(indice::regclass) - round(entradas / 0.90 * 1.01) as ganho_estimado
from e order by ganho_estimado desc;

-- 5. O log do pg_cron: tamanho, ritmo e quem escreve nele.
select count(*) as linhas, min(start_time) as mais_antiga, max(start_time) as mais_nova,
       pg_total_relation_size('cron.job_run_details') as bytes,
       round(count(*) / greatest(extract(epoch from max(start_time) - min(start_time)) / 86400, 1))
         as linhas_por_dia,
       count(*) filter (where end_time < now() - interval '7 days' and status = 'succeeded')
         as sucesso_com_mais_de_7_dias,
       count(*) filter (where end_time < now() - interval '30 days') as com_mais_de_30_dias,
       (select jsonb_agg(jsonb_build_object('job', jobname, 'agenda', schedule, 'ativo', active))
          from cron.job) as jobs
from cron.job_run_details;

-- 6. O cru que a A58 precisa: cobertura dos snapshots e quanto a poda da A42
-- apagaria HOJE se o motor rodasse sem a P24.
select min(data) as mais_antigo, max(data) as mais_novo, count(distinct data) as dias,
       count(*) as linhas, current_date - 21 as corte_da_poda_hoje,
       count(*) filter (where data < current_date - 21) as linhas_que_a_poda_apagaria,
       count(distinct data) filter (where data < current_date - 21) as dias_que_a_poda_apagaria,
       to_regclass('public.sortimento_diario') is not null as a58_aplicada
from public.snapshots;

-- 7. Quem esta no banco agora: sessoes, locks esperando, transacoes longas e
-- publicacoes do motor em andamento.
select (select count(*) from pg_stat_activity
          where datname = current_database() and pid <> pg_backend_pid()
            and state <> 'idle') as outras_sessoes_ativas,
       (select count(*) from pg_locks where not granted) as locks_esperando,
       (select max(now() - xact_start) from pg_stat_activity
          where datname = current_database() and pid <> pg_backend_pid()
            and xact_start is not null) as transacao_mais_longa,
       (select count(*) from public.motor_execucoes
          where status in ('queued', 'running')) as motor_em_andamento,
       (select max(age(datfrozenxid)) from pg_database) as idade_xid;

-- 8. As funcoes que P21, P22 e P24 substituem, contra o que foi medido em
-- 18/09. Diferenca aqui e criterio de abortamento: a migration substituiria
-- outra coisa.
select p.proname,
       md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) as hash_atual,
       case p.proname
         when 'computar_serie_varejo' then '4a1b76d8d0b9d81086474a563006d6b5'
         when 'computar_serie_editorial' then 'a56488dcf1e732973339e50442882c5e'
         when 'computar_z' then 'a84c63a5c5acd5fa95a25fe7fd0df120'
         when 'uso_do_banco' then '7c6355a6bd043f9d01108f01d465bc39'
         when 'podar_snapshots' then 'c9b22fd0cc607449cbbf7b5aef7c77cf'
       end as hash_de_18_09
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('computar_serie_varejo', 'computar_serie_editorial', 'computar_z',
                    'uso_do_banco', 'podar_snapshots')
order by 1;
