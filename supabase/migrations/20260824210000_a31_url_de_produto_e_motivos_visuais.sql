-- A31: uma URL conhecida do painel vira entrada auditável, sem visão e sem
-- guardar a URL de navegação do usuário. Motivos figurativos vivem numa
-- dimensão própria: podem melhorar similares, mas não fingem ser a taxonomia
-- ampla de estampa nem ganham uma série de busca sem volume medido.

insert into public.termos
  (id, rotulo, dimensao, exclusiva, sinonimos, palavras_pt, palavras_en,
   exemplo, status, sem_perna_busca, motivo, papel)
values
  ('tomate_print', 'Tomate', 'motivo_estampa', false, 'tomate|tomatinho',
   'tomate|tomates|tomatinho|tomatinhos', 'tomato|tomatoes',
   'Tomates reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares; nao alimenta busca', 'atributo'),
  ('cereja_print', 'Cereja', 'motivo_estampa', false, 'cereja|cerejinha',
   'cereja|cerejas|cerejinha|cerejinhas', 'cherry|cherries',
   'Cerejas reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares', 'atributo'),
  ('morango_print', 'Morango', 'motivo_estampa', false, 'morango|morangos',
   'morango|morangos', 'strawberry|strawberries',
   'Morangos reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares', 'atributo'),
  ('banana_print', 'Banana', 'motivo_estampa', false, 'banana|bananas',
   'banana|bananas', 'banana|bananas',
   'Bananas reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares', 'atributo'),
  ('abacaxi_print', 'Abacaxi', 'motivo_estampa', false, 'abacaxi|abacaxis',
   'abacaxi|abacaxis', 'pineapple|pineapples',
   'Abacaxis reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares', 'atributo'),
  ('melancia_print', 'Melancia', 'motivo_estampa', false, 'melancia|melancias',
   'melancia|melancias', 'watermelon|watermelons',
   'Melancias reconheciveis na estampa', 'aprovado', 'sim',
   'A31: motivo para similares', 'atributo')
on conflict (id) do update set
  rotulo = excluded.rotulo,
  dimensao = excluded.dimensao,
  exclusiva = excluded.exclusiva,
  sinonimos = excluded.sinonimos,
  palavras_pt = excluded.palavras_pt,
  palavras_en = excluded.palavras_en,
  exemplo = excluded.exemplo,
  status = excluded.status,
  sem_perna_busca = excluded.sem_perna_busca,
  motivo = excluded.motivo,
  papel = excluded.papel;

with motivos(termo_id, padrao) as (
  values
    ('tomate_print',  '\m(tomate|tomates|tomatinho|tomatinhos|tomato|tomatoes)\M'),
    ('cereja_print',  '\m(cereja|cerejas|cerejinha|cerejinhas|cherry|cherries)\M'),
    ('morango_print', '\m(morango|morangos|strawberry|strawberries)\M'),
    ('banana_print',  '\m(banana|bananas)\M'),
    ('abacaxi_print', '\m(abacaxi|abacaxis|pineapple|pineapples)\M'),
    ('melancia_print','\m(melancia|melancias|watermelon|watermelons)\M')
)
insert into public.produto_termos(produto_id, termo_id, origem)
select p.id, m.termo_id, 'titulo'
from public.produtos p
cross join motivos m
where lower(coalesce(p.titulo, '')) ~ m.padrao
on conflict do nothing;

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
  limpa := regexp_replace(split_part(p_url, '?', 1), '/+$', '');

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
  where regexp_replace(split_part(coalesce(p.url, ''), '?', 1), '/+$', '') = limpa
    and p.segmento = 'feminino_casual_br'
    and ep.ofertavel is true
    and ep.ultimo_avistamento_em >= current_date - 7
  order by p.id desc
  limit 1;

  return resultado;
end;
$function$;

comment on function public.produto_do_painel_por_url(text) is
  'A31: resolve somente URL exata já coletada e devolve atributos aprovados; nenhuma foto nem dado do usuário é persistido.';

revoke all on function public.produto_do_painel_por_url(text) from public;
grant execute on function public.produto_do_painel_por_url(text)
  to anon, authenticated;
