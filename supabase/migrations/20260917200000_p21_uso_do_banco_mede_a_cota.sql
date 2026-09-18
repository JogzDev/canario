-- P21: o portao de capacidade passa a medir o que a cota mede.
--
-- POR QUE
-- =======
--
-- A P5 media `pg_database_size(current_database())` -- so o banco `postgres`.
-- A cota do plano Free e outra conta. A documentacao do Supabase define
-- "Database size" como a soma sobre TODOS os bancos do cluster:
--
--   select sum(pg_database_size(pg_database.datname)) from pg_database;
--
-- (supabase.com/docs/guides/platform/database-size, consultada em 18/09/2026)
--
-- Medido em 18/09/2026 as 12:37 UTC, em leitura:
--
--   postgres     485.952.659 bytes   o que a P5 enxergava   97,19%
--   template0      7.520.783 bytes
--   template1      7.752.851 bytes
--   total        501.226.293 bytes   o que a cota enxerga  100,25%
--
-- O portao dizia 97,2% e bloqueava a coleta por estar acima de 96%. A conta
-- da plataforma ja passou de 100%. A diferenca, 15,3 MB, nao e nossa: sao os
-- bancos-modelo do cluster. Nao temos como reduzi-los e esta migration nao
-- finge que temos -- ela passa a MOSTRAR os tres numeros separados e a usar o
-- total para decidir.
--
-- O QUE A RPC DEVOLVE
-- ===================
--
--   bytes_da_cota            soma de todos os bancos -- o que decide
--   banco_principal_bytes    o banco `postgres`, onde mora o nosso dado
--   overhead_interno_bytes   todos os outros bancos do cluster
--   por_banco                os tres, nome a nome
--   bytes                    = bytes_da_cota. A chave antiga continua
--                            existindo e passa a carregar o total: um
--                            verificador antigo que so le `bytes` fica MAIS
--                            conservador, nunca menos.
--
-- O QUE ELA AINDA NAO SABE
-- ========================
--
-- A documentacao diz que a metrica do painel "e atualizada diariamente".
-- Esta RPC mede agora; o painel pode mostrar um numero de ate um dia atras.
-- E o momento exato em que a plataforma liga o modo somente-leitura nao e
-- observavel por SQL: `default_transaction_read_only` estava `off` em 18/09
-- com o total ja acima de 500 MB.
--
-- `pg_database_size` de outro banco exige CONNECT nele ou `pg_read_all_stats`.
-- A funcao e SECURITY DEFINER do papel `postgres`, que e membro de
-- `pg_read_all_stats` (conferido em 18/09). Custo: uma leitura de diretorio
-- por banco, sem varrer tabela nenhuma.

create or replace function public.uso_do_banco()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  with bancos as (
    select d.datname, pg_database_size(d.oid) as bytes
    from pg_database d
  ), totais as (
    select sum(bytes)::bigint as cota,
           sum(bytes) filter (where datname = current_database())::bigint
             as principal,
           coalesce(sum(bytes) filter (where datname <> current_database()), 0)::bigint
             as overhead
    from bancos
  )
  select jsonb_build_object(
    'bytes', t.cota,
    'bytes_da_cota', t.cota,
    'banco_principal_bytes', t.principal,
    'overhead_interno_bytes', t.overhead,
    'por_banco', (select jsonb_object_agg(datname, bytes) from bancos),
    'metrica', 'sum(pg_database_size) sobre pg_database, a definicao de Database size da documentacao do Supabase',
    'limite_bytes', 500000000,
    'medido_em', now()
  )
  from totais t;
$function$;

revoke execute on function public.uso_do_banco()
  from public, anon, authenticated;
grant execute on function public.uso_do_banco() to service_role;

comment on function public.uso_do_banco() is
  'P21: mede a cota como a plataforma mede (soma de todos os bancos do cluster) e separa banco principal de overhead interno; indisponivel para o app e para usuarios publicos.';
