-- A30: limita o dado cru sem apagar a historia ja materializada.
--
-- `snapshots` e a maior relacao do banco e recebe um batimento semanal por
-- produto, alem das mudancas reais. Cinco semanas cobrem com folga as janelas
-- operacionais (eventos: 14 dias; curva de tamanhos: 14 dias). As semanas mais
-- antigas continuam em `series_semanais`, que e a fonte historica do app.

create or replace function public.podar_snapshots(p_retencao_dias integer default 35)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  removidas integer := 0;
begin
  if p_retencao_dias < 21 then
    raise exception 'retencao de snapshots abaixo do piso seguro de 21 dias';
  end if;

  delete from public.snapshots
  where data < (current_date - p_retencao_dias);
  get diagnostics removidas = row_count;
  return removidas;
end;
$function$;

comment on function public.podar_snapshots(integer) is
  'A30: conserva a janela operacional crua; a serie semanal materializada permanece historica.';

revoke execute on function public.podar_snapshots(integer)
  from public, anon, authenticated;
grant execute on function public.podar_snapshots(integer) to service_role;

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

  -- So a janela ainda reconstruivel pode ser substituida. Sem este limite,
  -- podar o cru faria a proxima coleta apagar as semanas historicas prontas.
  delete from public.series_semanais s
  where s.fonte = 'varejo'
    and s.semana >= (select min(semana) from _serie_varejo_nova)
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
  'Share semanal de ofertas; recompõe apenas a janela crua e preserva a serie materializada anterior à retenção.';

revoke execute on function public.computar_serie_varejo()
  from public, anon, authenticated;
grant execute on function public.computar_serie_varejo() to service_role;

create or replace function public.computar_motor()
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  r_eventos integer;
  r_varejo integer;
  r_editorial integer;
  r_z integer;
  r_indice integer;
  r_curva integer;
  r_raridade integer;
  r_snapshots_removidos integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:publicacao-do-motor', 0));

  r_eventos := public.computar_eventos();
  r_varejo := public.computar_serie_varejo();
  r_editorial := public.computar_serie_editorial();
  r_z := public.computar_z();
  r_indice := public.computar_indice();
  r_curva := public.computar_curva_tamanhos();
  r_raridade := public.computar_raridade();

  -- A poda vem depois de todos os consumidores do cru e na mesma transação.
  r_snapshots_removidos := public.podar_snapshots(35);

  return jsonb_build_object(
    'computar_eventos', r_eventos,
    'computar_serie_varejo', r_varejo,
    'computar_serie_editorial', r_editorial,
    'computar_z', r_z,
    'computar_indice', r_indice,
    'computar_curva_tamanhos', r_curva,
    'computar_raridade', r_raridade,
    'snapshots_removidos', r_snapshots_removidos
  );
end;
$function$;

revoke execute on function public.computar_motor()
  from public, anon, authenticated;
grant execute on function public.computar_motor() to service_role;
