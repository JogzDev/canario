-- P0 — fecha superfícies internas, corrige o portão de cobertura e torna a
-- chave de saúde realmente única quando marca_id é NULL.
--
-- Esta migration é aditiva: o histórico real anterior permanece intocado.

-- -------------------------------------------------------------------------
-- 1. Default-deny para novos objetos
-- -------------------------------------------------------------------------

alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated;

-- São insumos internos do motor. O app recebe apenas as saídas computadas.
revoke select on table public.raridade_do_atributo
  from anon, authenticated;
drop policy if exists "leitura publica da raridade"
  on public.raridade_do_atributo;
revoke select on table public.veiculo_da_perna
  from anon, authenticated;
revoke select on table public._vocabulario_por_termo
  from anon, authenticated;
revoke select on table public.denominador_editorial
  from anon, authenticated;

-- Funções de motor não são endpoints públicos. O service_role usado pelos
-- coletores continua autorizado explicitamente.
revoke execute on function public.computar_curva_tamanhos(integer)
  from public, anon, authenticated;
revoke execute on function public.computar_eventos()
  from public, anon, authenticated;
revoke execute on function public.computar_indice()
  from public, anon, authenticated;
revoke execute on function public.computar_raridade()
  from public, anon, authenticated;
revoke execute on function public.computar_serie_editorial()
  from public, anon, authenticated;
revoke execute on function public.computar_serie_varejo()
  from public, anon, authenticated;
revoke execute on function public.computar_z()
  from public, anon, authenticated;
revoke execute on function public.ordem_do_tamanho(text)
  from public, anon, authenticated;
revoke execute on function public.grade_em_texto(jsonb)
  from public, anon, authenticated;

grant execute on function public.computar_curva_tamanhos(integer) to service_role;
grant execute on function public.computar_eventos() to service_role;
grant execute on function public.computar_indice() to service_role;
grant execute on function public.computar_raridade() to service_role;
grant execute on function public.computar_serie_editorial() to service_role;
grant execute on function public.computar_serie_varejo() to service_role;
grant execute on function public.computar_z() to service_role;
grant execute on function public.ordem_do_tamanho(text) to service_role;
grant execute on function public.grade_em_texto(jsonb) to service_role;

-- -------------------------------------------------------------------------
-- 2. Saúde: NULL também participa da unicidade
-- -------------------------------------------------------------------------

-- A chave UNIQUE anterior aceita várias linhas com marca_id NULL. Mantemos a
-- observação mais recente de cada grupo e descartamos apenas redundâncias.
with repetidas as (
  select id,
         row_number() over (
           partition by data, fonte, marca_id
           order by criado_em desc, id desc
         ) as ordem
  from public.saude
)
delete from public.saude s
using repetidas r
where s.id = r.id and r.ordem > 1;

alter table public.saude
  drop constraint if exists saude_data_fonte_marca_id_key;
alter table public.saude
  add constraint saude_data_fonte_marca_id_key
  unique nulls not distinct (data, fonte, marca_id);

-- -------------------------------------------------------------------------
-- 3. Similares: somente termos aprovados, recorte da v1 e entradas limitadas
-- -------------------------------------------------------------------------

create or replace function public.similares_da_peca(
  termos text[],
  limite integer default 12,
  preco_alvo numeric default null)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with entrada as (
    -- Mantém a ordem enviada pelo app, remove duplicatas, ignora termos que
    -- não são públicos e limita o custo da consulta.
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
  ),
  parametros as (
    select filtrados,
           cardinality(filtrados) as pedidos,
           greatest(1, ceil(0.7 * cardinality(filtrados))::int) as minimo,
           least(greatest(coalesce($2, 12), 1), 24) as teto
    from entrada
  ),
  candidatos as (
    select pt.produto_id, count(distinct pt.termo_id) as em_comum
    from public.produto_termos pt
    cross join parametros par
    where pt.termo_id = any(par.filtrados)
    group by pt.produto_id, par.minimo
    having count(distinct pt.termo_id) >= par.minimo
  ),
  sim as (
    select p.id, p.titulo, p.url, p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca, c.em_comum,
           p.ultima_grade is not null as tem_grade,
           g.quebrada, g.esgotada
    from candidatos c
    join public.produtos p on p.id = c.produto_id
    join public.marcas   m on m.id = p.marca_id
    cross join lateral (
      select bool_or(value = 'false'::jsonb)      as quebrada,
             not bool_or(value = 'true'::jsonb)   as esgotada
      from jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb))
    ) g
    where p.segmento = 'feminino_casual_br'
  ),
  resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas',    count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'minimo_em_comum',   (select minimo  from parametros),
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
    ) as j
    from sim
  ),
  ordenado as (
    select *, row_number() over (
      partition by marca order by em_comum desc, id) as posicao_na_marca
    from sim
  ),
  amostra as (
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'marca', marca,
      'papel_da_marca', papel_da_marca,
      'titulo', titulo,
      'url', url,
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
    'pecas',  coalesce((select j from amostra), '[]'::jsonb));
$function$;

