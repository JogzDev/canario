-- A32: a primeira versão normalizava a coluna inteira e estourou o timeout de
-- 3 s do papel público. Normaliza somente a entrada e usa índice na URL crua.

create index if not exists produtos_url_lookup
  on public.produtos (url)
  where segmento = 'feminino_casual_br' and url is not null;

create or replace function public.produto_do_painel_por_url(p_url text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  limpa text;
  resultado jsonb;
begin
  if p_url is null or length(p_url) > 2048 or p_url !~ '^https://[^/]+/' then
    return null;
  end if;
  limpa := rtrim(split_part(p_url, '?', 1), '/');

  select jsonb_build_object(
    'id', p.id,
    'title', p.titulo,
    'brand', m.nome,
    'image_url', p.imagem_url,
    'price', p.ultimo_preco_atual,
    'term_ids', coalesce((
      select jsonb_agg(pt.termo_id order by pt.termo_id)
      from public.produto_termos pt
      join public.termos t on t.id = pt.termo_id
      where pt.produto_id = p.id and t.status = 'aprovado'
    ), '[]'::jsonb)
  ) into resultado
  from public.produtos p
  join public.marcas m on m.id = p.marca_id
  join public.estado_dos_produtos ep on ep.produto_id = p.id
  where p.url in (limpa, limpa || '/')
    and p.segmento = 'feminino_casual_br'
    and ep.ofertavel is true
    and ep.ultimo_avistamento_em >= current_date - 7
  order by p.id desc
  limit 1;

  return resultado;
end;
$function$;

comment on function public.produto_do_painel_por_url(text) is
  'A32: resolve URL exata já coletada por índice e devolve somente atributos aprovados.';

revoke all on function public.produto_do_painel_por_url(text) from public;
grant execute on function public.produto_do_painel_por_url(text)
  to anon, authenticated;
