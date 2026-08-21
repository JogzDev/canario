-- P18 — 30 PECAS NAO SIGNIFICAM 30% DA DIMENSAO OBSERVADA
--
-- O portao da §8 exigia 30 pecas e 8 marcas por termo. `liso` passava com 39
-- pecas, embora estampa existisse em apenas 6,3% das ofertas atuais: ausencia
-- da palavra no titulo era interpretada como ausencia do atributo. O app
-- podia, portanto, soar confiante exatamente onde o coletor era quase cego.
--
-- A serie de varejo passa a materializar, por semana e dimensao, quantas
-- ofertas receberam QUALQUER rotulo daquela dimensao. A interface só libera
-- indice/estado quando essa cobertura chega a 30% do sortimento confirmado.
-- O minimo antigo por termo e por marcas continua valendo junto.

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

create or replace view public.cobertura_por_celula
with (security_invoker = true)
as
with marcas as (
  -- Mantem bigint, o tipo historico de count(*) exposto pela view. PostgreSQL
  -- nao permite trocar o tipo de uma coluna existente em CREATE OR REPLACE.
  select count(*) as externas
  from public.marcas m
  where m.status_teste in ('vtex','shopify')
    and m.ativa
    and m.papel in ('nucleo','adjacente','ancora')
    and exists (select 1 from public.produtos p where p.marca_id = m.id)
)
select
  s.termo_id,
  s.segmento,
  s.semana,
  s.n_amostra as pecas_na_celula,
  marcas.externas as marcas_externas,
  30 as minimo_pecas,
  8 as minimo_marcas,
  -- As oito colunas historicas permanecem na mesma ordem; colunas novas so
  -- podem ser anexadas ao fim quando a view e substituida em producao.
  (s.n_amostra >= 30
   and marcas.externas >= 8
   and coalesce(
         (s.meta ->> 'cobertura_dimensao_pct')::numeric, 0
       ) >= 30
  ) as suficiente,
  (s.meta ->> 'n_com_atributo_na_dimensao')::integer
    as pecas_na_dimensao,
  (s.meta ->> 'cobertura_dimensao_pct')::numeric
    as cobertura_dimensao_pct,
  30::numeric as minimo_cobertura_dimensao_pct
from public.series_semanais s
cross join marcas
where s.fonte = 'varejo';

comment on view public.cobertura_por_celula is
  '§8/P18: exige 30 pecas, 8 marcas externas e ao menos 30% do sortimento com algum rotulo da dimensao. Ausencia de medicao reprova.';

grant select on public.cobertura_por_celula to anon, authenticated;