revoke all on function public.similares_da_peca(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca(text[], integer, numeric)
  to anon, authenticated;

-- -------------------------------------------------------------------------
-- 4. Cluster: ausência de cobertura reprova, nunca libera
-- -------------------------------------------------------------------------

create or replace function public.indice_do_cluster(termos text[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  categoria_da_peca text;
  n_categorias      integer;
begin
  if termos is null or array_length(termos, 1) is null then
    return jsonb_build_object('erro', 'nenhum atributo informado');
  end if;

  -- Protege a função pública de arrays usados como paginação/varredura.
  if array_length(termos, 1) > 12 then
    return jsonb_build_object('erro', 'atributos demais');
  end if;

  -- A função é SECURITY DEFINER e, portanto, não pode aceitar IDs que o app
  -- não obteria pela política pública de termos aprovados.
  if exists (
    select 1
    from unnest(indice_do_cluster.termos) entrada(termo_id)
    left join public.termos t on t.id = entrada.termo_id
    where t.id is null or t.status <> 'aprovado'
  ) then
    return jsonb_build_object('erro', 'atributo fora da taxonomia aprovada');
  end if;

  select count(*), min(t.id) into n_categorias, categoria_da_peca
  from public.termos t
  where t.id = any(indice_do_cluster.termos)
    and t.status = 'aprovado'
    and t.dimensao = 'categoria';

  if coalesce(n_categorias, 0) <> 1 then
    categoria_da_peca := '(todas)';
  end if;

  return (
  with
  ultimo as (
    select distinct on (i.termo_id)
           i.termo_id, i.segmento, i.indice, i.estado, i.semana,
           i.pernas_ativas, i.n_pernas
    from public.indices_semanais i
    where i.termo_id = any(indice_do_cluster.termos)
      and i.segmento = 'feminino_casual_br'
    order by i.termo_id, i.semana desc
  ),
  com_cobertura as (
    select u.*, coalesce(c.suficiente, false) as cobertura_ok
    from ultimo u
    left join public.cobertura_por_celula c
      on c.termo_id = u.termo_id
     and c.segmento = u.segmento
     and c.semana = u.semana
  ),
  pedido as (
    select t.id as termo_id, t.rotulo, t.dimensao, t.papel,
           r.peso, r.pecas, r.p_observado,
           cc.indice, cc.estado, cc.semana, cc.pernas_ativas, cc.n_pernas,
           case
             when cc.indice is null then 'sem leitura neste recorte'
             when not coalesce(cc.cobertura_ok, false)
                                  then 'cobertura insuficiente (§8)'
             when r.peso is null  then 'sem raridade computada'
             else null
           end as fora_por
    from public.termos t
    left join public.raridade_do_atributo r
      on r.termo_id = t.id and r.categoria = categoria_da_peca
    left join com_cobertura cc on cc.termo_id = t.id
    where t.id = any(indice_do_cluster.termos)
      and t.status = 'aprovado'
  ),
  somas as (
    select coalesce(sum(peso), 0)          as soma_w,
           coalesce(sum(peso * peso), 0)   as soma_w2,
           coalesce(sum(peso * indice), 0) as soma_wz,
           count(*)::integer               as n_atributos
    from pedido where fora_por is null
  ),
  media as (
    select s.*, case when s.soma_w > 0 then s.soma_wz / s.soma_w end as indice
    from somas s
  ),
  espalhamento as (
    select m.*,
      (select case when m.soma_w > 0 and m.n_atributos > 1
                then sqrt(sum(p.peso * (p.indice - m.indice) ^ 2) / m.soma_w)
              end
         from pedido p where p.fora_por is null) as desvio
    from media m
  )
  select jsonb_build_object(
    'categoria_usada', categoria_da_peca,
    'indice',      round(e.indice, 4),
    'dispersao',   round(e.desvio, 4),
    'atributos_efetivos',
        round((e.soma_w ^ 2) / nullif(e.soma_w2, 0), 2),
    'n_atributos', e.n_atributos,
    'ha_direcao',  case when e.n_atributos = 0 then false
                        when e.n_atributos = 1 then true
                        else abs(e.indice) >= coalesce(e.desvio, 0) end,
    'unidade', 'desvios-padrao da propria historia de cada atributo (§21)',
    'metodo',  'media dos indices ponderada por raridade dentro da dimensao e '
               || 'da categoria, com encolhimento para o prior em contagem '
               || 'baixa (§22, K5)',
    'atributos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'termo_id', p.termo_id,
        'rotulo',   p.rotulo,
        'dimensao', p.dimensao,
        'papel',    p.papel,
        'indice',   p.indice,
        'estado',   p.estado,
        'semana',   p.semana,
        'pernas',   p.pernas_ativas,
        'peso',     round(p.peso, 4),
        'peso_relativo', case when e.soma_w > 0 and p.fora_por is null
                              then round(p.peso / e.soma_w, 4) end,
        'pecas_no_painel', p.pecas,
        'pct_na_dimensao', round(100 * p.p_observado, 1),
        'fora_por', p.fora_por
      ) order by (p.fora_por is not null), p.peso desc nulls last), '[]'::jsonb)
      from pedido p
    )
  )
  from espalhamento e);
end;
$function$;

revoke all on function public.indice_do_cluster(text[]) from public;
grant execute on function public.indice_do_cluster(text[]) to anon, authenticated;
