-- A40: amplia o catálogo de análogos sem reescrever o painel congelado.
--
-- As marcas candidatas vivem em `catalogo_candidato_br`: podem aparecer com
-- foto, preço e fonte nos similares, mas não entram em `feminino_casual_br`,
-- portanto não alteram share, cobertura, raridade ou z-score no meio da
-- temporada. A entrada na coorte medida continua sendo uma virada explícita.

create or replace function public.similares_da_peca(termos text[],
                                                    limite integer default 12,
                                                    preco_alvo numeric default null)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with entrada as (
    select e.termo_id, min(e.posicao) as primeira_posicao,
           min(t.dimensao) as dimensao
    from unnest(coalesce($1, '{}'::text[])) with ordinality e(termo_id, posicao)
    join public.termos t
      on t.id = e.termo_id and t.status = 'aprovado'
    group by e.termo_id
    order by min(e.posicao)
    limit 12
  ), parametros as (
    select count(*)::int as pedidos,
           count(distinct dimensao)::int as dimensoes_pedidas,
           greatest(1, ceil(0.7 * count(distinct dimensao))::int) as minimo_base,
           least(greatest(coalesce($2, 12), 1), 24) as teto,
           coalesce(array_agg(termo_id order by primeira_posicao)
             filter (where dimensao = 'categoria'), '{}'::text[]) as categorias
    from entrada
  ), casamentos as (
    select pt.produto_id,
           count(distinct pt.termo_id)::int as em_comum,
           count(distinct e.dimensao)::int as dimensoes_em_comum,
           array_agg(distinct pt.termo_id) as termos_em_comum,
           bool_or(e.dimensao = 'categoria') as tem_categoria
    from public.produto_termos pt
    join entrada e on e.termo_id = pt.termo_id
    group by pt.produto_id
  ), elegiveis as (
    select c.*
    from casamentos c
    join public.produtos p on p.id = c.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    cross join parametros par
    where p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em >= current_date - 7
      and (cardinality(par.categorias) = 0 or c.tem_categoria)
  ), nivel_escolhido as (
    select coalesce(max(nivel) filter (where existe), 1)::int as minimo
    from parametros par
    cross join lateral generate_series(par.minimo_base, 1, -1) nivel
    cross join lateral (
      select exists(select 1 from elegiveis e
                    where e.dimensoes_em_comum >= nivel) as existe
    ) x
  ), candidatos as (
    select e.*
    from elegiveis e cross join nivel_escolhido n
    where e.dimensoes_em_comum >= n.minimo
  ), sim as (
    select p.id, p.titulo,
           public.url_publica_produto(p.url, m.nome) as url,
           p.imagem_url as imagem,
           p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca,
           c.em_comum, c.dimensoes_em_comum, c.termos_em_comum,
           p.ultima_grade is not null as tem_grade,
           g.quebrada, g.esgotada
    from candidatos c
    join public.produtos p on p.id = c.produto_id
    join public.marcas m on m.id = p.marca_id
    cross join lateral (
      select bool_or(value = 'false'::jsonb) as quebrada,
             not bool_or(value = 'true'::jsonb) as esgotada
      from jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb))
    ) g
    where coalesce(g.esgotada, false) = false
  ), resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas', count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'dimensoes_pedidas', (select dimensoes_pedidas from parametros),
      'minimo_em_comum', coalesce(min(em_comum), 0),
      'minimo_dimensoes', (select minimo from nivel_escolhido),
      'n_com_todos', count(*) filter (
        where em_comum = (select pedidos from parametros)),
      'com_preco', count(*) filter (where preco is not null),
      'pct_preco_cheio', case when count(*) filter (where preco is not null) > 0
        then round(100.0 * count(*) filter (
               where preco is not null and preco >= coalesce(preco_de, preco))
             / count(*) filter (where preco is not null), 1) end,
      'pct_grade_quebrada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where quebrada)
             / count(*) filter (where tem_grade), 1) end,
      'pct_esgotada', 0,
      'preco_min', min(preco),
      'preco_max', max(preco),
      'preco_mediana', percentile_cont(0.5) within group (order by preco),
      'percentil_do_alvo', case
        when $3 is null or count(*) filter (where preco is not null) = 0 then null
        else round(100.0 * count(*) filter (where preco is not null and preco <= $3)
             / count(*) filter (where preco is not null), 0) end,
      'exibidos', least((select teto from parametros), count(*))
    ) as j from sim
  ), ordenado as (
    select *, row_number() over (
      partition by marca order by dimensoes_em_comum desc, em_comum desc, id
    ) as posicao_na_marca
    from sim
  ), amostra as (
    select jsonb_agg(jsonb_build_object(
      'id', id, 'marca', marca, 'papel_da_marca', papel_da_marca,
      'titulo', titulo, 'url', url, 'imagem', imagem,
      'preco', preco, 'preco_de', preco_de,
      'queda_pct', case when preco_de is not null and preco is not null
                         and preco_de > 0 and preco < preco_de
                    then round(100.0 * (preco_de - preco) / preco_de, 1) end,
      'em_comum', em_comum,
      'termos_em_comum', to_jsonb(termos_em_comum),
      'grade', public.grade_em_texto(ultima_grade))
      order by dimensoes_em_comum desc, em_comum desc, posicao_na_marca, id) as j
    from (
      select * from ordenado
      order by dimensoes_em_comum desc, em_comum desc, posicao_na_marca, id
      limit (select teto from parametros)
    ) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas', coalesce((select j from amostra), '[]'::jsonb));
$function$;

comment on function public.similares_da_peca(text[], integer, numeric) is
  'A40: A28 sobre coorte medida + catálogo candidato; candidatos ampliam análogos e nunca as séries do painel.';

revoke all on function public.similares_da_peca(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca(text[], integer, numeric)
  to anon, authenticated;
