-- A26: conta opcional e sincronização dos dados estruturados do Closet.
--
-- Esta migração pode ser aplicada no projeto atual ou num segundo projeto
-- Supabase dedicado à identidade. Ela não concede nenhuma leitura pública.

create table if not exists public.closet_items (
    user_id uuid not null references auth.users(id) on delete cascade,
    id uuid not null,
    apelido text,
    termo_ids text[],
    preco_alvo numeric,
    canal text,
    criada_em timestamptz,
    favorita boolean,
    similares_rejeitados boolean,
    atualizado_em timestamptz not null default now(),
    removido_em timestamptz,
    primary key (user_id, id),
    constraint closet_apelido_curto check (apelido is null or length(apelido) <= 160),
    constraint closet_canal_curto check (canal is null or length(canal) <= 80),
    constraint closet_taxonomia_limitada check (
        termo_ids is null or cardinality(termo_ids) <= 24
    ),
    constraint closet_ativo_tem_conteudo check (
        removido_em is not null
        or (apelido is not null and termo_ids is not null and criada_em is not null)
    )
);

alter table public.closet_items enable row level security;
alter table public.closet_items force row level security;

revoke all on table public.closet_items from public, anon, authenticated;
grant select on table public.closet_items to authenticated;

drop policy if exists closet_select_proprio on public.closet_items;
create policy closet_select_proprio on public.closet_items
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists closet_insert_proprio on public.closet_items;
create policy closet_insert_proprio on public.closet_items
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists closet_update_proprio on public.closet_items;
create policy closet_update_proprio on public.closet_items
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists closet_delete_proprio on public.closet_items;
create policy closet_delete_proprio on public.closet_items
for delete to authenticated
using (user_id = (select auth.uid()));

-- O cliente fornece a data para ordenar edições feitas offline. O servidor
-- recusa relógio absurdamente no futuro, que poderia ganhar de toda alteração
-- legítima para sempre.
create or replace function public.validar_closet_item()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
    if new.atualizado_em > now() + interval '10 minutes' then
        raise exception 'closet_updated_at_in_future';
    end if;
    if new.removido_em is not null and new.removido_em > new.atualizado_em then
        raise exception 'closet_removed_after_update';
    end if;
    return new;
end;
$$;

drop trigger if exists validar_closet_item on public.closet_items;
create trigger validar_closet_item
before insert or update on public.closet_items
for each row execute function public.validar_closet_item();

create index if not exists closet_items_usuario_atualizacao
on public.closet_items (user_id, atualizado_em desc);

-- Um upsert REST comum poderia deixar uma edição antiga terminar depois de
-- uma nova e vencê-la por ordem de chegada. A função compara a versão dentro
-- do mesmo comando atômico e só aceita a mudança mais recente.
create or replace function public.aplicar_mudancas_closet(p_mudancas jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if jsonb_typeof(coalesce(p_mudancas, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_mudancas, '[]'::jsonb)) > 250 then
        raise exception 'closet_batch_too_large';
    end if;

    -- Tombstones impedem que um aparelho muito desatualizado ressuscite uma
    -- peça apagada. Depois de seis meses, deixam de comprar confiabilidade e
    -- passam a ser só crescimento; a limpeza fica confinada ao próprio dono.
    delete from public.closet_items
    where user_id = auth.uid()
      and removido_em < now() - interval '180 days';

    insert into public.closet_items (
        user_id, id, apelido, termo_ids, preco_alvo, canal, criada_em,
        favorita, similares_rejeitados, atualizado_em, removido_em
    )
    select
        auth.uid(), x.id, x.apelido, x.termo_ids, x.preco_alvo, x.canal,
        x.criada_em, x.favorita, x.similares_rejeitados,
        x.atualizado_em, x.removido_em
    from jsonb_to_recordset(coalesce(p_mudancas, '[]'::jsonb)) as x(
        id uuid, apelido text, termo_ids text[], preco_alvo numeric,
        canal text, criada_em timestamptz, favorita boolean,
        similares_rejeitados boolean, atualizado_em timestamptz,
        removido_em timestamptz
    )
    on conflict (user_id, id) do update set
        apelido = excluded.apelido,
        termo_ids = excluded.termo_ids,
        preco_alvo = excluded.preco_alvo,
        canal = excluded.canal,
        criada_em = excluded.criada_em,
        favorita = excluded.favorita,
        similares_rejeitados = excluded.similares_rejeitados,
        atualizado_em = excluded.atualizado_em,
        removido_em = excluded.removido_em
    where excluded.atualizado_em > closet_items.atualizado_em;

    if (select count(*) from public.closet_items
        where user_id = auth.uid() and removido_em is null) > 200 then
        raise exception 'closet_active_item_limit';
    end if;
    if (select count(*) from public.closet_items
        where user_id = auth.uid()) > 400 then
        raise exception 'closet_total_item_limit';
    end if;
end;
$$;

revoke all on function public.aplicar_mudancas_closet(jsonb) from public, anon;
grant execute on function public.aplicar_mudancas_closet(jsonb) to authenticated;

comment on table public.closet_items is
'A26: dados digitados no Closet. Fotos e leituras calculadas nunca entram.';
