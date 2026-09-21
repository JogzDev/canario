-- A59 — cifra de aplicacao para o refresh token de revogacao Apple.
--
-- A50 retirou a credencial da superficie do cliente, mas ela ainda ficava em
-- claro para quem obtivesse leitura administrativa do banco. A59 permite a
-- transicao sem interromper Delete account: linhas existentes continuam
-- legiveis pelas Edge Functions e o proximo login Apple as regrava com
-- AES-256-GCM. A migration mantem o formato antigo temporariamente para que
-- a Edge Function ainda publicada nao quebre entre schema e deploy; o codigo
-- novo so escreve cifras. A chave vive somente nos secrets das Edge Functions
-- e `versao_chave` torna a rotacao explicita.

alter table public.apple_refresh_tokens
    add column if not exists refresh_token_cifrado text,
    add column if not exists nonce_cifragem text,
    add column if not exists versao_chave smallint,
    add column if not exists algoritmo_cifragem text;

alter table public.apple_refresh_tokens
    alter column refresh_token drop not null;

alter table public.apple_refresh_tokens
    drop constraint if exists apple_refresh_tokens_formato_cifrado_check;

alter table public.apple_refresh_tokens
    add constraint apple_refresh_tokens_formato_cifrado_check check (
        (
            refresh_token is not null
            and refresh_token_cifrado is null
            and nonce_cifragem is null
            and versao_chave is null
            and algoritmo_cifragem is null
        )
        or
        (
            refresh_token is null
            and refresh_token_cifrado is not null
            and length(refresh_token_cifrado) between 24 and 8192
            and nonce_cifragem is not null
            and length(nonce_cifragem) = 16
            and versao_chave is not null
            and versao_chave between 1 and 32767
            and algoritmo_cifragem is not null
            and algoritmo_cifragem = 'aes-256-gcm-v1'
        )
    );

comment on column public.apple_refresh_tokens.refresh_token is
'A59: legado transitorio A50; o codigo novo nunca grava esta coluna.';
comment on column public.apple_refresh_tokens.refresh_token_cifrado is
'A59: refresh token cifrado por AES-256-GCM na Edge Function.';
comment on column public.apple_refresh_tokens.versao_chave is
'A59: seleciona APPLE_REFRESH_TOKEN_KEY_V<n> para permitir rotacao.';
