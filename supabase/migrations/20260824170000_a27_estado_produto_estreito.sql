-- A27: estado volatil sai da linha larga de produtos.
--
-- A coleta visita dezenas de milhares de itens por noite. Atualizar uma data
-- na linha larga criava uma nova tupla inteira no MVCC, mesmo sem mudança de
-- produto. Esta tabela estreita reduz a escrita diária e permite que o
-- autovacuum acompanhe o pipeline no plano gratuito.

create table if not exists public.estado_dos_produtos (
  produto_id bigint primary key references public.produtos(id) on delete cascade,
  ultimo_avistamento_em date not null,
  ofertavel boolean not null,
  ultimo_snapshot_em date not null
);

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em)
select p.id,
       coalesce(p.ultimo_avistamento_em, p.ultimo_snapshot_em, current_date),
       coalesce(p.ofertavel, false),
       coalesce(p.ultimo_snapshot_em, p.ultimo_avistamento_em, current_date)
from public.produtos p
on conflict (produto_id) do nothing;

alter table public.estado_dos_produtos enable row level security;
alter table public.estado_dos_produtos force row level security;
revoke all on public.estado_dos_produtos from public, anon, authenticated;
grant select, insert, update, delete on public.estado_dos_produtos to service_role;

create index if not exists estado_produtos_oferta_recente
  on public.estado_dos_produtos (ultimo_avistamento_em desc, produto_id)
  where ofertavel is true;

comment on table public.estado_dos_produtos is
  'A27: estado corrente estreito, regravado diariamente sem inflar produtos.';

create or replace function public.computar_serie_varejo()
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer := 0;
  removidas integer := 0;
begin
  create temp table _serie_varejo_nova (
    termo_id text not null,
    segmento text not null,
    semana date not null,
    valor_bruto numeric not null,
    n_amostra integer not null,
    n_total integer not null,
    dimensao text not null,
    n_dimensao integer not null,
    cobertura_dimensao_pct numeric not null,
    primary key (termo_id, segmento, semana)
  ) on commit drop;

  insert into _serie_varejo_nova
    (termo_id, segmento, semana, valor_bruto, n_amostra, n_total,
     dimensao, n_dimensao, cobertura_dimensao_pct)
  with semanas as (
    select distinct
      (s.data - ((extract(isodow from s.data)::int) - 1)) as semana
    from public.snapshots s
  ),
  estados as (
    select
      s.produto_id,
      p.segmento,
      s.data as inicio,
      least(
        coalesce(
          lead(s.data) over (partition by s.produto_id order by s.data) - 1,
          ep.ultimo_avistamento_em),
        ep.ultimo_avistamento_em,
        s.data + 6
      ) as fim,
      s.ofertavel
    from public.snapshots s
    join public.produtos p on p.id = s.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    where p.segmento is not null
      and ep.ultimo_avistamento_em is not null
  ),
  presenca as (
    select distinct
      w.semana, e.produto_id, e.segmento
    from semanas w
    join estados e
      on e.ofertavel is true
     and e.inicio <= w.semana + 6
     and e.fim >= w.semana
  ),
  total_semana as (
    select semana, segmento, count(distinct produto_id)::integer as n_total
    from presenca
    group by semana, segmento
  ),
  por_termo as (
    select pr.semana, pr.segmento, pt.termo_id, t.dimensao,
           count(distinct pr.produto_id)::integer as n
    from presenca pr
    join public.produto_termos pt on pt.produto_id = pr.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.status = 'aprovado'
    group by pr.semana, pr.segmento, pt.termo_id, t.dimensao
  ),
  por_dimensao as (
    select pr.semana, pr.segmento, t.dimensao,
           count(distinct pr.produto_id)::integer as n_dimensao
    from presenca pr
    join public.produto_termos pt on pt.produto_id = pr.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.status = 'aprovado'
      and t.papel in ('atributo', 'denominador')
    group by pr.semana, pr.segmento, t.dimensao
  )
  select
    pt.termo_id,
    pt.segmento,
    pt.semana,
    round(100.0 * pt.n / nullif(ts.n_total, 0), 4),
    pt.n,
    ts.n_total,
    pt.dimensao,
    pd.n_dimensao,
    round(100.0 * pd.n_dimensao / nullif(ts.n_total, 0), 4)
  from por_termo pt
  join total_semana ts
    on ts.semana = pt.semana and ts.segmento = pt.segmento
  join por_dimensao pd
    on pd.semana = pt.semana and pd.segmento = pt.segmento
   and pd.dimensao = pt.dimensao;

  if not exists (select 1 from _serie_varejo_nova) then
    raise exception
      'serie de varejo vazia: nenhuma oferta observada; publicacao preservada';
  end if;

  delete from public.series_semanais s
  where s.fonte = 'varejo'
    and not exists (
      select 1 from _serie_varejo_nova n
      where n.termo_id = s.termo_id
        and n.segmento = s.segmento
        and n.semana = s.semana
    );
  get diagnostics removidas = row_count;

  insert into public.series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select
    n.termo_id,
    n.segmento,
    'varejo',
    n.semana,
    n.valor_bruto,
    null,
    n.n_amostra,
    jsonb_build_object(
      'metrica', 'share de ofertas observadas no sortimento do painel (%)',
      'n_total_sortimento', n.n_total,
      'dimensao', n.dimensao,
      'n_com_atributo_na_dimensao', n.n_dimensao,
      'cobertura_dimensao_pct', n.cobertura_dimensao_pct,
      'minimo_cobertura_dimensao_pct', 30,
      'semantica_presenca', 'ofertavel em ao menos um dia da semana, com confirmacao em intervalo de ate 7 dias',
      'legado_desconhecido_excluido', true,
      'obs', 'varejo descritivo, sem z-score por decisao B1',
      'computado_em', now()
    )
  from _serie_varejo_nova n
  on conflict (termo_id, segmento, fonte, semana) do update
    set valor_bruto = excluded.valor_bruto,
        z           = null,
        n_amostra   = excluded.n_amostra,
        meta        = excluded.meta;

  get diagnostics linhas = row_count;
  return linhas + removidas;
