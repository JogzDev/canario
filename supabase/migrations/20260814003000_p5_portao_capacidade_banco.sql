-- PORTAO DE CAPACIDADE DO BANCO
--
-- O projeto Free entra em read-only quando o tamanho do PostgreSQL cruza
-- 500 MB. Em 14/08 o banco chegou a 482.864.275 bytes sem nenhum alerta no
-- pipeline. Esta RPC expõe apenas o total agregado ao service_role; o app e as
-- chaves públicas não ganham acesso a catálogo, tabelas ou detalhes internos.

create or replace function public.uso_do_banco()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'bytes', pg_database_size(current_database()),
    'limite_bytes', 500000000,
    'medido_em', now()
  );
$function$;

revoke execute on function public.uso_do_banco()
  from public, anon, authenticated;
grant execute on function public.uso_do_banco() to service_role;

comment on function public.uso_do_banco() is
  'Tamanho agregado usado pelo portao de capacidade antes das coletas; '
  'indisponivel para o app e para usuarios publicos.';
