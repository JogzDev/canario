-- A39: a URL pública atual da Farm usa `secure`, enquanto o coletor grava o
-- host canônico `www`. Ambos apontam para o mesmo slug VTEX e devem resolver
-- pelo índice, sem varrer a tabela.

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
  where p.url = any(candidatas)
    and p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
    and ep.ofertavel is true
    and ep.ultimo_avistamento_em >= current_date - 7
  order by p.id desc
  limit 1;
  return resultado;
end;
$function$;

revoke all on function public.produto_do_painel_por_url(text) from public;
grant execute on function public.produto_do_painel_por_url(text)
  to anon, authenticated;

-- Motivo reconhecível é o elo solicitado entre marcas. Quando ele existe,
-- consultar primeiro uma categoria muito ampla (por exemplo Tops) pode bater
-- o timeout e ainda esconder vestidos/saias com o mesmo tomate. A rota usa o
-- detalhe figurativo como âncora, declara a categoria relaxada e mantém o
-- motor amplo anterior para todas as peças sem motivo.
create or replace function public.similares_da_peca_amplo(
  termos text[], limite integer default 12, preco_alvo numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  estrita jsonb;
  ampliada jsonb;
  motivos text[];
  dimensao_a_relaxar text;
  termos_reduzidos text[];
  dimensoes_originais integer;
  atributos_originais integer;
begin
  select array_agg(e.id order by e.posicao)
    into motivos
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao = 'motivo_estampa';

  select count(*)::integer, count(distinct t.dimensao)::integer
    into atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) e(id)
  join public.termos t on t.id = e.id and t.status = 'aprovado';

  if cardinality(motivos) > 0 then
    ampliada := public.similares_da_peca(motivos, limite, preco_alvo);
    ampliada := jsonb_set(ampliada, '{resumo,atributos_pedidos}',
                          to_jsonb(atributos_originais), true);
    ampliada := jsonb_set(ampliada, '{resumo,dimensoes_pedidas}',
                          to_jsonb(dimensoes_originais), true);
    ampliada := jsonb_set(ampliada, '{resumo,dimensao_relaxada}',
                          '"categoria"'::jsonb, true);
    return ampliada;
  end if;

  estrita := public.similares_da_peca(termos, limite, preco_alvo);
  if jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) >= least(limite, 8) then
    return estrita;
  end if;

  select t.dimensao into dimensao_a_relaxar
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao not in ('categoria', 'motivo_estampa')
  group by t.dimensao
  order by array_position(
    array['estetica','comprimento','silhueta','cintura','tecido','cor','estampa'],
    t.dimensao) nulls last, min(e.posicao)
  limit 1;
  if dimensao_a_relaxar is null then return estrita; end if;

  select array_agg(e.id order by e.posicao)
    into termos_reduzidos
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> dimensao_a_relaxar;
  if cardinality(termos_reduzidos) = 0 then return estrita; end if;

  ampliada := public.similares_da_peca(termos_reduzidos, limite, preco_alvo);
  if jsonb_array_length(coalesce(ampliada->'pecas', '[]'::jsonb)) <=
     jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) then
    return estrita;
  end if;
  ampliada := jsonb_set(ampliada, '{resumo,atributos_pedidos}',
                        to_jsonb(atributos_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensoes_pedidas}',
                        to_jsonb(dimensoes_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensao_relaxada}',
                        to_jsonb(dimensao_a_relaxar), true);
  return ampliada;
end;
$function$;

revoke all on function public.similares_da_peca_amplo(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca_amplo(text[], integer, numeric)
  to anon, authenticated;
