-- 0009 -- Bloco de similares (§29), e o parágrafo-resumo que depende dele.
--
-- ===========================================================================
-- POR QUE ISTO É O CORAÇÃO DO PROJETO, E NÃO UM BLOCO A MAIS
-- ===========================================================================
--
-- A §5 proíbe previsão de venda, score de peça e veredito. E lista, no mesmo
-- lugar, o que o app entrega **no lugar disso**. O primeiro item da lista é:
--
--     "análogos descritivos (as 3 peças mais parecidas e o desfecho delas)"
--
-- E a §29 monta o parágrafo-resumo — a primeira coisa que o comprador lê —
-- inteiramente sobre eles:
--
--     "No painel de {n_marcas} marcas, encontrei {n_similares} similares:
--      {pct_preco_cheio}% a preço cheio e {pct_grade_quebrada}% com grade
--      quebrando {formato}."
--
-- Ou seja: sem similares não existe bloco 1 da §29. O índice do cluster (K5)
-- é o bloco 3, e vem depois.
--
-- ===========================================================================
-- DUAS DECISÕES DE MÉTODO
-- ===========================================================================
--
-- 1. **O resumo é sobre TODOS os similares; a lista é uma amostra.**
--    Uma peça "vestido + floral + midi" tem 233 similares no painel. Mostrar 12
--    cartões e calcular a porcentagem sobre esses 12 seria estatística de
--    vitrine. O `resumo` percorre o conjunto inteiro e a tela declara quantos
--    são contra quantos aparecem.
--
-- 2. **Similaridade é contagem de atributos em comum, e o mínimo é declarado.**
--    Nada de distância inventada com peso arbitrário. Exige-se pelo menos
--    `n-1` dos atributos pedidos (tolera uma diferença), com piso de 1. É
--    grosseiro de propósito: é explicável ao usuário em uma linha, e a §29
--    pede o caminho até a origem em todo número.
--
-- ===========================================================================
-- RESTRIÇÃO QUE MANDOU NO DESENHO
-- ===========================================================================
--
-- Esta função é chamada **pelo app, ao vivo**, com o papel `anon`, cujo
-- `statement_timeout` é de **3 segundos**. Não é um lote noturno como a curva
-- de tamanhos (que leva 64s e roda no `service_role`). Por isso:
--
--   * o índice `produto_termos_por_termo` é pré-requisito, não otimização;
--   * o corte por `limite` acontece antes de qualquer trabalho por peça;
--   * o estado da grade é lido de `produtos.ultima_grade`, que já está
--     materializado, em vez de reconstruído de `snapshots`.

-- ---------------------------------------------------------------------------
-- Estado da grade de uma peça, em uma linha legível.
--
-- Reaproveita `ordem_do_tamanho()` da §24: os tamanhos saem na ordem da escada
-- da própria peça, e nunca convertidos entre marcas.
-- ---------------------------------------------------------------------------
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
  'Estado da grade de uma peça: quantos degraus, quantos disponíveis e quais '
  'faltam, na ordem da escada da própria peça (§24).';

-- ---------------------------------------------------------------------------
-- Os similares, com o resumo por cima.
-- ---------------------------------------------------------------------------
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
  -- Tolera uma diferença, com piso de 1. Com um atributo só, exige aquele.
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

  -- RESUMO sobre o conjunto INTEIRO. É o que alimenta o parágrafo da §29.
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
    -- §5 autoriza percentil de preço como substituto da previsão proibida.
    'percentil_do_alvo', case
      when preco_alvo is null or count(*) filter (where preco is not null) = 0 then null
      else round(100.0 * count(*) filter (where preco is not null and preco <= preco_alvo)
                 / count(*) filter (where preco is not null), 0) end,
    'exibidos', least(limite, count(*))
  ) into resumo
  from _sim;

  -- A AMOSTRA que vira cartão. Mais parecidas primeiro; empate resolvido pelo
  -- id, para a lista não dançar entre duas aberturas da mesma tela.
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
  'Peças do painel que compartilham atributos com a peça analisada (§29). O '
  'resumo é sobre TODOS os similares; a lista de peças é uma amostra ordenada '
  'por atributos em comum. Chamada ao vivo pelo app, que roda como `anon` com '
  'limite de 3 segundos.';

grant execute on function public.similares_da_peca(text[], integer, numeric)
  to anon, authenticated;
grant execute on function public.grade_em_texto(jsonb) to anon, authenticated;
