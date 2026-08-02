-- Papel do termo na taxonomia. Espelha `marcas.papel`, que ja distingue
-- medicao de direcao: aqui distingue ATRIBUTO (medido por casamento de
-- palavra) de DENOMINADOR (existe para dar base de comparacao ao resto).
alter table public.termos
  add column if not exists papel text not null default 'atributo';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'termos_papel_valido') then
    alter table public.termos
      add constraint termos_papel_valido check (papel in ('atributo','denominador'));
  end if;
end $$;

comment on column public.termos.papel is
  'atributo = medido por casamento de palavra. denominador = existe para dar '
  'base de comparacao (liso, outras_cores); nao recebe peso de raridade '
  'proprio porque sua contagem nao e medicao.';

update public.termos set papel = 'denominador' where id in ('liso','outras_cores');

alter table public.raridade_do_atributo
  add column if not exists papel text not null default 'atributo';

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
  -- Cardinalidade da dimensao conta so os ATRIBUTOS: o denominador nao e uma
  -- opcao que o comprador escolhe, e inflar k rebaixaria o prior de todos.
  dims as (
    select dimensao, count(*) filter (where papel = 'atributo')::integer as k
    from termos group by dimensao
  ),
  categorias as (select distinct categoria from universo),
  grade as (
    select c.categoria, t.id as termo_id, t.dimensao, t.papel,
           greatest(d.k, 1) as termos_na_dimensao
    from categorias c
    cross join termos t
    join dims d on d.dimensao = t.dimensao
  ),
  df as (
    select u.categoria, pt.termo_id, count(distinct u.produto_id)::integer as pecas
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    group by 1, 2
  ),
  -- Denominador fica FORA do denominador da dimensao. Sem isto, `liso`
  -- entraria no n de estampa e mexeria na fatia de `floral` por um numero
  -- que nao e medicao.
  n_dim as (
    select u.categoria, t.dimensao,
           count(distinct u.produto_id)::integer as pecas_na_dimensao
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    join termos t on t.id = pt.termo_id
    where t.papel = 'atributo'
    group by 1, 2
  ),
  observado as (
    select g.categoria, g.termo_id, g.dimensao, g.papel, g.termos_na_dimensao,
           coalesce(df.pecas, 0) as pecas,
           coalesce(n.pecas_na_dimensao, 0) as pecas_na_dimensao,
           case when coalesce(n.pecas_na_dimensao, 0) > 0 and g.papel = 'atributo'
                then coalesce(df.pecas, 0)::numeric / n.pecas_na_dimensao
                else null end as p_observado,
           1.0::numeric / g.termos_na_dimensao as p_prior
    from grade g
    left join df    on df.categoria = g.categoria and df.termo_id = g.termo_id
    left join n_dim n on n.categoria = g.categoria and n.dimensao = g.dimensao
  ),
  momentos as (
    select categoria, dimensao,
           avg(p_observado) as p_barra, var_samp(p_observado) as tau2
    from observado where p_observado is not null group by 1, 2
  ),
  ajustado as (
    select o.*,
           case when mo.tau2 is null or mo.tau2 <= 0 then null
                else (mo.p_barra * (1 - mo.p_barra)) / mo.tau2 end as m
    from observado o
    left join momentos mo on mo.categoria = o.categoria and mo.dimensao = o.dimensao
  ),
  final as (
    select a.*,
           case when a.m is null or a.p_observado is null then 0::numeric
                else a.pecas::numeric / (a.m + a.pecas) end as lambda
    from ajustado a
  )
  insert into raridade_do_atributo
    (categoria, termo_id, dimensao, papel, pecas, pecas_na_dimensao,
     termos_na_dimensao, p_observado, p_prior, m, lambda, p_ajustado, peso,
     computado_em)
  select
    f.categoria, f.termo_id, f.dimensao, f.papel, f.pecas, f.pecas_na_dimensao,
    f.termos_na_dimensao, f.p_observado, f.p_prior, f.m, round(f.lambda, 6),
    round(calc.p_aj, 8),
    round(ln(1 + 1 / calc.p_aj)::numeric, 6),
    now()
  from final f
  cross join lateral (
    select greatest(
      f.lambda * coalesce(f.p_observado, f.p_prior) + (1 - f.lambda) * f.p_prior,
      1e-6) as p_aj
  ) calc
  on conflict (categoria, termo_id) do update
    set dimensao = excluded.dimensao, papel = excluded.papel,
        pecas = excluded.pecas, pecas_na_dimensao = excluded.pecas_na_dimensao,
        termos_na_dimensao = excluded.termos_na_dimensao,
        p_observado = excluded.p_observado, p_prior = excluded.p_prior,
        m = excluded.m, lambda = excluded.lambda,
        p_ajustado = excluded.p_ajustado, peso = excluded.peso,
        computado_em = now();

  get diagnostics linhas = row_count;

  -- Denominador nao reivindica raridade: recebe o peso MEDIO dos atributos
  -- medidos da propria dimensao. Nao e prior (que depende de k, e k e
  -- arbitrario), e nao e zero (o termo tem indice valido vindo das pernas de
  -- busca e editorial -- so a contagem no painel e que nao e medicao).
  update raridade_do_atributo r
     set peso = coalesce(med.peso_medio, r.peso),
         lambda = 0,
         p_ajustado = r.p_prior
    from (select categoria, dimensao, avg(peso) as peso_medio
            from raridade_do_atributo
           where papel = 'atributo'
           group by 1, 2) med
   where r.papel = 'denominador'
     and med.categoria = r.categoria
     and med.dimensao = r.dimensao;

  return linhas;
end;
$function$;;
