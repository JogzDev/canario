# Texto público para a 1.2 — conta opcional e sincronização

Substituir a política da 1.1 antes de enviar o build. O texto descreve o
binário implementado: conta opcional, fotos locais, atributos do Closet
sincronizados e exclusão iniciada dentro do app.

```text
Privacy Policy

Effective August 30, 2026. DataDrobe is published by Fundação Padre Leonel
Franca. This policy describes version 1.2 of the iPhone app.

Summary

DataDrobe has no advertising and does not track you across apps or websites.
You can use the app without an account. If you choose to sign in, DataDrobe
syncs the structured details of your Closet so you can restore them on another
device. Closet photos remain on the iPhone in this version.

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

Closet thumbnails and original photos are not uploaded as part of account sync
in version 1.2. A signed-out, local Closet remains confined to that iPhone.

Account deletion

Account settings includes Delete account. Confirming it permanently deletes
the account and its synchronized Closet data and removes the signed-in Closet
and session from that iPhone. If you used Sign in with Apple and no Apple token
is available to revoke programmatically, the app directs you to Apple Account
settings after deletion so you can remove the remaining authorization.

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
- No Closet-photo sync in version 1.2.

Your choices

You can stay signed out, sign out at any time, delete individual garments, erase
the local Closet, or permanently delete a connected account inside the app. You
can revoke camera and photo access in iOS Settings.

Changes

This page is updated before a released version changes what leaves the device.

Contact

canarioch3@gmail.com
```
