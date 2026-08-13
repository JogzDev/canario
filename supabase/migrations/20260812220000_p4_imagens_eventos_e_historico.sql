-- A19: fotos nos eventos, série dos atributos sem buraco artificial e hotlink
-- dos similares consolidado no estado final das funções públicas.

-- 1. Eventos: limitar ANTES de calcular ordinal. A view antiga calcula janelas
-- sobre todo o histórico e estoura o statement_timeout de 3 s da chave anon.
create index if not exists eventos_tipo_data_id_idx
  on public.eventos (tipo, data desc, id desc);
create index if not exists eventos_produto_tipo_data_id_idx
  on public.eventos (produto_id, tipo, data, id);

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
           p.url as url_da_peca,
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

comment on function public.eventos_recentes(text, integer) is
  'A19: reposições/remarcações recentes com foto hotlink A13. Limita eventos antes de calcular repetição para caber no timeout público.';

-- 2. Similares: consolida a foto do CDN da própria loja na definição final.
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
    select p.id, p.titulo, p.url, p.imagem_url as imagem,
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
      'pct_esgotada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where tem_grade and esgotada)
             / count(*) filter (where tem_grade), 1) end,
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

-- 3. Série: índice existe mesmo quando uma só fonte chegou; quem exige duas
-- fontes é o ESTADO direcional. O filtro antigo confundia as duas coisas e
-- apagava quase todo o gráfico. Agora o ponto fica e carrega a cobertura.
create or replace function public.serie_do_cluster(
  termos text[],
  semanas integer default 52
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  categoria_da_peca text;
  n_categorias integer;
  janela integer;
begin
  janela := least(greatest(coalesce(semanas, 52), 8), 260);
  if termos is null or array_length(termos, 1) is null then
    return jsonb_build_object('erro', 'nenhum atributo informado');
  end if;
  if array_length(termos, 1) > 12 then
    return jsonb_build_object('erro', 'atributos demais');
  end if;
  if exists (
    select 1
    from unnest(serie_do_cluster.termos) entrada(termo_id)
    left join public.termos t on t.id = entrada.termo_id
    where t.id is null or t.status <> 'aprovado'
  ) then
    return jsonb_build_object('erro', 'atributo fora da taxonomia aprovada');
  end if;

  select count(*), min(t.id) into n_categorias, categoria_da_peca
  from public.termos t
  where t.id = any(serie_do_cluster.termos)
    and t.status = 'aprovado'
    and t.dimensao = 'categoria';
  if coalesce(n_categorias, 0) <> 1 then
    categoria_da_peca := '(todas)';
  end if;

  return (
    with pedido as (
      select distinct unnest(serie_do_cluster.termos) as termo_id
    ), pesos as (
      select p.termo_id, r.peso
      from pedido p
      join public.raridade_do_atributo r
        on r.termo_id = p.termo_id
       and r.categoria = categoria_da_peca
      where r.peso is not null
    ), pontos as (
      select i.semana,
             sum(i.indice * w.peso) / nullif(sum(w.peso), 0) as indice,
             count(*)::integer as n_atributos,
             count(*) filter (where i.estado is not null)::integer
               as n_atributos_com_estado,
             min(i.n_pernas)::integer as n_pernas_min
      from public.indices_semanais i
      join pesos w on w.termo_id = i.termo_id
      where i.segmento = 'feminino_casual_br'
        and i.indice is not null
        and i.semana >= (current_date - (janela * 7))
      group by i.semana
    )
    select jsonb_build_object(
      'unidade', 'desvios contra a própria história de cada atributo',
      'categoria_usada', categoria_da_peca,
      'atributos_pedidos', coalesce(array_length(termos, 1), 0),
      'atributos_com_peso', (select count(*) from pesos),
      'semanas_pedidas', janela,
      'pontos', coalesce((select jsonb_agg(jsonb_build_object(
        'semana', semana,
        'indice', round(indice, 4),
        'n_atributos', n_atributos,
        'n_atributos_com_estado', n_atributos_com_estado,
        'n_pernas_min', n_pernas_min
      ) order by semana) from pontos), '[]'::jsonb),
      'obs', 'O índice pode existir com uma fonte; estado direcional exige duas. '
          || 'Cobertura por ponto fica explícita em n_atributos e n_pernas_min.'
    )
  );
end;
$function$;

revoke all on function public.serie_do_cluster(text[], integer) from public;
grant execute on function public.serie_do_cluster(text[], integer)
  to anon, authenticated;

comment on function public.serie_do_cluster(text[], integer) is
  'A19: série do índice dos atributos. Não apaga índice de uma fonte; expõe n_pernas_min e reserva a exigência de duas fontes ao estado.';
