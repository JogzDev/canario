-- A66: a leitura específica filtra pela taxonomia o que a taxonomia sabe.
--
-- Na A64 tudo o que não era categoria virava texto no nome da peça. Medido em
-- 24/09/2026 com "saia midi plissada": uma rodada escolheu os sinais
-- "plissada, pregas" e leu 11 saias certas; a seguinte escolheu "saia midi"
-- e recebeu 405 candidatas, das quais o verificador só vê 40. "Midi" é termo
-- da taxonomia (comprimento), ligado às peças pelo motor; procurá-lo no texto
-- é jogar fora o que já está resolvido.
--
-- Agora a interpretação devolve `atributos` (ids aprovados de comprimento,
-- cor, estampa, tecido, silhueta, cintura e estética) e a busca exige todos
-- eles, como exige a categoria. Os sinais de texto ficam para a construção
-- que a taxonomia não nomeia (plissada, abotoamento duplo) e podem faltar
-- quando a taxonomia cobre o pedido inteiro ("saia midi preta").
--
-- A assinatura muda (entra `p_atributos`), então a versão da A64 sai: a única
-- chamadora é a Edge Function `ler-peca`, publicada junto.

drop function if exists public.candidatas_da_leitura(text[], text[], text[], integer);

create or replace function public.candidatas_da_leitura(
  p_categorias text[],
  p_atributos text[],
  p_sinais text[],
  p_vetos text[] default '{}',
  p_limite integer default 60)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  painel date;
  sinais text[] := public._texto_da_leitura(p_sinais);
  vetos text[] := public._texto_da_leitura(p_vetos);
  atributos text[] := coalesce(p_atributos, '{}');
  limite integer := least(greatest(coalesce(p_limite, 60), 1), 100);
  resultado jsonb;
begin
  if coalesce(cardinality(p_sinais), 0) > 12 or coalesce(cardinality(p_vetos), 0) > 12
     or coalesce(cardinality(p_categorias), 0) > 8 or cardinality(atributos) > 6 then
    raise exception 'leitura: no maximo 12 sinais, 12 vetos, 8 categorias e 6 atributos'
      using errcode = '22023';
  end if;
  -- Sem sinal de texto a busca precisa de outro recorte: categoria ou atributo.
  if cardinality(sinais) = 0
     and (coalesce(cardinality(p_categorias), 0) = 0 or cardinality(atributos) = 0) then
    raise exception 'leitura: sem sinal de texto, informe categoria e atributo'
      using errcode = '22023';
  end if;

  select o.observado_em into painel
  from public.observacoes_publicadas_do_painel o
  where o.segmento = 'feminino_casual_br';
  if painel is null then
    return jsonb_build_object('painel_observado_em', null, 'total', 0, 'pecas', '[]'::jsonb);
  end if;

  with ativos as (
    select p.id, p.titulo, p.url, p.imagem_url, p.marca_id,
           p.ultimo_preco_atual, p.ultimo_preco_original,
           ep.ultimo_avistamento_em,
           lower(public.unaccent(p.titulo)) as t
    from public.produtos p
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    where p.segmento = 'feminino_casual_br'
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em between painel - 7 and painel
      and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                       where ca.produto_id = p.id)
      and (coalesce(cardinality(p_categorias), 0) = 0
           or exists (select 1 from public.produto_termos pt
                       where pt.produto_id = p.id
                         and pt.termo_id = any (p_categorias)))
      -- Todos os atributos pedidos, cada um ligado a peca pelo motor.
      and not exists (select 1 from unnest(atributos) a
                       where not exists (select 1 from public.produto_termos pt
                                          where pt.produto_id = p.id and pt.termo_id = a))
  ), casados as (
    select a.*,
           (select count(*) from unnest(sinais) s where a.t like s) as forca
    from ativos a
    where (cardinality(sinais) = 0 or a.t like any (sinais))
      and not (a.t like any (vetos))
  )
  select jsonb_build_object(
    'painel_observado_em', painel,
    'total', (select count(*) from casados),
    'pecas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'titulo', c.titulo, 'marca', m.nome,
               'preco', c.ultimo_preco_atual, 'preco_original', c.ultimo_preco_original,
               'imagem_url', c.imagem_url,
               'url', public.url_publica_produto(c.url, m.nome),
               'visto_em', c.ultimo_avistamento_em, 'sinais_casados', c.forca)
             order by c.forca desc, c.ultimo_avistamento_em desc, c.id)
      from (select * from casados
            order by forca desc, ultimo_avistamento_em desc, id
            limit limite) c
      join public.marcas m on m.id = c.marca_id), '[]'::jsonb))
  into resultado;
  return resultado;
end;
$function$;

revoke all on function public.candidatas_da_leitura(text[], text[], text[], text[], integer) from public, anon, authenticated;
grant execute on function public.candidatas_da_leitura(text[], text[], text[], text[], integer) to service_role;

comment on function public.candidatas_da_leitura(text[], text[], text[], text[], integer) is
  'A66: pecas ativas do painel publicado com a categoria e TODOS os atributos da taxonomia pedidos, e que casam com os sinais de construcao (texto escapado, nunca padrao) e com nenhum veto.';
