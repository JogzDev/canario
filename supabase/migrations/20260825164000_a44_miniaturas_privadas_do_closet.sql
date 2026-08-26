-- A44: restaura miniaturas do Closet para contas conectadas.
--
-- Nunca recebe a foto original. O cliente só envia a miniatura de até 720 px,
-- já recodificada sem EXIF/localização. O objeto é privado e o primeiro
-- componente do caminho precisa ser o próprio auth.uid().

alter table public.closet_items
    add column if not exists miniatura_hash text,
    add column if not exists miniatura_extensao text;

alter table public.closet_items
    drop constraint if exists closet_miniatura_hash_valido,
    add constraint closet_miniatura_hash_valido check (
        miniatura_hash is null or miniatura_hash ~ '^[0-9a-f]{64}$'
    ),
    drop constraint if exists closet_miniatura_extensao_valida,
    add constraint closet_miniatura_extensao_valida check (
        miniatura_extensao is null or miniatura_extensao in ('jpg', 'png')
    ),
    drop constraint if exists closet_miniatura_contrato_completo,
    add constraint closet_miniatura_contrato_completo check (
        (miniatura_hash is null) = (miniatura_extensao is null)
    );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'closet-thumbnails', 'closet-thumbnails', false, 3000000,
    array['image/jpeg', 'image/png']
)
on conflict (id) do update set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists closet_thumbnail_select_proprio on storage.objects;
create policy closet_thumbnail_select_proprio on storage.objects
for select to authenticated
using (
    bucket_id = 'closet-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists closet_thumbnail_insert_proprio on storage.objects;
create policy closet_thumbnail_insert_proprio on storage.objects
for insert to authenticated
with check (
    bucket_id = 'closet-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists closet_thumbnail_update_proprio on storage.objects;
create policy closet_thumbnail_update_proprio on storage.objects
for update to authenticated
using (
    bucket_id = 'closet-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
    bucket_id = 'closet-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists closet_thumbnail_delete_proprio on storage.objects;
create policy closet_thumbnail_delete_proprio on storage.objects
for delete to authenticated
using (
    bucket_id = 'closet-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Mantém o merge atômico da A26 e acrescenta somente o marcador da cópia
-- visual. O hash evita upload repetido em toda abertura do app.
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

    delete from public.closet_items
    where user_id = auth.uid()
      and removido_em < now() - interval '180 days';

    insert into public.closet_items (
        user_id, id, apelido, termo_ids, preco_alvo, canal, criada_em,
        favorita, similares_rejeitados, miniatura_hash, miniatura_extensao,
        atualizado_em, removido_em
    )
    select
        auth.uid(), x.id, x.apelido, x.termo_ids, x.preco_alvo, x.canal,
        x.criada_em, x.favorita, x.similares_rejeitados,
        x.miniatura_hash, x.miniatura_extensao,
        x.atualizado_em, x.removido_em
    from jsonb_to_recordset(coalesce(p_mudancas, '[]'::jsonb)) as x(
        id uuid, apelido text, termo_ids text[], preco_alvo numeric,
        canal text, criada_em timestamptz, favorita boolean,
        similares_rejeitados boolean, miniatura_hash text,
        miniatura_extensao text, atualizado_em timestamptz,
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
        miniatura_hash = excluded.miniatura_hash,
        miniatura_extensao = excluded.miniatura_extensao,
        atualizado_em = excluded.atualizado_em,
        removido_em = excluded.removido_em
    where excluded.atualizado_em > closet_items.atualizado_em
       or (
           excluded.atualizado_em = closet_items.atualizado_em
           and excluded.miniatura_hash is distinct from closet_items.miniatura_hash
       );

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
'A44: atributos do Closet e hash/formato da miniatura privada. Fotos originais nunca entram.';
