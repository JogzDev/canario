-- A63: o Supabase dispara e vigia o pipeline diario.
--
-- POR QUE
-- =======
--
-- O pipeline nascia do agendamento do GitHub, que atrasou de 3,5 a 5 horas
-- entre 19 e 23/09/2026 (nominal 03:17 BRT; 23/09 nasceu as 08:33) e em 21/09
-- nem nasceu. O GitHub documenta isso: eventos agendados podem atrasar ou ser
-- descartados sob carga. Nenhuma regra do pipeline resolve um disparo que
-- nao acontece.
--
-- O pg_cron deste banco ja roda o despachante do motor a cada minuto e a
-- retencao do proprio log. Ele passa a ser o titular do disparo diario, e o
-- GitHub vira reserva (`gatilho-reserva.yml`, que so dispara se o dia ainda
-- nao teve execucao).
--
-- O QUE ENTRA
-- ===========
--
-- * `disparar_pipeline_diario()`, as 03:17 BRT: pede ao GitHub a execucao do
--   `pipeline-diario.yml`, no maximo uma vez por dia operacional.
-- * `vigiar_pipeline_diario()`, ao meio-dia BRT: se o painel nao foi publicado
--   hoje E nenhuma coleta do dia gravou saude, o pipeline nao rodou. Ela pede
--   de novo e abre uma issue -- o GitHub manda a issue por e-mail ao JP.
--   Coleta que rodou e falhou nao e com ela: o job `alerta` do pipeline ja
--   abre e mantem a issue de incidente.
-- * `testar_token_do_github()`: um GET inofensivo nos metadados do repositorio,
--   para conferir o token sem disparar nada.
--
-- O TOKEN
-- =======
--
-- Um token fine-grained do GitHub, restrito a JogzDev/canario, com Actions e
-- Issues em leitura e escrita, guardado no Vault com o nome
-- `github_pipeline`. Quem cria e guarda e o JP; nenhuma migration, log ou
-- conversa carrega o valor. Sem o segredo, as tres funcoes devolvem o
-- motivo e nao fazem chamada nenhuma -- a reserva do GitHub segue sozinha,
-- exatamente como antes desta migration.
--
-- As chamadas HTTP saem pelo pg_net, que e assincrono: a resposta do GitHub
-- (204 no disparo, 201 na issue, 200 no teste) aparece depois em
-- `net._http_response` e fica la so 6 horas. `registrar_respostas_do_pipeline`
-- copia o codigo para `gatilhos_do_pipeline.respostas` de hora em hora, para
-- a vigia do meio-dia ainda saber o que o GitHub respondeu as 03:17.

create extension if not exists pg_net;

create table if not exists public.gatilhos_do_pipeline (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('disparo', 'vigia')),
  data_operacional date not null,
  pedidos bigint[] not null default '{}',
  respostas integer[] not null default '{}',
  criado_em timestamptz not null default now(),
  unique (tipo, data_operacional)
);

alter table public.gatilhos_do_pipeline enable row level security;
alter table public.gatilhos_do_pipeline force row level security;
revoke all on public.gatilhos_do_pipeline from public, anon, authenticated;
grant select on public.gatilhos_do_pipeline to service_role;

comment on table public.gatilhos_do_pipeline is
  'A63: uma linha por disparo diario e por acao da vigia; `pedidos` guarda os ids do pg_net e `respostas` os codigos HTTP do GitHub, na mesma ordem.';

create or replace function public._token_do_github()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'github_pipeline'
  limit 1;
$function$;

revoke all on function public._token_do_github() from public, anon, authenticated, service_role;

create or replace function public._chamar_github(
  p_metodo text, p_caminho text, p_corpo jsonb default null)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  token text := public._token_do_github();
  cabecalhos jsonb;
begin
  if token is null then
    return null;
  end if;
  cabecalhos := jsonb_build_object(
    'Authorization', 'Bearer ' || token,
    'Accept', 'application/vnd.github+json',
    'X-GitHub-Api-Version', '2022-11-28',
    'User-Agent', 'canario-supabase-pg-cron');
  if p_metodo = 'GET' then
    return net.http_get(
      url := 'https://api.github.com/repos/JogzDev/canario' || p_caminho,
      headers := cabecalhos);
  end if;
  return net.http_post(
    url := 'https://api.github.com/repos/JogzDev/canario' || p_caminho,
    body := coalesce(p_corpo, '{}'::jsonb),
    headers := cabecalhos || jsonb_build_object('Content-Type', 'application/json'));
end;
$function$;

revoke all on function public._chamar_github(text, text, jsonb) from public, anon, authenticated, service_role;

create or replace function public.disparar_pipeline_diario()
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  pedido bigint;
begin
  if public._token_do_github() is null then
    return 'sem token github_pipeline no Vault: a reserva do GitHub segue sozinha';
  end if;
  insert into public.gatilhos_do_pipeline (tipo, data_operacional)
  values ('disparo', hoje)
  on conflict (tipo, data_operacional) do nothing;
  if not found then
    return 'o pipeline de ' || hoje || ' ja foi pedido';
  end if;
  pedido := public._chamar_github(
    'POST', '/actions/workflows/pipeline-diario.yml/dispatches',
    jsonb_build_object('ref', 'main'));
  update public.gatilhos_do_pipeline
     set pedidos = pedidos || pedido
   where tipo = 'disparo' and data_operacional = hoje;
  return 'pipeline de ' || hoje || ' pedido (pg_net ' || pedido || ')';
