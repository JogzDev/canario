create table if not exists public.raridade_do_atributo (
  categoria           text        not null,
  termo_id            text        not null,
  dimensao            text        not null,
  pecas               integer     not null,
  pecas_na_dimensao   integer     not null,
  termos_na_dimensao  integer     not null,
  p_observado         numeric,
  p_prior             numeric     not null,
  m                   numeric,
  lambda              numeric     not null,
  p_ajustado          numeric     not null,
  peso                numeric     not null,
  computado_em        timestamptz not null default now(),
  primary key (categoria, termo_id)
);

alter table public.raridade_do_atributo enable row level security;

drop policy if exists "leitura publica da raridade" on public.raridade_do_atributo;
create policy "leitura publica da raridade"
  on public.raridade_do_atributo for select
  using (true);

create or replace function public.computar_raridade()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
begin
  with
  cat as (
    select pt.produto_id, t.id as categoria
    from produto_termos pt
    join termos t on t.id = pt.termo_id
    where t.dimensao = 'categoria'
  ),
  universo as (
    select produto_id, categoria from cat
    union all
    select distinct produto_id, '(todas)' from produto_termos
  ),
  dims as (
    select dimensao, count(*)::integer as k from termos group by dimensao
  ),
  categorias as (
    select distinct categoria from universo
  ),
  grade as (
    select c.categoria, t.id as termo_id, t.dimensao, d.k as termos_na_dimensao
    from categorias c cross join termos t join dims d on d.dimensao = t.dimensao
  ),
  df as (
    select u.categoria, pt.termo_id, count(distinct u.produto_id)::integer as pecas
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    group by 1, 2
  ),
  n_dim as (
    select u.categoria, t.dimensao,
           count(distinct u.produto_id)::integer as pecas_na_dimensao
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    join termos t on t.id = pt.termo_id
    group by 1, 2
  ),
  observado as (
    select g.categoria, g.termo_id, g.dimensao, g.termos_na_dimensao,
           coalesce(df.pecas, 0) as pecas,
           coalesce(n.pecas_na_dimensao, 0) as pecas_na_dimensao,
           case when coalesce(n.pecas_na_dimensao, 0) > 0
                then coalesce(df.pecas, 0)::numeric / n.pecas_na_dimensao
                else null end as p_observado,
           1.0::numeric / g.termos_na_dimensao as p_prior
    from grade g
    left join df    on df.categoria = g.categoria and df.termo_id  = g.termo_id
    left join n_dim n on n.categoria = g.categoria and n.dimensao  = g.dimensao
  ),
  momentos as (
    select categoria, dimensao,
           avg(p_observado)      as p_barra,
           var_samp(p_observado) as tau2
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
  insert into raridade_do_atributo
    (categoria, termo_id, dimensao, pecas, pecas_na_dimensao,
     termos_na_dimensao, p_observado, p_prior, m, lambda, p_ajustado, peso,
     computado_em)
  select
    f.categoria, f.termo_id, f.dimensao, f.pecas, f.pecas_na_dimensao,
    f.termos_na_dimensao, f.p_observado, f.p_prior, f.m, round(f.lambda, 6),
    round(calc.p_aj, 8),
    round(ln(1 + 1 / calc.p_aj)::numeric, 6),
    now()
  from final f
  cross join lateral (
    select greatest(
      f.lambda * coalesce(f.p_observado, f.p_prior) + (1 - f.lambda) * f.p_prior,
      1e-6
    ) as p_aj
  ) calc
  on conflict (categoria, termo_id) do update
    set dimensao           = excluded.dimensao,
        pecas              = excluded.pecas,
        pecas_na_dimensao  = excluded.pecas_na_dimensao,
        termos_na_dimensao = excluded.termos_na_dimensao,
        p_observado        = excluded.p_observado,
        p_prior            = excluded.p_prior,
        m                  = excluded.m,
        lambda             = excluded.lambda,
        p_ajustado         = excluded.p_ajustado,
        peso               = excluded.peso,
        computado_em       = now();

  get diagnostics linhas = row_count;
  return linhas;
end;
$function$;;
