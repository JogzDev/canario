# Ficha da App Store — DataDrobe 1.1 (build 4)

Metadados do candidato de 21/08/2026. A ficha da 1.0 é histórica e não deve ser
copiada para este binário, porque dizia corretamente que nenhuma foto saía do
iPhone naquela versão. Na 1.1 a análise visual remota é opcional e consentida.

## Inglês — locale principal

**Subtitle**

```text
Fashion market, measured
```

**Promotional text**

```text
Add a garment and compare its confirmed attributes with current prices, markdowns, size availability and similar pieces across 15 Brazilian brands.
```

**What's New**

```text
• A clearer four-step flow for photos, files and PDFs.
• Optional visual suggestions after a separate cloud-consent step; every attribute remains editable.
• Local Closet thumbnails and favorites.
• Cleaner market reports that show only supported readings, with source and date details where relevant.
• Similar Pieces now require a current offer seen within the last seven days.
• Similar Pieces now always match the garment category.
• More reliable PDF analysis and attribute selection while scrolling.
• Reliability and accessibility improvements, including offline fallbacks and faster failure recovery.
```

**Description**

```text
DataDrobe organizes observed evidence from the Brazilian women's fashion market around the garment you are evaluating.

Add a garment, confirm its attributes and compare it with the monitored panel: current prices and markdowns, missing sizes, similar pieces with store links, and weekly readings for its attributes. Published readings include their sources and dates. Your Closet stays on this iPhone and requires no account.

When you choose a photo, DataDrobe reads color and visible text on the device. After you confirm the target garment, you may separately allow a reduced, metadata-free copy to be sent through Supabase to OpenAI for visual attribute suggestions. The submitted image is not stored by DataDrobe, and you review or replace every suggestion before saving. Manual entry remains available if you decline or the service is unavailable.

DataDrobe does not predict sales, rank a garment's chance of success or make purchasing decisions. It describes prices, availability, coverage and market signals that have already been observed.

No account, no advertising identifier and no tracking.
```

**Keywords**

```text
fashion,apparel,retail,pricing,markdown,brands,buying,merchandising,sizing,market,data
```

## Português (Brasil)

**Novidades**

```text
• Um fluxo mais claro em quatro etapas para fotos, arquivos e PDFs.
• Sugestões visuais opcionais após consentimento separado para a nuvem; todo atributo continua editável.
• Miniaturas locais e favoritos no Closet.
• Relatórios mais limpos, exibindo somente leituras sustentadas, com fonte e data quando relevantes.
• Peças similares agora exigem oferta atual vista nos últimos sete dias.
• Melhorias de confiabilidade, acessibilidade e uso offline.
```

## App Privacy

Responder de acordo com o binário:

| Pergunta | Resposta |
|---|---|
| Data Used to Track You | **No** |
| Data Linked to You | **No** |
| Photos or Videos collected | **Yes** |
| Purpose | **App Functionality** |
| Account/contact/payment/precise location/advertising ID | **No** |

Explicação para Review Notes: somente a cópia reduzida e sem metadados da peça
confirmada cruza o aparelho, depois de consentimento separado, via Supabase para
OpenAI. O DataDrobe não guarda a imagem enviada. A OpenAI pode manter logs de
monitoramento de abuso por até 30 dias. A miniatura do Closet fica apenas no
iPhone e é apagada junto com a peça.

## URLs e copyright

| Campo | Valor |
|---|---|
| Support URL | `https://datadrobe.carrd.co` |
| Marketing URL | `https://datadrobe.carrd.co` |
| Privacy Policy URL | `https://datadrobe.carrd.co/#privacy` |
| Copyright | `2026 Fundação Padre Leonel Franca` |

Antes de uma futura App Review, abrir a URL de privacidade fora de uma sessão
autenticada e confirmar que ela descreve a análise remota da 1.1. O upload para
TestFlight não substitui essa conferência.
