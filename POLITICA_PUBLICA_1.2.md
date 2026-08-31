# Texto público para a 1.2 — conta opcional e sincronização

Substituir a política da 1.1 antes de enviar o build. O texto descreve o
binário implementado: conta opcional, atributos do Closet sincronizados,
miniatura reduzida em área privada da conta (A44), foto original somente no
aparelho e exclusão iniciada dentro do app.

> **Por que este arquivo mudou em 26/08.** Até esta revisão ele dizia que
> nenhuma imagem do Closet subia. A A44 entrou em produção em 25/08 e passou a
> sincronizar a miniatura reduzida; o `PrivacyInfo.xcprivacy` foi atualizado na
> mesma leva e este texto não. Documento público que descreve um binário
> diferente do publicado não é imprecisão: é declaração de privacidade errada.

```text
Privacy Policy

Effective August 30, 2026. DataDrobe is published by Fundação Padre Leonel
Franca. This policy describes version 1.2 of the iPhone app.

Summary

DataDrobe has no advertising and does not track you across apps or websites.
You can use the app without an account. If you choose to sign in, DataDrobe
syncs the structured details of your Closet, plus a reduced, metadata-free
thumbnail of each garment, so you can restore them on another device. The
original photo you took or picked never leaves this iPhone.

Optional account

You may create an account with email and password, Sign in with Apple, or
Google. Supabase provides authentication and processes your account identifier,
email address when supplied, encrypted session credentials, and the information
needed to operate the account. DataDrobe never receives your Apple or Google
password and does not store your email password itself.

The app stores its session in the iOS Keychain. Signing out removes that local
session. You can continue using DataDrobe without signing in.

Closet sync

When signed in, DataDrobe synchronizes the details you save for a garment:
its name, confirmed taxonomy attributes, target price, channel, creation date,
favorite state, and your similar-item preference. These records are linked to
your account so they can be restored. Row-level security restricts every record
to its owner. The app keeps working from its local copy when offline and merges
changes when a connection returns.

Closet thumbnails

When signed in, DataDrobe also uploads one reduced, metadata-free thumbnail per
garment, at most 720 pixels on its longest side, so your Closet still shows the
right picture after you reinstall the app or sign in on another iPhone. Each
file is stored in a private area addressed by your account identifier;
row-level security allows only your account to read, replace or delete it. The
app verifies a checksum before it accepts a downloaded thumbnail.

The original photo is never uploaded. Deleting a garment deletes its thumbnail.
Deleting your account deletes every thumbnail it stored. A signed-out, local
Closet remains confined to that iPhone: nothing about it leaves the device.

Account deletion

Account settings includes Delete account. Confirming it permanently deletes the
account, its synchronized Closet records and every thumbnail stored for it, and
removes the signed-in Closet and session from that iPhone. For new Sign in with
Apple sessions, DataDrobe securely retains the Apple refresh token only to call
Apple's revocation API when you delete the account, then deletes that token with
the account. If an older Apple session has no token available to revoke
programmatically, the app directs you to Apple Account settings after deletion
so you can remove the remaining authorization.

Photos and camera

Camera and Photo Library access happen only after you choose the corresponding
action. DataDrobe separates the garment from the background, measures dominant
colour and recognizes visible text on the device.

After you confirm the target garment, the app may separately ask permission to
send a reduced, metadata-free copy through a Supabase Edge Function to OpenAI
for attribute suggestions. The original is never uploaded. DataDrobe does not
store the submitted copy. OpenAI may retain abuse-monitoring logs for up to 30
days under its API policy. Every suggestion remains editable before saving.
Declining leaves on-device and manual entry available.

To prevent abuse of this optional service, the server stores for up to seven
days a salted, irreversible hash derived from the request origin, not the IP
address itself. It is used only to count recent requests.

Market data and retailer links

The app reads published market measurements from a read-only Supabase database.
Product images displayed for similar pieces load from the retailer's image host;
opening a store link uses that retailer's website and privacy policy.

What DataDrobe does not do

- No advertising identifier, advertising SDK, data broker or cross-app tracking.
- No sale of personal data.
- No collection of contacts, precise location, health or payment data.
- No upload of your original Closet photos, in any version.
- No Closet data of any kind leaves the iPhone while you are signed out.

Your choices

You can stay signed out, sign out at any time, delete individual garments, erase
the local Closet, or permanently delete a connected account inside the app. You
can revoke camera and photo access in iOS Settings.

Changes

This page is updated before a released version changes what leaves the device.

Contact

canarioch3@gmail.com
```
