# Ficha da App Store — DataDrobe 1.2 (build 2)

## Inglês — locale principal

### Subtitle

```text
Fashion market, measured
```

### Promotional text

```text
Add a garment and compare its confirmed attributes with observed prices, markdowns, size availability and similar pieces in Brazil's fashion market.
```

### Description

```text
DataDrobe organizes observed evidence from the Brazilian women's fashion market around the garment you are evaluating.

Add a garment, confirm its attributes and compare it with the monitored panel: observed prices and markdowns, size availability, similar pieces with store links, weekly market readings and editorial references. Dates and coverage stay visible so old or incomplete evidence is not presented as current.

Your Closet works without an account. You can optionally sign in with Apple, Google or email to synchronize and restore structured item details and a reduced, metadata-free thumbnail across your signed-in devices. Original photos stay on this iPhone. You can delete your account and synchronized data inside the app.

When you choose a photo, DataDrobe reads color and visible text on the device. After you confirm the target garment, you may separately allow a reduced, metadata-free copy to be sent through Supabase to OpenAI for visual attribute suggestions. DataDrobe does not store the submitted copy, and you review or replace every suggestion before saving. Manual entry remains available if you decline or the service is unavailable.

DataDrobe does not predict sales, rank a garment's chance of success or make purchasing decisions. It describes prices, availability, coverage and market signals that have already been observed.

No advertising identifier, no advertising and no tracking.
```

### Keywords

```text
fashion,apparel,retail,pricing,markdown,brands,buying,merchandising,sizing,market,data
```

## What's New

```text
• Optional accounts with Apple, Google or email sign-in.
• Offline-first Closet sync across your signed-in devices, including a private,
  reduced thumbnail per item; your original photos never leave the iPhone.
• Account deletion directly inside DataDrobe.
• Secure password recovery and session storage in the iOS Keychain.
• Reliability and accessibility improvements.
```

## Português (Brasil) — se o locale continuar ativo no App Store Connect

### Novidades

```text
• Conta opcional com início de sessão pela Apple, Google ou e-mail.
• Sincronização offline-first do Closet entre seus aparelhos conectados, incluindo uma miniatura privada e reduzida por peça; suas fotos originais nunca saem do iPhone.
• Exclusão da conta diretamente no DataDrobe.
• Recuperação segura de senha e sessão protegida no Chaves do iOS.
• Melhorias de confiabilidade e acessibilidade.
```

## Copy de apoio — já incorporada à Description acima

Não copiar este bloco como um campo separado. Ele registra a substituição da
frase antiga “No account” e serve para conferir outras superfícies da loja.

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
For a new Sign in with Apple session, the server first revokes the retained
Apple refresh token through Apple's REST API. An older Apple session that has
no revocation token receives the official Apple Account fallback after its data
has still been deleted.
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
