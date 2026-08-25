-- A33: dois resultados perfeitos não devem esconder seis alternativas úteis.
-- Mantém categoria e motivo figurativo, remove no máximo uma dimensão de baixa
-- cobertura e só troca a resposta quando a amostra realmente cresce.

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
  dimensao_a_relaxar text;
  termos_reduzidos text[];
  dimensoes_originais integer;
  atributos_originais integer;
begin
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
    t.dimensao) nulls last,
    min(e.posicao)
  limit 1;

  if dimensao_a_relaxar is null then return estrita; end if;

  select array_agg(e.id order by e.posicao),
         count(*)::integer,
         count(distinct t.dimensao)::integer
    into termos_reduzidos, atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> dimensao_a_relaxar;

  -- Contagens originais são calculadas separadamente porque o array acima já
  -- exclui a dimensão. Elas explicam o relaxamento na tela sem fingir que o
  -- usuário pediu menos atributos.
  select count(*)::integer, count(distinct t.dimensao)::integer
    into atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) e(id)
  join public.termos t on t.id = e.id and t.status = 'aprovado';

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

comment on function public.similares_da_peca_amplo(text[], integer, numeric) is
  'A33: amplia conjuntos menores que oito, preservando categoria e motivo de estampa; declara a dimensão relaxada.';

revoke all on function public.similares_da_peca_amplo(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca_amplo(text[], integer, numeric)
  to anon, authenticated;
