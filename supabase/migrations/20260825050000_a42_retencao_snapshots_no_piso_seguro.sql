-- A42: usa o piso seguro ja imposto pela A30 para manter o plano gratuito.
--
-- Eventos e curva de tamanhos consomem no maximo 14 dias de dado cru. Tres
-- semanas preservam uma semana adicional para atrasos de coleta; a historia do
-- app continua em `series_semanais` e nao e podada aqui.

create or replace function public.podar_snapshots(p_retencao_dias integer default 21)
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
  'A42: conserva 21 dias de dado cru; a serie semanal materializada permanece historica.';

revoke execute on function public.podar_snapshots(integer)
  from public, anon, authenticated;
grant execute on function public.podar_snapshots(integer) to service_role;

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

  -- Todos os consumidores do cru ja terminaram; mantemos o piso seguro da A30.
  r_snapshots_removidos := public.podar_snapshots(21);

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
