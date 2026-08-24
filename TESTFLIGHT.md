# TestFlight — DataDrobe 1.2 (build 1)

Checklist iniciado em 24/08/2026.

- App publicado: **DataDrobe 1.1**.
- Próximo beta: **1.2 (build 1)**.
- Bundle: `br.com.canario.ch3.app`.
- Team: `67AYPRFZH8`.
- Idioma-fonte do app: inglês.
- Destino: iPhone, iOS 17+.
- Análise visual: Luna v8 ligada; cópia reduzida e sem metadados só é enviada
  após consentimento explícito.
- Upload atual: **ainda não enviado**.
- Archive: **ainda não gerado**.

## Envio

1. Rode todos os portões de `RELEASE_DATADROBE.md`.
2. Gere um Archive Release para **Any iOS Device (arm64)**.
3. No Organizer, use **Validate App**.
4. Escolha **Distribute App > TestFlight & App Store > Upload**.
5. Aguarde o processamento no App Store Connect e associe o build apenas ao
   grupo interno de teste.
6. Não selecione nem envie o build para App Review até concluir o aceite nos
   aparelhos físicos.

## What to Test

```text
DataDrobe 1.2 adds optional Apple, Google and email accounts, offline-first
Closet sync without photo upload, password recovery and in-app account deletion.

Please test camera, Photos and PDF/file import; target selection and crop;
the cloud-consent disclosure; guest use; all three sign-in methods; confirmation
and password-reset links; offline edits and conflict merge; signing out; account
deletion; saving, editing and deleting Closet items; favorites; Similar Pieces
and store links; scrolling over attribute chips; consistent light appearance,
larger text and VoiceOver.

Report any number whose source or date is unclear, any stale store link, any
photo sent without the separate confirmation, and any import wait that feels
stuck. DataDrobe describes observed market evidence; it does not predict sales.
```

## Portão do beta interno

Testar instalação limpa e atualização da 1.0 em pelo menos dois iPhones. Um
deles deve executar iOS 17 ou 18 para cobrir o visual de compatibilidade; o
outro pode usar a versão atual. Registrar modelo, iOS, duração da importação e
resultado de câmera/fototeca/offline.

O upload para TestFlight é permitido por este guia. O envio para App Review
continua sendo uma ação separada e deliberada.