end;
$function$;

comment on function public.computar_serie_varejo() is
  'Share semanal de ofertas observadas com cobertura materializada por dimensao. Presenca exige oferta confirmada em intervalo maximo de sete dias.';

create or replace function public.computar_raridade()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
begin
  with
  ativos as materialized (
    select p.id as produto_id
    from public.produtos p
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    where p.segmento is not null
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em >=
          (now() at time zone 'America/Sao_Paulo')::date - 7
  ),
  cat as (
    select pt.produto_id, t.id as categoria
    from ativos a
    join public.produto_termos pt on pt.produto_id = a.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.dimensao = 'categoria'
  ),
  universo as (
    select produto_id, categoria from cat
    union all
    select a.produto_id, '(todas)'
    from ativos a
  ),
  dims as (
    select dimensao, count(*) filter (where papel = 'atributo')::integer as k
    from public.termos group by dimensao
  ),
  categorias as (select distinct categoria from universo),
  grade as (
    select c.categoria, t.id as termo_id, t.dimensao, t.papel,
           greatest(d.k, 1) as termos_na_dimensao
    from categorias c
    cross join public.termos t
    join dims d on d.dimensao = t.dimensao
  ),
  df as (
    select u.categoria, pt.termo_id,
           count(distinct u.produto_id)::integer as pecas
    from universo u
    join public.produto_termos pt on pt.produto_id = u.produto_id
    group by 1, 2
  ),
  n_dim as (
    select u.categoria, t.dimensao,
           count(distinct u.produto_id)::integer as pecas_na_dimensao
    from universo u
    join public.produto_termos pt on pt.produto_id = u.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.papel = 'atributo'
    group by 1, 2
  ),
  observado as (
    select g.categoria, g.termo_id, g.dimensao, g.papel,
           g.termos_na_dimensao,
           coalesce(df.pecas, 0) as pecas,
           coalesce(n.pecas_na_dimensao, 0) as pecas_na_dimensao,
           case when coalesce(n.pecas_na_dimensao, 0) > 0
                     and g.papel = 'atributo'
                then coalesce(df.pecas, 0)::numeric / n.pecas_na_dimensao
                else null end as p_observado,
           1.0::numeric / g.termos_na_dimensao as p_prior
    from grade g
    left join df
      on df.categoria = g.categoria and df.termo_id = g.termo_id
    left join n_dim n
      on n.categoria = g.categoria and n.dimensao = g.dimensao
  ),
  momentos as (
    select categoria, dimensao,
           avg(p_observado) as p_barra, var_samp(p_observado) as tau2
    from observado
    where p_observado is not null
    group by 1, 2
  ),
  ajustado as (
    select o.*,
           case when mo.tau2 is null or mo.tau2 <= 0 then null
                else (mo.p_barra * (1 - mo.p_barra)) / mo.tau2 end as m
    from observado o
    left join momentos mo
      on mo.categoria = o.categoria and mo.dimensao = o.dimensao
  ),
  final as (
    select a.*,
           case when a.m is null or a.p_observado is null then 0::numeric
                else a.pecas::numeric / (a.m + a.pecas) end as lambda
    from ajustado a
  )
  insert into public.raridade_do_atributo
    (categoria, termo_id, dimensao, papel, pecas, pecas_na_dimensao,
     termos_na_dimensao, p_observado, p_prior, m, lambda, p_ajustado, peso,
     computado_em)
  select
    f.categoria, f.termo_id, f.dimensao, f.papel, f.pecas,
    f.pecas_na_dimensao, f.termos_na_dimensao, f.p_observado, f.p_prior,
    f.m, round(f.lambda, 6), round(calc.p_aj, 8),
    round(ln(1 + 1 / calc.p_aj)::numeric, 6), now()
  from final f
  cross join lateral (
    select greatest(
      f.lambda * coalesce(f.p_observado, f.p_prior)
        + (1 - f.lambda) * f.p_prior,
      1e-6) as p_aj
  ) calc
  on conflict (categoria, termo_id) do update
    set dimensao = excluded.dimensao,
        papel = excluded.papel,
        pecas = excluded.pecas,
        pecas_na_dimensao = excluded.pecas_na_dimensao,
        termos_na_dimensao = excluded.termos_na_dimensao,
        p_observado = excluded.p_observado,
        p_prior = excluded.p_prior,
        m = excluded.m,
        lambda = excluded.lambda,
        p_ajustado = excluded.p_ajustado,
        peso = excluded.peso,
        computado_em = now();

  get diagnostics linhas = row_count;

  update public.raridade_do_atributo r
     set peso = coalesce(med.peso_medio, r.peso),
         lambda = 0,
         p_ajustado = r.p_prior
    from (
      select categoria, dimensao, avg(peso) as peso_medio
      from public.raridade_do_atributo
      where papel = 'atributo'
      group by 1, 2
    ) med
   where r.papel = 'denominador'
     and med.categoria = r.categoria
     and med.dimensao = r.dimensao;

  return linhas;
