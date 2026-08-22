# TestFlight — DataDrobe 1.1 (build 5)

Checklist ativo em 21/08/2026.

- App publicado: **DataDrobe 1.0**.
- Próximo beta: **1.1 (build 5)**.
- Bundle: `br.com.canario.ch3.app`.
- Team: `67AYPRFZH8`.
- Idioma-fonte do app: inglês.
- Destino: iPhone, iOS 17+.
- Análise visual: Luna v8 ligada; cópia reduzida e sem metadados só é enviada
  após consentimento explícito.
- Upload anterior: **build 4 aceito pelo App Store Connect às 19:49 de
  21/08/2026**, sem submissão à App Review.
- Build 5: correções do Compare, curva de tamanhos por atributo, ajuda e
  hierarquia visual dos sinais; aguardando archive e upload.

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
DataDrobe 1.1 adds a four-step item flow, optional cloud visual suggestions,
manual correction of every suggested attribute, local Closet thumbnails,
favorites, clearer market reports, and fresher Similar Pieces links.

Please test camera, Photos and PDF/file import; target selection and crop;
the cloud-consent disclosure; manual fallback while offline or after a refused
analysis; saving, editing and deleting Closet items; favorites; Similar Pieces
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
