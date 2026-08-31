-- A50 — credencial de revogação de Sign in with Apple.
--
-- O refresh token não é dado de produto nem pode ser lido pelo aplicativo.
-- Ele fica em uma tabela sem privilégios para `anon` ou `authenticated`; só a
-- service role das Edge Functions o usa para chamar a API REST da Apple quando
-- a própria pessoa pede exclusão da conta.

create table if not exists public.apple_refresh_tokens (
    user_id uuid primary key references auth.users(id) on delete cascade,
    refresh_token text not null check (
        length(refresh_token) between 16 and 4096
    ),
    atualizado_em timestamptz not null default now()
);

alter table public.apple_refresh_tokens enable row level security;
alter table public.apple_refresh_tokens force row level security;

revoke all on table public.apple_refresh_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.apple_refresh_tokens to service_role;

comment on table public.apple_refresh_tokens is
'A50: refresh token Apple guardado somente para revogacao REST durante exclusao da conta.';
