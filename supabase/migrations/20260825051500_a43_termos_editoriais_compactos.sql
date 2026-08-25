-- A43: persiste somente o resultado do matching editorial, nunca o texto.
--
-- O feed e o wp-json entregam resumo suficiente para encontrar atributos que
-- nao cabem na manchete. Guardar o resumo inteiro seria peso e copyright
-- desnecessarios; `artigo_termos` e a representacao compacta e auditavel.

create or replace function public.registrar_termos_editoriais(ligacoes jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  inseridas integer := 0;
begin
  insert into public.artigo_termos (artigo_id, termo_id)
  select distinct a.id, l.termo_id
  from jsonb_to_recordset(coalesce(ligacoes, '[]'::jsonb))
       as l(url text, termo_id text)
  join public.artigos a on a.url = l.url
  join public.termos t on t.id = l.termo_id and t.status = 'aprovado'
  where l.url is not null and l.termo_id is not null
  on conflict (artigo_id, termo_id) do nothing;

  get diagnostics inseridas = row_count;
  return inseridas;
end;
$function$;

comment on function public.registrar_termos_editoriais(jsonb) is
  'A43: grava pares artigo/termo extraidos em memoria de titulo+resumo; nao persiste o resumo.';

revoke execute on function public.registrar_termos_editoriais(jsonb)
  from public, anon, authenticated;
grant execute on function public.registrar_termos_editoriais(jsonb)
  to service_role;
