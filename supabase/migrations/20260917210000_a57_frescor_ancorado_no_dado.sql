-- A57: frescor ancorado no dado, nao no calendario.
--
-- POR QUE
-- =======
--
-- Medido em 17/09/2026, com a coleta pausada desde 02/09:
--
--   select public.similares_da_peca(array['vestido','preto'], 3);
--   -> n_similares: 0
--
-- O painel tem 12.496 vestidos e 35.564 produtos ofertaveis. O que zerou a
-- resposta foi o portao de frescor `ep.ultimo_avistamento_em >= current_date -
-- 7`: em 09/09 ele passou a reprovar o painel INTEIRO, e desde entao o app
-- diz "nao encontrei nenhuma peca do painel com esses atributos". Isso e uma
-- afirmacao sobre o MERCADO quando a verdade e uma afirmacao sobre a NOSSA
-- COLETA. Pausa de coleta nao e ausencia de mercado.
--
-- A janela passa a ser ancorada no ultimo dia observado de CADA SEGMENTO
-- (`feminino_casual_br` e `catalogo_candidato_br` tem cadencias diferentes, e
-- uma data unica deixaria a mais nova reprovar a coorte da outra). Com coleta
-- saudavel, ancorar no dado e ancorar em `current_date` dao o mesmo conjunto;
-- com coleta parada, o app recebe o painel da ultima observacao E A IDADE
-- DELE, em vez de receber vazio. `observado_em` e `dias_desde_a_observacao`
-- entram no resumo para a tela declarar essa idade -- sem isso, a correcao
-- apenas trocaria uma frase falsa ("nao existe") por outra ("isto e de hoje").
--
-- O SEGUNDO DEFEITO, INDEPENDENTE DA PAUSA
-- ========================================
--
-- `eventos_recentes` decide o link da loja por `p.ultimo_snapshot_em`, uma
-- coluna que o coletor parou de escrever quando a A27 moveu o estado para
-- `estado_dos_produtos`. Ela esta congelada em 24/08 enquanto o estado real
-- vai a 02/09: o link teria sumido em 07/09 mesmo com a coleta de pe. Passa a
-- ler `estado_dos_produtos`, com a mesma ancora de dado.
--
-- POR QUE `_v2`, E NAO SUBSTITUIR NO LUGAR
-- ========================================
--
-- A primeira versao desta migration fazia `create or replace` em
-- `similares_da_peca`. Publicar isso junto com o app novo NAO e suficiente: o
-- aparelho de quem nao atualizou continua chamando a mesma funcao, e quem
-- decide a versao do app e a pessoa, nao nos. Pior, `similares_da_peca_amplo`
-- chama `similares_da_peca` por dentro -- trocar a segunda muda a primeira
-- sem que nada no nome dela diga isso.
--
-- Entao as funcoes antigas ficam INTACTAS, com o comportamento que os
-- aparelhos instalados esperam, e o comportamento novo nasce em
-- `similares_da_peca_v2` e `similares_da_peca_amplo_v2`. A ordem de
-- publicacao passa a ser backend primeiro, app depois -- que e a unica ordem
-- em que nenhuma versao ja instalada quebra.
--
-- O preco disso e duas definicoes quase iguais no banco. O preco de nao fazer
-- e mudar, sem aviso, o que um app que ninguem atualizou mostra na tela.
--
-- `eventos_recentes` E A EXCECAO, E COM MOTIVO
-- ============================================
--
-- Ela e substituida no lugar porque o CONTRATO nao muda -- mesmas chaves,
-- mesmos tipos -- e porque o que ela corrige e um link que sumiu para todo
-- mundo. Um app antigo ganha o link de volta; nenhum app antigo passa a
-- receber campo diferente do que le hoje.
--
-- O QUE NAO MUDA
-- ==============
--
-- Os prazos continuam os mesmos (7 dias de frescor, 14 dias para o link). O
-- portao de cobertura, o z-score, a raridade e os pesos nao sao tocados.
-- `produto_do_painel_por_url` fica como esta: a entrada por link saiu do app
-- na A47 e nenhuma tela a chama.
--
-- ZERO RESULTADO TAMBEM TEM PERIODO
-- =================================
--
-- `observado_em` e a data das PECAS DEVOLVIDAS: sem pecas, ela e nula, e a
-- tela ficaria sem saber de quando e o painel que respondeu "nao achei". O
-- resumo passa a carregar tambem as datas do PAINEL CONSULTADO
-- (`painel_observado_em`, `painel_dias_desde_a_observacao`), que existem
-- independentemente de casamento. Sem isso, "nenhuma peca com estes
-- atributos" e uma afirmacao sem data -- e uma afirmacao sem data sobre um
-- painel de duas semanas atras e uma afirmacao sobre hoje que ninguem mediu.
--
-- E A MAIS ANTIGA MANDA NO "AGORA"
-- ================================
--
-- `dias_desde_a_observacao` sozinho e a idade da peca MAIS NOVA do conjunto.
-- Uma peca vista ontem, ao lado de dezenove vistas ha quinze dias, faria a
-- resposta inteira passar por atual. Por isso entra
-- `dias_desde_a_observacao_mais_antiga`: quem decide se o conjunto pode ser
-- apresentado como atual e a ponta velha, nao a nova.

