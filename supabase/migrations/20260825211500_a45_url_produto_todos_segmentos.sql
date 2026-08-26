-- A45: a A39 passou a aceitar `catalogo_candidato_br`, mas reutilizou o índice
-- parcial da A32, válido somente para `feminino_casual_br`. Ao aparecer o OR
-- dos dois segmentos o plano deixou de usar aquele índice e a URL real do
-- vestido de tomates da Farm estourou o statement_timeout público de 3 s.

create index if not exists produtos_url_lookup_segmentos
  on public.produtos (url)
  where url is not null
    and segmento in ('feminino_casual_br', 'catalogo_candidato_br');

create or replace function public.produto_do_painel_por_url(p_url text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  limpa text;
  candidatas text[];
  v_produto_id bigint;
  resultado jsonb;
begin
  if p_url is null or length(p_url) > 2048 or p_url !~ '^https://[^/]+/' then
    return null;
  end if;
  limpa := rtrim(split_part(p_url, '?', 1), '/');
  candidatas := array[limpa, limpa || '/'];
  if limpa ~ '^https://secure\.farmrio\.com\.br/' then
    candidatas := candidatas || array[
      regexp_replace(limpa, '^https://secure\.farmrio\.com\.br',
                     'https://www.farmrio.com.br'),
      regexp_replace(limpa, '^https://secure\.farmrio\.com\.br',
                     'https://www.farmrio.com.br') || '/'
    ];
  end if;

  -- Isola primeiro o único id por igualdade indexada. Os joins e a agregação
  -- dos termos só acontecem depois; uma URL ausente também volta em milissegundos.
  select p.id into v_produto_id
  from public.produtos p
  where p.url = any(candidatas)
    and p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
  order by p.id desc
  limit 1;

  if v_produto_id is null then return null; end if;

  select jsonb_build_object(
    'id', p.id, 'title', p.titulo, 'brand', m.nome,
    'image_url', p.imagem_url, 'price', p.ultimo_preco_atual,
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
  where p.id = v_produto_id
    and ep.ofertavel is true
    and ep.ultimo_avistamento_em >= current_date - 7;

  return resultado;
end;
$function$;

comment on function public.produto_do_painel_por_url(text) is
  'A45: lookup indexado de URL nos segmentos brasileiro e candidato, incluindo alias secure/www da Farm.';

revoke all on function public.produto_do_painel_por_url(text) from public;
grant execute on function public.produto_do_painel_por_url(text)
  to anon, authenticated;
