-- A funcao passa a rodar com os privilegios do DONO, e nao os de quem chama.
--
-- POR QUE, e por que isso NAO afrouxa a RLS:
--
-- O app entra como `anon`, que por desenho (migracao 0001) so enxerga
-- `termos`, `series_semanais`, `indices_semanais`, `eventos_da_semana`,
-- `cobertura_por_celula` e `curva_tamanhos`. `produtos`, `marcas` e
-- `produto_termos` sao invisiveis para ele -- e e assim que deve continuar: a
-- RLS existe para o app nao poder baixar o painel inteiro.
--
-- Sem `security definer`, a funcao herda essa cegueira e o PostgREST devolve
-- 401. Com ela, o app ganha uma JANELA CONTROLADA: recebe exatamente o que a
-- §29 manda mostrar -- marca, titulo, url publica, preco, remarcacao e estado
-- da grade, de no maximo `limite` pecas -- e nada mais. Continua sem poder
-- listar as tabelas, filtrar por marca ou paginar o catalogo.
--
-- E o dado devolvido e publico por natureza: sao pecas a venda em loja aberta,
-- e o cartao leva o link para a pagina original, que e o que a regra 3 exige.
--
-- `set search_path` ja esta fixado, que e a protecao padrao contra sequestro
-- de resolucao de nome em funcao com privilegio elevado.
alter function public.similares_da_peca(text[], integer, numeric) security definer;
alter function public.grade_em_texto(jsonb) security definer;

-- O teto de `limite` deixa de ser confianca no cliente e vira regra da funcao.
create or replace function public.similares_da_peca(
  termos text[],
  limite integer default 12,
  preco_alvo numeric default null)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with parametros as (
    select coalesce(array_length(termos, 1), 0) as pedidos,
           greatest(1, ceil(0.7 * coalesce(array_length(termos, 1), 0))::int) as minimo,
           -- Teto de 24 pecas por chamada: a §29 mostra um punhado, e sem teto
           -- a funcao viraria um jeito de paginar o catalogo por fora da RLS.
           least(greatest(coalesce(limite, 12), 1), 24) as teto
  ),
  candidatos as (
    select pt.produto_id, count(distinct pt.termo_id) as em_comum
    from produto_termos pt
    where pt.termo_id = any (termos)
    group by pt.produto_id
    having count(distinct pt.termo_id) >= (select minimo from parametros)
  ),
  sim as (
    select p.id, p.titulo, p.url, p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca, c.em_comum,
           p.ultima_grade is not null as tem_grade,
           g.quebrada, g.esgotada
    from candidatos c
    join produtos p on p.id = c.produto_id
    join marcas   m on m.id = p.marca_id
    cross join lateral (
      select bool_or(value = 'false'::jsonb)      as quebrada,
             not bool_or(value = 'true'::jsonb)   as esgotada
      from jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb))
    ) g
    where p.segmento is not null
  ),
  resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas',    count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'minimo_em_comum',   (select minimo  from parametros),
      'n_com_todos', count(*) filter (where em_comum = (select pedidos from parametros)),
      'com_preco',   count(*) filter (where preco is not null),
      'pct_preco_cheio', case when count(*) filter (where preco is not null) > 0
        then round(100.0 * count(*) filter (where preco is not null and preco >= coalesce(preco_de, preco))
                   / count(*) filter (where preco is not null), 1) end,
      'pct_grade_quebrada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where quebrada)
                   / count(*) filter (where tem_grade), 1) end,
      'pct_esgotada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where tem_grade and esgotada)
                   / count(*) filter (where tem_grade), 1) end,
      'preco_min', min(preco), 'preco_max', max(preco),
      'preco_mediana', percentile_cont(0.5) within group (order by preco),
      'percentil_do_alvo', case
        when preco_alvo is null or count(*) filter (where preco is not null) = 0 then null
        else round(100.0 * count(*) filter (where preco is not null and preco <= preco_alvo)
                   / count(*) filter (where preco is not null), 0) end,
      'exibidos', least((select teto from parametros), count(*))
    ) as j
    from sim
  ),
  ordenado as (
    select *, row_number() over (partition by marca order by em_comum desc, id) as posicao_na_marca
    from sim
  ),
  amostra as (
    select jsonb_agg(jsonb_build_object(
      'id', id, 'marca', marca, 'papel_da_marca', papel_da_marca,
      'titulo', titulo, 'url', url,
      'preco', preco, 'preco_de', preco_de,
      'queda_pct', case when preco_de is not null and preco is not null
                         and preco_de > 0 and preco < preco_de
                    then round(100.0 * (preco_de - preco) / preco_de, 1) end,
      'em_comum', em_comum,
      'grade', public.grade_em_texto(ultima_grade))
      order by posicao_na_marca, em_comum desc, id) as j
    from (select * from ordenado order by posicao_na_marca, em_comum desc, id
          limit (select teto from parametros)) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas',  coalesce((select j from amostra), '[]'::jsonb));
$function$;

grant execute on function public.similares_da_peca(text[], integer, numeric) to anon, authenticated;
grant execute on function public.grade_em_texto(jsonb) to anon, authenticated;;