end;
$function$;

create or replace function public.registrar_respostas_do_pipeline()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  n integer;
begin
  update public.gatilhos_do_pipeline g
     set respostas = coalesce((
       select array_agg(r.status_code order by u.ordem)
       from unnest(g.pedidos) with ordinality as u(id, ordem)
       left join net._http_response r on r.id = u.id), '{}')
   where g.data_operacional >= (now() at time zone 'America/Sao_Paulo')::date - 1
     and (cardinality(g.respostas) < cardinality(g.pedidos)
          or array_position(g.respostas, null) is not null);
  get diagnostics n = row_count;
  return n;
end;
$function$;

create or replace function public.vigiar_pipeline_diario()
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  publicado date;
  resposta_da_manha text;
  corpo text;
  redisparo bigint;
  issue bigint;
begin
  select observado_em into publicado
  from public.observacoes_publicadas_do_painel
  where segmento = 'feminino_casual_br';
  if publicado >= hoje then
    return 'painel publicado em ' || publicado;
  end if;
  -- Saude de hoje gravada por uma fonte do PAINEL PRINCIPAL prova que o
  -- pipeline rodou; a falha dele tem a issue de incidente do job `alerta`.
  -- As coletas do catalogo candidato e da direcao internacional tem agenda
  -- propria e gravam saude das marcas delas: nao contam.
  if exists (select 1 from public.saude s
             left join public.marcas m on m.id = s.marca_id
             where s.data = hoje
               and (s.marca_id is null or m.segmento = 'feminino_casual_br')) then
    return 'o pipeline de ' || hoje || ' rodou; publicacao pendente fica com o alerta do pipeline';
  end if;
  if public._token_do_github() is null then
    return 'pipeline de ' || hoje || ' nao rodou e nao ha token para avisar';
  end if;
  insert into public.gatilhos_do_pipeline (tipo, data_operacional)
  values ('vigia', hoje)
  on conflict (tipo, data_operacional) do nothing;
  if not found then
    return 'a vigia ja agiu em ' || hoje;
  end if;

  perform public.registrar_respostas_do_pipeline();
  select coalesce(g.respostas[1]::text, 'sem resposta registrada')
    into resposta_da_manha
  from public.gatilhos_do_pipeline g
  where g.tipo = 'disparo' and g.data_operacional = hoje;

  redisparo := public._chamar_github(
    'POST', '/actions/workflows/pipeline-diario.yml/dispatches',
    jsonb_build_object('ref', 'main'));

  corpo := format(
    E'A coleta de %s nao comecou ate o meio-dia: nenhuma fonte gravou saude hoje, e o painel publicado continua em %s.\n\n'
    || E'- Pedido do Supabase as 03:17: %s (204 = aceito; 401 ou 403 = token vencido ou sem permissao; vazio = o pedido nao saiu).\n'
    || E'- A vigia acabou de pedir o pipeline de novo.\n\n'
    || E'Aberto pelo pg_cron do Supabase (A63). Feche quando a coleta do dia terminar.',
    to_char(hoje, 'DD/MM/YYYY'), coalesce(to_char(publicado, 'DD/MM/YYYY'), 'nenhuma data'),
    coalesce(resposta_da_manha, 'nenhum pedido registrado'));
  issue := public._chamar_github(
    'POST', '/issues',
    jsonb_build_object('title', 'O pipeline de ' || to_char(hoje, 'DD/MM') || ' nao rodou',
                       'body', corpo));
  update public.gatilhos_do_pipeline
     set pedidos = array[redisparo, issue]
   where tipo = 'vigia' and data_operacional = hoje;
  return 'pipeline de ' || hoje || ' pedido de novo e issue aberta';
end;
$function$;

create or replace function public.testar_token_do_github()
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  pedido bigint := public._chamar_github('GET', '');
begin
  if pedido is null then
    return 'sem token github_pipeline no Vault';
  end if;
  return 'teste enviado; leia net._http_response onde id = ' || pedido || ' (200 = token bom)';
end;
$function$;

revoke all on function public.disparar_pipeline_diario() from public, anon, authenticated, service_role;
revoke all on function public.vigiar_pipeline_diario() from public, anon, authenticated, service_role;
revoke all on function public.testar_token_do_github() from public, anon, authenticated, service_role;
revoke all on function public.registrar_respostas_do_pipeline() from public, anon, authenticated, service_role;

-- 03:17 BRT = 06:17 UTC; meio-dia BRT = 15:00 UTC. O pg_cron roda em UTC.
select cron.schedule('canario-disparo-diario', '17 6 * * *',
  $cron$select public.disparar_pipeline_diario();$cron$);
select cron.schedule('canario-vigia-do-pipeline', '0 15 * * *',
  $cron$select public.vigiar_pipeline_diario();$cron$);
select cron.schedule('canario-respostas-do-github', '27 * * * *',
  $cron$select public.registrar_respostas_do_pipeline();$cron$);
