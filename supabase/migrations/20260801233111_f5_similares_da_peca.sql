create or replace function public.grade_em_texto(grade jsonb)
returns jsonb
language sql immutable
set search_path to 'public', 'pg_temp'
as $$
  with itens as (
    select o.rotulo, o.ordem, (t.value = 'true'::jsonb) as disponivel
    from jsonb_each(coalesce(grade, '{}'::jsonb)) t
    cross join lateral public.ordem_do_tamanho(t.key) o
    where o.sistema is not null and o.ordem is not null
  )
  select jsonb_build_object(
    'degraus',     count(*),
    'disponiveis', count(*) filter (where disponivel),
    'faltando',    coalesce(jsonb_agg(rotulo order by ordem)
                            filter (where not disponivel), '[]'::jsonb),
    'quebrada',    count(*) filter (where not disponivel) > 0,
    'esgotada',    count(*) > 0 and count(*) filter (where disponivel) = 0
  )
  from itens;
$$;

comment on function public.grade_em_texto is
  'Estado da grade de uma peca: quantos degraus, quantos disponiveis e quais faltam, na ordem da escada da propria peca (§24).';

create or replace function public.similares_da_peca(
  termos text[],
  limite integer default 12,
  preco_alvo numeric default null)
returns jsonb
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  pedidos integer := coalesce(array_length(termos, 1), 0);
  minimo  integer;
  resumo  jsonb;
  pecas   jsonb;
begin
  if pedidos = 0 then
    return jsonb_build_object('resumo', null, 'pecas', '[]'::jsonb);
  end if;
  minimo := greatest(1, pedidos - 1);

  create temp table _sim on commit drop as
  select p.id, p.titulo, p.url, p.ultimo_preco_atual as preco,
         p.ultimo_preco_original as preco_de, p.ultima_grade,
         m.nome as marca, m.papel as papel_da_marca,
         c.em_comum
  from (
    select pt.produto_id, count(distinct pt.termo_id) as em_comum
    from produto_termos pt
    where pt.termo_id = any (termos)
    group by pt.produto_id
    having count(distinct pt.termo_id) >= minimo
  ) c
  join produtos p on p.id = c.produto_id
  join marcas   m on m.id = p.marca_id
  where p.segmento is not null;

  select jsonb_build_object(
    'n_similares',  count(*),
    'n_marcas',     count(distinct marca),
    'atributos_pedidos', pedidos,
    'minimo_em_comum',   minimo,
    'com_preco',    count(*) filter (where preco is not null),
    'pct_preco_cheio', case when count(*) filter (where preco is not null) > 0
      then round(100.0 * count(*) filter (where preco is not null and preco >= coalesce(preco_de, preco))
                 / count(*) filter (where preco is not null), 1) end,
    'pct_grade_quebrada', case when count(*) filter (where ultima_grade is not null) > 0
      then round(100.0 * count(*) filter (where (grade_em_texto(ultima_grade)->>'quebrada')::boolean)
                 / count(*) filter (where ultima_grade is not null), 1) end,
    'preco_min',    min(preco), 'preco_max', max(preco),
    'preco_mediana', percentile_cont(0.5) within group (order by preco),
    'percentil_do_alvo', case
      when preco_alvo is null or count(*) filter (where preco is not null) = 0 then null
      else round(100.0 * count(*) filter (where preco is not null and preco <= preco_alvo)
                 / count(*) filter (where preco is not null), 0) end,
    'exibidos', least(limite, count(*))
  ) into resumo
  from _sim;

  select coalesce(jsonb_agg(x order by x->>'ordem'), '[]'::jsonb) into pecas
  from (
    select jsonb_build_object(
      'id', s.id, 'marca', s.marca, 'papel_da_marca', s.papel_da_marca,
      'titulo', s.titulo, 'url', s.url,
      'preco', s.preco, 'preco_de', s.preco_de,
      'queda_pct', case when s.preco_de is not null and s.preco is not null
                         and s.preco_de > 0 and s.preco < s.preco_de
                    then round(100.0 * (s.preco_de - s.preco) / s.preco_de, 1) end,
      'em_comum', s.em_comum,
      'grade', grade_em_texto(s.ultima_grade),
      'ordem', lpad((1000 - s.em_comum)::text, 4, '0') || lpad(s.id::text, 12, '0')
    ) as x
    from _sim s
    order by s.em_comum desc, s.id
    limit limite
  ) t;

  return jsonb_build_object('resumo', resumo, 'pecas', pecas);
end;
$function$;

comment on function public.similares_da_peca is
  'Pecas do painel que compartilham atributos com a peca analisada (§29). O resumo e sobre TODOS os similares; a lista de pecas e uma amostra ordenada por atributos em comum. Chamada ao vivo pelo app, que roda como anon com limite de 3 segundos.';

grant execute on function public.similares_da_peca(text[], integer, numeric) to anon, authenticated;
grant execute on function public.grade_em_texto(jsonb) to anon, authenticated;;
