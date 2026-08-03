-- PUBLICACAO ATOMICA FORA DO TIMEOUT HTTP
--
-- O lote real de 67 mil produtos leva mais que os ~120s permitidos pelo
-- gateway do PostgREST. A transacao estava correta, mas a conexao HTTP morria
-- antes do COMMIT. O Actions agora apenas agenda o trabalho e consulta este
-- registro; pg_cron executa a MESMA publicacao atomica dentro do Postgres.

create extension if not exists pg_cron;

create table public.motor_execucoes (
  execucao       uuid primary key,
  total_produtos integer not null check (total_produtos > 0),
  status         text not null check (status in ('queued', 'running', 'success', 'failed')),
  cron_job_id    bigint,
  resultado      jsonb,
  erro           text,
  solicitado_em  timestamptz not null default now(),
  iniciado_em    timestamptz,
  concluido_em   timestamptz
);

create index motor_execucoes_ativas
  on public.motor_execucoes (status, solicitado_em)
  where status in ('queued', 'running');

alter table public.motor_execucoes enable row level security;
revoke all on table public.motor_execucoes from public, anon, authenticated;
grant select on table public.motor_execucoes to service_role;

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
  v_job_id bigint;
  v_resultado jsonb;
begin
  select status, cron_job_id into v_status, v_job_id
  from public.motor_execucoes
  where execucao = p_execucao
  for update;

  if not found or v_status <> 'queued' then
    return;
  end if;

  -- O job e recorrente apenas para o pg_cron poder inicia-lo sem uma conexao
  -- aberta. A primeira execucao o remove; a trava da linha impede duplicidade.
  begin
    if v_job_id is not null then
      perform cron.unschedule(v_job_id);
    end if;
  exception when others then
    null;
  end;

  update public.motor_execucoes
  set status = 'running', iniciado_em = now(), erro = null
  where execucao = p_execucao;

  -- O bloco cria um subtransaction: qualquer erro reverte atributos e todos
  -- os calculos juntos, mas ainda permite registrar a falha para o Actions.
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
  v_nome text;
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

  -- Recupera automaticamente uma fila abandonada; uma publicacao normal leva
  -- poucos minutos e a funcao interna ainda tem teto de 15 minutos.
  update public.motor_execucoes
  set status = 'failed', erro = 'fila expirada antes da conclusao',
      concluido_em = now()
  where status in ('queued', 'running')
    and solicitado_em < now() - interval '30 minutes';

  if exists (select 1 from public.motor_execucoes
             where status in ('queued', 'running')) then
    raise exception 'ja existe uma publicacao do motor em andamento';
  end if;

  insert into public.motor_execucoes
    (execucao, total_produtos, status)
  values (p_execucao, p_total, 'queued');

  v_nome := 'canario-motor-' || p_execucao::text;
  select cron.schedule(
    v_nome,
    '* * * * *',
    format('select public.executar_publicacao_motor(%L::uuid, %s);',
           p_execucao::text, p_total)
  ) into v_job_id;

  update public.motor_execucoes set cron_job_id = v_job_id
  where execucao = p_execucao;

  delete from public.motor_execucoes
  where concluido_em < now() - interval '14 days';

  return jsonb_build_object(
    'execucao', p_execucao, 'status', 'queued', 'cron_job_id', v_job_id);
end;
$function$;

revoke execute on function public.executar_publicacao_motor(uuid, integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.solicitar_publicacao_motor(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.solicitar_publicacao_motor(uuid, integer)
  to service_role;

comment on table public.motor_execucoes is
  'Estado observavel das publicacoes atomicas executadas pelo pg_cron.';
comment on function public.executar_publicacao_motor(uuid, integer) is
  'Worker interno do pg_cron; executa publicar_motor fora do timeout HTTP.';
comment on function public.solicitar_publicacao_motor(uuid, integer) is
  'Valida o stage, agenda uma unica publicacao e devolve imediatamente.';
