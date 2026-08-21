-- P17 — PRESENCA NAO E EXISTENCIA HISTORICA; OFERTA NAO E BATIMENTO
--
-- Ate aqui `ultimo_snapshot_em` acumulava tres significados diferentes:
-- mudanca de estado, batimento semanal e avistamento. Pior: a serie de varejo
-- considerava presente em TODA semana futura qualquer produto que ja tivesse
-- entrado no catalogo. O share chamado de "sortimento" era, portanto, share
-- do catalogo historico acumulado.
--
-- O contrato novo separa os sinais:
--   * ultimo_avistamento_em: ultimo dia em que a loja devolveu o produto;
--   * ofertavel: havia ao menos uma variante/seller realmente compravel;
--   * ultimo_snapshot_em: continua sendo apenas o ponto de delta/batimento.
--
-- A serie historica usa os snapshots como intervalos confirmados de no maximo
-- sete dias, que e exatamente a cadencia do batimento B3. Ausencia de
-- observacao deixa de ser interpretada como presenca eterna.

alter table public.produtos
  add column if not exists ultimo_avistamento_em date,
  add column if not exists ofertavel boolean;

alter table public.snapshots
  add column if not exists ofertavel boolean;

comment on column public.produtos.ultimo_avistamento_em is
  'Ultimo dia em que a fonte devolveu o produto. Anda a cada visita, mesmo sem delta; nao confundir com ultimo_snapshot_em.';
comment on column public.produtos.ofertavel is
  'Estado atual observado: true quando ao menos uma variante/seller podia ser comprada; false quando nenhuma podia; null apenas no legado ainda nao reobservado.';
comment on column public.snapshots.ofertavel is
  'Oferta observada no ponto de delta/batimento. Null significa que o snapshot legado nao permite concluir disponibilidade.';

-- O legado permite afirmar oferta apenas quando existe grade e ao menos um
-- tamanho true. Grade vazia e ambigua (pode ser tamanho unico), portanto fica
-- NULL em vez de inventarmos disponibilidade a partir de preco cadastrado.
update public.snapshots s
set ofertavel = case
  when jsonb_typeof(s.grade_por_tamanho) = 'object'
   and exists (select 1 from jsonb_each(s.grade_por_tamanho))
    then exists (
      select 1 from jsonb_each(s.grade_por_tamanho) g
      where g.value = 'true'::jsonb
    )
  else null
end
where s.ofertavel is null;

with ultimo as (
  select distinct on (s.produto_id)
         s.produto_id, s.data, s.ofertavel
  from public.snapshots s
  order by s.produto_id, s.data desc
)
update public.produtos p
set ultimo_avistamento_em = coalesce(
      p.ultimo_avistamento_em, p.ultimo_snapshot_em, u.data,
      p.primeiro_avistamento),
    ofertavel = coalesce(p.ofertavel, u.ofertavel)
from ultimo u
where u.produto_id = p.id;

update public.produtos p
set ultimo_avistamento_em = coalesce(
      p.ultimo_avistamento_em, p.ultimo_snapshot_em,
      p.primeiro_avistamento)
where p.ultimo_avistamento_em is null;

create index if not exists produtos_ofertaveis_recentes
  on public.produtos (segmento, ultimo_avistamento_em desc)
  where ofertavel is true and segmento is not null;

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
    primary key (termo_id, segmento, semana)
  ) on commit drop;

  insert into _serie_varejo_nova
    (termo_id, segmento, semana, valor_bruto, n_amostra, n_total)
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
          p.ultimo_avistamento_em),
        p.ultimo_avistamento_em,
        s.data + 6
      ) as fim,
      s.ofertavel
    from public.snapshots s
    join public.produtos p on p.id = s.produto_id
    where p.segmento is not null
      and p.ultimo_avistamento_em is not null
  ),
  presenca as (
    -- Oferta semanal = produto observado compravel em pelo menos um dia da
    -- semana. DISTINCT impede que dois deltas na mesma semana contem duas
    -- pecas. O teto inicio+6 exige a confirmacao semanal prometida pela B3.
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
    select pr.semana, pr.segmento, pt.termo_id,
           count(distinct pr.produto_id)::integer as n
    from presenca pr
    join public.produto_termos pt on pt.produto_id = pr.produto_id
    group by pr.semana, pr.segmento, pt.termo_id
  )
  select
    pt.termo_id,
    pt.segmento,
    pt.semana,
    round(100.0 * pt.n / nullif(t.n_total, 0), 4),
    pt.n,
    t.n_total
  from por_termo pt
  join total_semana t
    on t.semana = pt.semana and t.segmento = pt.segmento;

  if not exists (select 1 from _serie_varejo_nova) then
    raise exception
      'serie de varejo vazia: nenhuma oferta observada; publicacao preservada';
  end if;

  -- Upsert sozinho deixava linhas antigas vivas quando uma celula desaparecia.
  -- A anti-juncao remove apenas o que esta materializacao acabou de provar que
  -- nao existe; tudo continua na mesma transacao do motor.
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
  'Share semanal de ofertas observadas. Presenca exige ofertavel=true e confirmacao por snapshot/delta em intervalo maximo de sete dias; produto antigo nao permanece para sempre.';

revoke execute on function public.computar_serie_varejo()
  from public, anon, authenticated;
grant execute on function public.computar_serie_varejo()
  to service_role;

-- Raridade alimenta o peso do cluster atual. Ela tambem lia todos os produtos
-- historicos; passa a usar somente o estado corrente explicitamente ofertavel
-- e confirmado dentro da cadencia semanal.
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
    where p.segmento is not null
      and p.ofertavel is true
      and p.ultimo_avistamento_em >=
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
