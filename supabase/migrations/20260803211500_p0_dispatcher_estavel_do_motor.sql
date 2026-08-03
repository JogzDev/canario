-- DISPATCHER PERMANENTE DO MOTOR
--
-- A primeira versao criava um job por execucao e tentava remove-lo de dentro
-- da propria transacao longa. O unschedule so ficava visivel no COMMIT; com
-- isso o scheduler relancava a chamada e a fila permanecia em `queued`.
-- Um dispatcher permanente elimina esse ciclo: ele pega no maximo uma fila e
-- o pg_cron garante que duas instancias do mesmo job nao rodam em paralelo.

do $block$
declare
  v_job record;
begin
  for v_job in
    select jobid from cron.job
    where jobname like 'canario-motor-%'
      and jobname <> 'canario-motor-dispatcher'
  loop
    -- Desativar e nao apagar e deliberado: `unschedule` espera uma instancia
    -- ativa terminar e travou a migration de recuperacao. Inativo, o job nao
    -- ganha novas execucoes; o worker que ja existe pode concluir com seguranca.
    perform cron.alter_job(v_job.jobid, active := false);
  end loop;
end;
$block$;

create or replace function public.executar_publicacao_motor(
  p_execucao uuid,
  p_total integer
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '900s'
as $function$
declare
  v_status text;
  v_resultado jsonb;
begin
  select status into v_status
  from public.motor_execucoes
  where execucao = p_execucao
  for update;

  if not found or v_status <> 'queued' then
    return;
  end if;

  update public.motor_execucoes
  set status = 'running', iniciado_em = now(), erro = null
  where execucao = p_execucao;

  begin
    v_resultado := public.publicar_motor(p_execucao, p_total);
  exception when others then
    update public.motor_execucoes
    set status = 'failed', erro = sqlstate || ': ' || sqlerrm,
        concluido_em = now()
    where execucao = p_execucao;
    return;
  end;

  update public.motor_execucoes
  set status = 'success', resultado = v_resultado, concluido_em = now()
  where execucao = p_execucao;
end;
$function$;

create or replace function public.executar_proxima_publicacao_motor()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_execucao uuid;
  v_total integer;
begin
  select execucao, total_produtos into v_execucao, v_total
  from public.motor_execucoes
  where status = 'queued'
  order by solicitado_em
  limit 1;

  if found then
    perform public.executar_publicacao_motor(v_execucao, v_total);
  end if;
end;
$function$;

select cron.schedule(
  'canario-motor-dispatcher',
  '* * * * *',
  'select public.executar_proxima_publicacao_motor();'
);

create or replace function public.solicitar_publicacao_motor(
  p_execucao uuid,
  p_total integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_stage integer;
  v_vivos integer;
  v_job_id bigint;
begin
  if p_execucao is null or p_total is null or p_total < 1 then
    raise exception 'execucao e total positivo sao obrigatorios';
  end if;

  select count(*) into v_stage from public.motor_produtos_stage
  where execucao = p_execucao;
  select count(*) into v_vivos from public.produtos;
  if v_stage <> p_total or v_vivos <> p_total then
    raise exception 'stage incompleto para %: declarados %, preparados %, vivos %',
      p_execucao, p_total, v_stage, v_vivos;
  end if;

  update public.motor_execucoes
  set status = 'failed', erro = 'fila expirada antes da conclusao',
      concluido_em = now()
  where status in ('queued', 'running')
    and solicitado_em < now() - interval '30 minutes';

  if exists (select 1 from public.motor_execucoes
             where status in ('queued', 'running')) then
    raise exception 'ja existe uma publicacao do motor em andamento';
  end if;

  select jobid into v_job_id from cron.job
  where jobname = 'canario-motor-dispatcher';
  if v_job_id is null then
    raise exception 'dispatcher do motor nao esta instalado';
  end if;

  insert into public.motor_execucoes
    (execucao, total_produtos, status, cron_job_id)
  values (p_execucao, p_total, 'queued', v_job_id);

  delete from public.motor_execucoes
  where concluido_em < now() - interval '14 days';

  return jsonb_build_object(
    'execucao', p_execucao, 'status', 'queued', 'cron_job_id', v_job_id);
end;
$function$;

revoke execute on function public.executar_publicacao_motor(uuid, integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.executar_proxima_publicacao_motor()
  from public, anon, authenticated, service_role;
revoke execute on function public.solicitar_publicacao_motor(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.solicitar_publicacao_motor(uuid, integer)
  to service_role;

comment on function public.executar_proxima_publicacao_motor() is
  'Dispatcher unico do pg_cron: publica a fila mais antiga sem sobreposicao.';
