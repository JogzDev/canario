# Ficha da App Store — DataDrobe 1.2 (build 1)

## What's New

```text
• Optional accounts with Apple, Google or email sign-in.
• Offline-first Closet sync across your signed-in devices; photos stay local.
• Account deletion directly inside DataDrobe.
• Secure password recovery and session storage in the iOS Keychain.
• Reliability and accessibility improvements.
```

## Trecho da descrição que substitui “No account”

```text
Your Closet works without an account. You may optionally sign in with Apple,
Google or email to synchronize and restore its item details across devices.
Closet photos stay on this iPhone in version 1.2. DataDrobe has no advertising
identifier and does not track you across apps or websites.
```

## App Privacy

| Tipo | Coletado | Ligado ao usuário | Finalidade |
|---|---:|---:|---|
| Contact Info → Email Address | sim | sim | App Functionality |
| Identifiers → User ID | sim | sim | App Functionality |
| User Content → Other User Content | sim | sim | App Functionality |
| Photos or Videos | sim | não | App Functionality |
| Identifiers → Device ID | sim | não | App Functionality |
| Data Used to Track You | não | — | — |

`Other User Content` cobre nome, atributos, preço-alvo, canal, favorito e
preferência de similares sincronizados. `Photos or Videos` continua cobrindo
somente a análise visual opcional da 1.1; as fotos do Closet não são
sincronizadas. `Device ID` é o balde adotado na 1.1 para o hash irreversível de
origem usado contra abuso.

**Photos or Videos collected:** Yes, not linked to the user. A cópia reduzida
passa pelo Supabase para a OpenAI somente após consentimento; a OpenAI pode
reter logs de monitoramento de abuso por **até 30 dias**.

## Review Notes

```text
Account creation is optional. Open the side menu and choose Account to test
Apple, Google or email sign-in. A signed-out user retains the complete local
workflow. When signed in, only structured Closet details sync; Closet photos
remain local. Account → Delete account permanently deletes the Supabase Auth
user and cascades deletion of all synchronized Closet rows, then removes the
signed-in Closet and Keychain session from the device.
```

Antes do envio: publicar `POLITICA_PUBLICA_1.2.md`, configurar a Privacy Policy
URL, fornecer uma conta de demonstração por e-mail ao App Review e confirmar
que Apple/Google estão ativos no ambiente de produção.