end;
$function$;

comment on function public.computar_raridade() is
  'Raridade empirico-Bayes no catalogo atualmente ofertavel e observado ha no maximo sete dias; legado sem disponibilidade explicita nao entra.';

revoke execute on function public.computar_raridade()
  from public, anon, authenticated;
grant execute on function public.computar_raridade()
  to service_role;


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
             as filtrados,
           coalesce(array_agg(a.termo_id order by a.primeira_posicao)
             filter (where a.dimensao = 'categoria'), '{}'::text[]) as categorias
    from (
      select e.termo_id, min(e.posicao) as primeira_posicao,
             min(t.dimensao) as dimensao
      from unnest(coalesce($1, '{}'::text[])) with ordinality e(termo_id, posicao)
      join public.termos t
        on t.id = e.termo_id and t.status = 'aprovado'
      group by e.termo_id
      order by min(e.posicao)
      limit 12
    ) a
  ), parametros as (
    select filtrados, categorias,
           cardinality(filtrados) as pedidos,
           greatest(1, ceil(0.7 * cardinality(filtrados))::int) as minimo,
           least(greatest(coalesce($2, 12), 1), 24) as teto
    from entrada
  ), candidatos as (
    select pt.produto_id,
           count(distinct pt.termo_id) as em_comum,
           array_agg(distinct pt.termo_id) as termos_em_comum
    from public.produto_termos pt
    cross join parametros par
    where pt.termo_id = any(par.filtrados)
    group by pt.produto_id, par.minimo, par.categorias
    having count(distinct pt.termo_id) >= par.minimo
       and (cardinality(par.categorias) = 0
            or bool_or(pt.termo_id = any(par.categorias)))
  ), sim as (
    select p.id, p.titulo,
           public.url_publica_produto(p.url, m.nome) as url,
           p.imagem_url as imagem,
           p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca,
           c.em_comum, c.termos_em_comum,
           p.ultima_grade is not null as tem_grade,
           g.quebrada, g.esgotada
    from candidatos c
    join public.produtos p on p.id = c.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    join public.marcas m on m.id = p.marca_id
    cross join lateral (
      select bool_or(value = 'false'::jsonb) as quebrada,
             not bool_or(value = 'true'::jsonb) as esgotada
      from jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb))
    ) g
    where p.segmento = 'feminino_casual_br'
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em >= current_date - 7
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
      'termos_em_comum', to_jsonb(termos_em_comum),
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
  'P20/A27: categoria obrigatoria; oferta recente lida do estado estreito.';


-- As colunas antigas ficam congeladas por uma migração para permitir rollback
-- operacional. Depois de sete coletas saudáveis, uma migração posterior pode
-- removê-las e executar VACUUM FULL fora do horário do pipeline.