create or replace function public.similares_da_peca_v2(termos text[],
                                                    limite integer default 12,
                                                    preco_alvo numeric default null)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with painel as (
    -- A ancora e POR SEGMENTO. Uma data unica para os dois misturava coortes:
    -- se o catalogo candidato fosse observado depois, a data mais nova dele
    -- reprovaria o painel medido de novo -- o mesmo defeito que esta migration
    -- existe para corrigir, com outro disfarce.
    select p.segmento, max(ep.ultimo_avistamento_em) as observado_em
    from public.estado_dos_produtos ep
    join public.produtos p on p.id = ep.produto_id
    where p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
      and ep.ofertavel is true
    group by p.segmento
  ), entrada as (
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
    select c.*, ep.ultimo_avistamento_em as visto_em
    from casamentos c
    join public.produtos p on p.id = c.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    join painel pa on pa.segmento = p.segmento
    cross join parametros par
    where ep.ofertavel is true
      and ep.ultimo_avistamento_em >= pa.observado_em - 7
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
           c.visto_em,
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
      'exibidos', least((select teto from parametros), count(*)),
      -- A idade viaja com a resposta, medida NAS PECAS QUE ELA DEVOLVE: a
      -- tela precisa poder dizer "visto em 02/09, 15 dias atras" em vez de
      -- deixar o leitor supor que e de hoje. `observado_em` e a observacao
      -- mais nova entre as pecas mostradas, e `observado_mais_antigo_em` a
      -- mais velha -- as duas sustentam a frase, nenhuma data solta sustenta.
      'observado_em', max(visto_em),
      'observado_mais_antigo_em', min(visto_em),
      'dias_desde_a_observacao', (current_date - max(visto_em)),
      -- A ponta VELHA, que e quem decide se isto pode ser chamado de "agora".
      'dias_desde_a_observacao_mais_antiga', (current_date - min(visto_em)),
      -- A data do PAINEL CONSULTADO, que existe mesmo sem casamento nenhum:
      -- zero resultado tambem precisa declarar de quando e o painel que
      -- respondeu. E a ancora de `feminino_casual_br` e nao o maximo entre os
      -- segmentos: o catalogo candidato tem cadencia propria, e usar a data
      -- dele para carimbar uma resposta sobre o painel medido seria carimbar
      -- com o relogio de outra coorte.
      'painel_observado_em', (select observado_em from painel
                               where segmento = 'feminino_casual_br'),
      'painel_dias_desde_a_observacao',
        (select current_date - observado_em from painel
          where segmento = 'feminino_casual_br')
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
      'visto_em', visto_em,
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

comment on function public.similares_da_peca_v2(text[], integer, numeric) is
  'A57: A40 com frescor ancorado no ultimo dia observado de cada segmento; cada peca carrega visto_em e o resumo declara a idade do que devolveu e a do painel consultado. A versao sem sufixo fica como esta, para os aparelhos ja instalados.';

revoke all on function public.similares_da_peca_v2(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca_v2(text[], integer, numeric)
  to anon, authenticated;

-- O envelope que o app chama de verdade. Copia fiel da A48, com uma unica
-- diferenca: as duas tentativas caem em `similares_da_peca_v2`. Duplicar o
-- corpo e o preco de nao mexer no que os aparelhos instalados usam.
create or replace function public.similares_da_peca_amplo_v2(
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
  select count(*)::integer, count(distinct t.dimensao)::integer
    into atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) e(id)
  join public.termos t on t.id = e.id and t.status = 'aprovado';

  estrita := public.similares_da_peca_v2(termos, limite, preco_alvo);
  if jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) >= least(limite, 8) then
    return estrita;
  end if;

  select t.dimensao into dimensao_a_relaxar
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> 'categoria'
  group by t.dimensao
  order by array_position(
    array['estetica','comprimento','silhueta','cintura','tecido','cor','estampa'],
    t.dimensao) nulls last, min(e.posicao)
  limit 1;
  if dimensao_a_relaxar is null then return estrita; end if;

  select array_agg(e.id order by e.posicao)
    into termos_reduzidos
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> dimensao_a_relaxar;
  if cardinality(termos_reduzidos) = 0 then return estrita; end if;

  ampliada := public.similares_da_peca_v2(termos_reduzidos, limite, preco_alvo);
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

comment on function public.similares_da_peca_amplo_v2(text[], integer, numeric) is
  'A57: envelope da A48 apoiado em similares_da_peca_v2; a versao sem sufixo continua servindo os aparelhos ja instalados.';

revoke all on function public.similares_da_peca_amplo_v2(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca_amplo_v2(text[], integer, numeric)
  to anon, authenticated;

-- O link da loja volta a ler o estado que o coletor escreve.

create or replace function public.eventos_recentes(tipo_evento text,
                                                   limite integer default 200)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with painel as (
    select max(ep.ultimo_snapshot_em) as observado_em
    from public.estado_dos_produtos ep
    join public.produtos p on p.id = ep.produto_id
    where p.segmento = 'feminino_casual_br'
  ), selecionados as materialized (
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
           case when ep.ultimo_snapshot_em
                     >= (select observado_em from painel) - 14
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
    join public.estado_dos_produtos ep on ep.produto_id = p.id
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

comment on function public.eventos_recentes(text, integer) is
  'A57: link da loja lido de estado_dos_produtos (a coluna em produtos congelou na A27) e ancorado no ultimo dia observado.';

revoke all on function public.eventos_recentes(text, integer) from public;
grant execute on function public.eventos_recentes(text, integer)
  to anon, authenticated;
