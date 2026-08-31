# Ficha da App Store — DataDrobe 1.2 (build 1)

## What's New

```text
• Optional accounts with Apple, Google or email sign-in.
• Offline-first Closet sync across your signed-in devices, including a private,
  reduced thumbnail per item; your original photos never leave the iPhone.
• Account deletion directly inside DataDrobe.
• Secure password recovery and session storage in the iOS Keychain.
• Reliability and accessibility improvements.
```

## Trecho da descrição que substitui “No account”

```text
Your Closet works without an account. You may optionally sign in with Apple,
Google or email to synchronize and restore its item details across devices,
along with a reduced, metadata-free thumbnail kept in your own private space.
Your original photos stay on this iPhone. DataDrobe has no advertising
identifier and does not track you across apps or websites.
```

## App Privacy

| Tipo | Coletado | Ligado ao usuário | Finalidade |
|---|---:|---:|---|
| Contact Info → Email Address | sim | sim | App Functionality |
| Identifiers → User ID | sim | sim | App Functionality |
| User Content → Other User Content | sim | sim | App Functionality |
| Usage Data → Product Interaction | sim | sim | App Functionality |
| Photos or Videos | sim | **sim** | App Functionality |
| Identifiers → Device ID | sim | não | App Functionality |
| Data Used to Track You | não | — | — |

`Other User Content` cobre nome, atributos, preço-alvo e canal sincronizados.
`Product Interaction` cobre o favorito e a escolha explícita sobre similares.
`Device ID` é o balde adotado na 1.1 para o hash irreversível de origem usado
contra abuso. A Apple orienta classificar IP armazenado de acordo com o uso;
esse hash não é ligado à conta e não é usado para rastreamento.

**Photos or Videos collected:** Yes, **linked to the user**. A 1.1 tinha um uso
só, anônimo; a 1.2 tem dois, e a Apple pede uma linha por tipo de dado — basta
um uso vinculado para a linha inteira ser declarada vinculada.

| Uso | Vinculado | O que é |
|---|---|---|
| Análise visual opcional (1.1, inalterada) | não | cópia reduzida que passa pelo Supabase para a OpenAI **somente após consentimento separado**; não é atrelada a conta, e a OpenAI pode reter logs de monitoramento de abuso por **até 30 dias** |
| Miniatura do Closet (A44, nova na 1.2) | **sim** | uma miniatura reduzida e sem metadados por peça, com no máximo 720 px no maior lado, gravada em área privada endereçada pelo identificador da conta, com RLS por `auth.uid()` e checksum verificado |

A foto original **nunca** é enviada em nenhum dos dois usos. Sem conta, nenhuma
imagem do Closet sai do aparelho. Isto é o que o
[`PrivacyInfo.xcprivacy`](app/Canario/PrivacyInfo.xcprivacy) declara com
`NSPrivacyCollectedDataTypeLinked = true`; a ficha e o manifesto têm de dizer a
mesma coisa, e `coletor/teste_privacidade_declarada.py` reprova o push se
divergirem.

## Review Notes

```text
Account creation is optional. Open the side menu and choose Account to test
Apple, Google or email sign-in. A signed-out user retains the complete local
workflow, and nothing about a signed-out Closet leaves the device.

When signed in, DataDrobe syncs structured Closet details plus one reduced,
metadata-free thumbnail per item (720 px maximum) into a private storage area
addressed by the account identifier. Row-level security limits every read,
write and delete to the owning account. Original photos are never uploaded.

Account → Delete account removes every stored thumbnail first, then permanently
deletes the Supabase Auth user and cascades deletion of all synchronized Closet
rows, then removes the signed-in Closet and Keychain session from the device.
```

Antes do envio: publicar `POLITICA_PUBLICA_1.2.md`, configurar a Privacy Policy
URL, fornecer uma conta de demonstração por e-mail ao App Review e confirmar
que Apple/Google estão ativos no ambiente de produção.

## URLs e copyright

| Campo | Valor |
|---|---|
| Support URL | `https://datadrobe.carrd.co` |
| Marketing URL | `https://datadrobe.carrd.co` |
| Privacy Policy URL | `https://datadrobe.carrd.co/#privacy` |
| Copyright | `2026 Fundação Padre Leonel Franca` |

O site público precisa conter integralmente o texto de
`POLITICA_PUBLICA_1.2.md` antes de selecionar este build para revisão. Em
31/08/2026 a URL ainda mostrava a política efetiva em 22/08/2026, que descreve
o comportamento anterior e não cobre conta nem sincronização.
