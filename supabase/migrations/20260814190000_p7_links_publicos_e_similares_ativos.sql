-- P7: links que abrem na loja pública e similares que ainda podem ser usados.
-- A auditoria de 14/08/2026 visitou 262 destinos reais. Ela encontrou o host
-- administrativo da Maria Filó, produtos removidos e um produto esgotado.

-- Trocar só o host NÃO resolve, e foi medido: numa amostra de 14/08/2026, das
-- 10 URLs reescritas apenas 1 abriu uma página de produto, contra 5 de 5 das
-- que já nasceram públicas. O slug interno da VTEX não existe na vitrine.
-- Reescrever daria um destino pior que o atual: responde 200, com canonical,
-- então passa por qualquer verificação automática -- e entrega página em branco
-- ao usuário. Enquanto o coletor não reresolver essas 205 linhas antigas, o
-- link é escondido. Card sem botão é honesto; botão que abre nada, não.
create or replace function public.url_publica_produto(url text, marca text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select case
    when url is null then null
    when marca = 'Maria Filo'
     and url like 'https://mariafilo.vtexcommercestable.com.br/%'
      then null
    else url
  end;
$function$;

revoke all on function public.url_publica_produto(text, text) from public;

create or replace function public.eventos_recentes(
  tipo_evento text,
  limite integer default 200
)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with selecionados as materialized (
    select e.id, e.produto_id, e.tipo, e.data, e.detalhe
    from public.eventos e
    join public.produtos p on p.id = e.produto_id
    where e.tipo = $1
      and $1 in ('reposicao', 'remarcacao', 'saida_de_linha')
      and p.segmento = 'feminino_casual_br'
    order by e.data desc, e.id desc
    limit least(greatest(coalesce($2, 200), 1), 400)
  ), legiveis as (
    select e.id,
           e.tipo,
           e.data,
           (e.data - ((extract(isodow from e.data))::integer - 1)) as semana,
           m.nome as marca,
           p.titulo as peca,
           case when p.ultimo_snapshot_em >= current_date - 14
             then public.url_publica_produto(p.url, m.nome)
             else null end as url_da_peca,
           p.imagem_url as imagem,
           e.detalhe,
           (select count(*)::integer
              from public.eventos h
             where h.produto_id = e.produto_id
               and h.tipo = e.tipo
               and (h.data, h.id) <= (e.data, e.id)) as ordinal,
           nullif(e.data - (
             select min(h.data)
             from public.eventos h
             where h.produto_id = e.produto_id and h.tipo = e.tipo
           ), 0) as dias_desde_a_primeira
    from selecionados e
    join public.produtos p on p.id = e.produto_id
    join public.marcas m on m.id = p.marca_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'tipo', tipo,
    'data', data,
    'semana', semana,
    'marca', marca,
    'peca', peca,
    'url_da_peca', url_da_peca,
    'imagem', imagem,
    'detalhe', detalhe,
    'ordinal', ordinal,
    'dias_desde_a_primeira', dias_desde_a_primeira
  ) order by data desc, id desc), '[]'::jsonb)
  from legiveis;
$function$;

revoke all on function public.eventos_recentes(text, integer) from public;
grant execute on function public.eventos_recentes(text, integer)
  to anon, authenticated;

create or replace function public.similares_da_peca(
  termos text[],
  limite integer default 12,
  preco_alvo numeric default null)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with entrada as (
    select coalesce(array_agg(a.termo_id order by a.primeira_posicao), '{}'::text[])
             as filtrados
    from (
      select e.termo_id, min(e.posicao) as primeira_posicao
      from unnest(coalesce($1, '{}'::text[])) with ordinality e(termo_id, posicao)
      join public.termos t
        on t.id = e.termo_id and t.status = 'aprovado'
      group by e.termo_id
      order by min(e.posicao)
      limit 12
    ) a
  ), parametros as (
    select filtrados,
           cardinality(filtrados) as pedidos,
           greatest(1, ceil(0.7 * cardinality(filtrados))::int) as minimo,
           least(greatest(coalesce($2, 12), 1), 24) as teto
    from entrada
  ), candidatos as (
    select pt.produto_id, count(distinct pt.termo_id) as em_comum
    from public.produto_termos pt
    cross join parametros par
    where pt.termo_id = any(par.filtrados)
    group by pt.produto_id, par.minimo
    having count(distinct pt.termo_id) >= par.minimo
  ), sim as (
    select p.id, p.titulo,
           public.url_publica_produto(p.url, m.nome) as url,
           p.imagem_url as imagem,
           p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca, c.em_comum,
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
    where p.segmento = 'feminino_casual_br'
      and p.ultimo_snapshot_em >= current_date - 14
      and coalesce(g.esgotada, false) = false
  ), resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas', count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'minimo_em_comum', (select minimo from parametros),
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
      partition by marca order by em_comum desc, id) as posicao_na_marca
    from sim
  ), amostra as (
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'marca', marca,
      'papel_da_marca', papel_da_marca,
      'titulo', titulo,
      'url', url,
      'imagem', imagem,
      'preco', preco,
      'preco_de', preco_de,
      'queda_pct', case when preco_de is not null and preco is not null
                         and preco_de > 0 and preco < preco_de
                    then round(100.0 * (preco_de - preco) / preco_de, 1) end,
      'em_comum', em_comum,
      'grade', public.grade_em_texto(ultima_grade))
      order by posicao_na_marca, em_comum desc, id) as j
    from (
      select * from ordenado
      order by posicao_na_marca, em_comum desc, id
      limit (select teto from parametros)
    ) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas', coalesce((select j from amostra), '[]'::jsonb));
$function$;

revoke all on function public.similares_da_peca(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca(text[], integer, numeric)
  to anon, authenticated;

comment on function public.similares_da_peca(text[], integer, numeric) is
  'P7: similares ativos nas últimas duas semanas, não esgotados e com URL pública canônica.';
