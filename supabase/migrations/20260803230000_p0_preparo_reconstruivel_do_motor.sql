-- PREPARO RECONSTRUIVEL DO MOTOR
--
-- O worker ja limpa o proprio stage quando falha depois de entrar na fila.
-- Faltava cobrir o intervalo ANTES da fila: se o runner caísse enquanto
-- preenchia o stage, nao existiria `motor_execucoes` para o worker recuperar.
-- Toda nova preparacao comeca por esta RPC; sem publicacao ativa, o stage e
-- descartavel e pode ser truncado, devolvendo espaco imediatamente.

create or replace function public.preparar_stage_motor()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_expiradas integer;
begin
  -- O comando do cron recebe teto de 15 min e inicia no maximo em um minuto.
  -- Vinte minutos deixam margem e ainda recuperam um dispatcher/runner morto
  -- antes da proxima coleta diaria.
  update public.motor_execucoes
  set status = 'failed',
      erro = coalesce(erro, 'publicacao expirada antes do proximo preparo'),
      concluido_em = coalesce(concluido_em, now())
  where status in ('queued', 'running')
    and coalesce(iniciado_em, solicitado_em) < now() - interval '20 minutes';
  get diagnostics v_expiradas = row_count;

  -- Nunca descarta a preparacao que o dispatcher ainda pode publicar. A
  -- concorrencia `canario-dados` do Actions cobre a preparacao inteira; esta
  -- guarda adicional protege tambem uma chamada manual do service_role.
  if exists (
    select 1 from public.motor_execucoes
    where status in ('queued', 'running')
  ) then
    raise exception 'ja existe uma publicacao do motor em andamento';
  end if;

  truncate table public.motor_termos_stage, public.motor_produtos_stage;

  return jsonb_build_object(
    'stage', 'limpo',
    'execucoes_expiradas', v_expiradas);
end;
$function$;

revoke execute on function public.preparar_stage_motor()
  from public, anon, authenticated;
grant execute on function public.preparar_stage_motor() to service_role;

comment on function public.preparar_stage_motor() is
  'Inicio seguro do stage reconstruivel: recupera execucao expirada e trunca somente sem motor ativo.';
