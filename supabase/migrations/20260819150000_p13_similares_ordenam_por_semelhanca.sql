-- P13: o bloco de similares passa a liderar com as peças mais parecidas.
--
-- O QUE UM TESTADOR VIU EM 19/08/2026
-- ==================================
--
-- Uma camiseta listrada foi enviada com `listra` marcada, e metade das peças
-- "semelhantes" exibidas não tinha listra nenhuma. Reproduzido contra os dados
-- de produção com `['camisa','listra','branco_cru','algodao']`:
--
--   atributos pedidos          4
--   mínimo exigido             3      (regra dos 70%)
--   candidatos                78
--   com os QUATRO atributos    2
--   exibidas                  12
--   exibidas SEM listra        6      -- metade do bloco
--
-- DUAS CAUSAS, E ESTA MIGRAÇÃO ATACA UMA
-- ======================================
--
-- 1. `minimo = ceil(0.7 * pedidos)` deixa cair qualquer atributo, inclusive o
--    mais visível. Com 4 marcados, um deles sobra -- e nada garante que o que
--    sobra seja o menos importante. Isto NÃO é mexido aqui: baixar o corte para
--    "todos" deixaria o bloco quase vazio (2 peças, no exemplo acima), e qual
--    atributo pode ou não ser dispensado é decisão de método, não de código.
--
-- 2. A ordenação colocava a variedade de marca ANTES da semelhança:
--
--      order by posicao_na_marca, em_comum desc, id
--
--    `posicao_na_marca` é o round-robin entre marcas. Com ele na frente, a
--    melhor peça de cada marca ocupa as primeiras posições -- mesmo quando é um
--    casamento 3 de 4 e existe um 4 de 4 esperando atrás. Num bloco que se chama
--    "peças semelhantes", semelhança tem de vir primeiro.
--
-- A TROCA
--
--      order by em_comum desc, posicao_na_marca, id
--
-- As peças que batem em tudo lideram. A variedade de marca continua existindo,
-- como critério de desempate DENTRO do mesmo nível de semelhança -- então duas
-- peças igualmente parecidas ainda vêm de marcas diferentes, que era o ganho
-- real do round-robin. O que se perde é a diversidade forçada no topo, e ela
-- estava sendo comprada com relevância.
--
-- Esta função é `stable` e só lê: a correção chega a quem já tem o app
-- instalado, sem esperar atualização na App Store.
--
-- Reverter: voltar `posicao_na_marca` para a frente nos dois `order by`.

create or replace function public.similares_da_peca(termos text[],
                                                    limite integer default 12,
                                                    preco_alvo numeric default null)
returns jsonb
language sql
stable security definer
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
    -- P13: `em_comum` na frente. Bloco chamado "peças semelhantes" ordena por
    -- semelhança; a variedade de marca desempata dentro do mesmo nível.
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
      order by em_comum desc, posicao_na_marca, id) as j
    from (
      select * from ordenado
      order by em_comum desc, posicao_na_marca, id
      limit (select teto from parametros)
    ) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas', coalesce((select j from amostra), '[]'::jsonb));
$function$;

comment on function public.similares_da_peca(text[], integer, numeric) is
  'Peças semelhantes por atributos em comum (§29). P13: ordena por semelhança e usa a variedade de marca só como desempate -- antes o round-robin de marca vinha primeiro e empurrava casamento parcial para o topo.';
