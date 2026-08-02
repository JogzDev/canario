create or replace function public.similares_da_peca(
  termos text[],
  limite integer default 12,
  preco_alvo numeric default null)
returns jsonb
language sql stable
set search_path to 'public', 'pg_temp'
as $function$
  -- O LIMIAR DE SEMELHANCA, e por que nao e `n-1`.
  --
  -- A primeira versao exigia "todos menos um" e devolveu 3.989 similares para
  -- "vestido + floral + midi" -- porque com tres atributos, tolerar uma
  -- diferenca deixa entrar todo vestido midi liso e todo floral curto. Medido:
  -- 233 pecas tem os TRES, e 3.816 tem apenas dois. Chamar as 3.816 de
  -- "parecidas" esvazia a palavra, e o §29 promete "as pecas mais parecidas".
  --
  -- A regra passa a ser 70% dos atributos marcados, arredondado para cima:
  --
  --     2 atributos -> exige 2      5 atributos -> exige 4
  --     3 atributos -> exige 3      6 atributos -> exige 5
  --     4 atributos -> exige 3      8 atributos -> exige 6
  --
  -- Aperta onde a peca e descrita por poucos atributos (onde cada um pesa
  -- muito) e afrouxa onde ha muitos (onde exigir todos zeraria o resultado).
  -- A tela DECLARA o limiar: "pecas com pelo menos 3 dos 4 atributos".
  with parametros as (
    select coalesce(array_length(termos, 1), 0) as pedidos,
           greatest(1, ceil(0.7 * coalesce(array_length(termos, 1), 0))::int) as minimo
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
           p.ultimo_preco_original as preco_de,
           public.grade_em_texto(p.ultima_grade) as grade,
           p.ultima_grade is not null as tem_grade,
           m.nome as marca, m.papel as papel_da_marca,
           c.em_comum
    from candidatos c
    join produtos p on p.id = c.produto_id
    join marcas   m on m.id = p.marca_id
    where p.segmento is not null
  ),
  resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas',    count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'minimo_em_comum',   (select minimo  from parametros),
      -- Quantos batem em TODOS: e o numero mais forte, e a tela mostra os dois.
      'n_com_todos', count(*) filter (where em_comum = (select pedidos from parametros)),
      'com_preco',   count(*) filter (where preco is not null),
      'pct_preco_cheio', case when count(*) filter (where preco is not null) > 0
        then round(100.0 * count(*) filter (where preco is not null and preco >= coalesce(preco_de, preco))
                   / count(*) filter (where preco is not null), 1) end,
      'pct_grade_quebrada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where (grade->>'quebrada')::boolean)
                   / count(*) filter (where tem_grade), 1) end,
      'pct_esgotada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where (grade->>'esgotada')::boolean)
                   / count(*) filter (where tem_grade), 1) end,
      'preco_min', min(preco), 'preco_max', max(preco),
      'preco_mediana', percentile_cont(0.5) within group (order by preco),
      'percentil_do_alvo', case
        when preco_alvo is null or count(*) filter (where preco is not null) = 0 then null
        else round(100.0 * count(*) filter (where preco is not null and preco <= preco_alvo)
                   / count(*) filter (where preco is not null), 0) end,
      'exibidos', least(limite, count(*))
    ) as j
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
      'grade', grade) order by em_comum desc, id) as j
    from (select * from sim order by em_comum desc, id limit limite) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas',  coalesce((select j from amostra), '[]'::jsonb));
$function$;

grant execute on function public.similares_da_peca(text[], integer, numeric) to anon, authenticated;;
