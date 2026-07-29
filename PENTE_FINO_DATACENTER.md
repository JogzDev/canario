# Pente fino do datacenter — 4 casos-limite

**Executado (UTC):** 2026-07-29T18:26:11.745904+00:00


| Marca | Plataforma | Tentativas HTTP | JSON | Veredito |
|---|---|---|---|---|
| Colcci | vtex | 403 → 403 | não | 403 confirmado do datacenter — politica da loja, falha definitiva (regra 7) |
| Centauro | vtex | 403 → 403 | não | 403 confirmado do datacenter — politica da loja, falha definitiva (regra 7) |
| Amaro | shopify | 429 → 429 | não | 429 persistiu apos backoff longo — aguarda; nao forcar (regra 7) |
| PatBo | shopify | 200 | sim | ABRIU — catalogo valido do datacenter |
| Maria Filo | vtex | mariafilo:206 | sim | ABRIU pelo host da plataforma (conta 'mariafilo'), com autorizacao escrita do cliente |
| Fabula | vtex | afabula:404 → fabula:206 | sim | ABRIU pelo host da plataforma (conta 'fabula'), com autorizacao escrita do cliente |

**Nenhuma promoção:** os vereditos acima são finais para esta temporada.


Regra 7: nenhum proxy nem header alternativo. Só diagnóstico honesto.
