-- A Edge Function de visão é chamada por um app sem conta. A publishable key
-- identifica o projeto, mas é pública por desenho; portanto ela não pode ser o
-- único freio de custo. Esta reserva atômica limita cada origem e o projeto por
-- dia antes de qualquer chamada paga à OpenAI.

create table if not exists public._limites_analise_visual (
    dia date not null,
    origem_hash text not null check (length(origem_hash) = 64),
    requisicoes integer not null default 0 check (requisicoes >= 0),
    primary key (dia, origem_hash)
);

alter table public._limites_analise_visual enable row level security;
revoke all on table public._limites_analise_visual from public, anon, authenticated;

create or replace function public._reservar_analise_visual(
    p_origem_hash text,
    p_limite_origem integer default 12,
    p_limite_global integer default 120
)
returns table (permitida boolean, motivo text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
    v_origem integer;
    v_global bigint;
begin
    if p_origem_hash !~ '^[0-9a-f]{64}$'
       or p_limite_origem not between 1 and 100
       or p_limite_global not between 1 and 10000 then
        return query select false, 'invalid_limit_request'::text;
        return;
    end if;

    -- Uma trava por dia torna a leitura + incremento uma única decisão. Sem
    -- isso, duas instâncias simultâneas poderiam atravessar o mesmo último slot.
    perform pg_advisory_xact_lock(hashtext('analise_visual:' || v_dia::text));

    delete from public._limites_analise_visual
    where dia < v_dia - 7;

    select coalesce(sum(requisicoes), 0)
      into v_global
      from public._limites_analise_visual
     where dia = v_dia;

    if v_global >= p_limite_global then
        return query select false, 'daily_project_limit'::text;
        return;
    end if;

    select requisicoes
      into v_origem
      from public._limites_analise_visual
     where dia = v_dia and origem_hash = p_origem_hash;

    if coalesce(v_origem, 0) >= p_limite_origem then
        return query select false, 'daily_origin_limit'::text;
        return;
    end if;

    insert into public._limites_analise_visual (dia, origem_hash, requisicoes)
    values (v_dia, p_origem_hash, 1)
    on conflict (dia, origem_hash) do update
        set requisicoes = public._limites_analise_visual.requisicoes + 1;

    return query select true, 'reserved'::text;
end;
$$;

revoke all on function public._reservar_analise_visual(text, integer, integer)
    from public, anon, authenticated;
grant execute on function public._reservar_analise_visual(text, integer, integer)
    to service_role;

comment on table public._limites_analise_visual is
    'Contadores efêmeros e pseudonimizados do limite de custo da análise visual; nunca guarda IP ou imagem.';
