# Ficha da App Store — DataDrobe 1.0

Escrito em 15/08/2026, conferido contra o banco de produção e contra o binário
que saiu do Archive de hoje. Copie campo a campo no App Store Connect.

## Por que o texto anterior foi reescrito

O texto que você me mandou dizia, nas duas línguas, que o app faz entender
*"how it will perform in the current market"* / *"como ela vai performar no
mercado"*.

Dois problemas somados:

1. **Regra 1 do projeto.** O `CANARIO.md` abre proibindo qualquer texto que
   afirme ou sugira quanto uma peça vai vender, com lista negra de vocabulário
   e teste automatizado. Prometer previsão na loja contradiz a única coisa que
   sustenta a credibilidade do produto.
2. **Diretriz 2.3 da Apple**, metadados precisos. A análise visual está
   desligada nesta build (`REMOTE_ANALYSIS_ENABLED` vazio no Info.plist do
   IPA). Prometer análise automática de foto renderia rejeição.

O texto abaixo troca promessa de futuro por leitura de mercado observada. Não
é mais fraco: é o que o app realmente entrega, com números conferidos.

## Números usados, e de onde vêm

| Afirmação | Valor | Fonte |
|---|---|---|
| Marcas | **15** | marcas com peça ativa no segmento; a tabela tem 32 linhas, mas só 15 têm produto |
| Peças ativas | **~69.000** | `ultimo_snapshot_em` nos últimos 14 dias |
| Atributos | **41** | termos com `status='aprovado'` |
| Série do índice | desde **2021** | `indices_semanais`, 257 semanas — vem das pernas editorial e busca |
| Preço e grade | desde **24/07/2026** | primeiro snapshot de varejo |

Não misture as duas últimas linhas num só número. O índice tem cinco anos de
série; a observação de preço e grade tem três semanas. As duas coisas são
verdade e medem coisas diferentes.

---

# Inglês (locale principal)

## Subtitle (máx. 30)

```
Fashion market, measured
```

## Promotional text (máx. 170)

```
Add a piece, tag what it is, and see what 15 Brazilian brands are doing with the same attributes right now: prices, markdowns, size grids, and the closest pieces.
```

## Description

```
DataDrobe reads the women's fashion market from your product's point of view.

Add a garment, tag what it is, and DataDrobe shows you what the market is already doing with that same combination of attributes.

WHAT YOU GET

• Price and markdown — what comparable pieces cost across the cohort, what is still at full price and what is already discounted.
• Size grids — which sizes have gone missing from comparable pieces. A grid breaking is a signal you can read today.
• Similar pieces — the closest garments in the catalogue, with brand, price, current availability and a link to the store.
• Weekly attribute index — how each attribute has behaved week by week, with series going back to 2021 from editorial and search coverage.
• Your closet — every piece you add, with its own report and comparison between your pieces.

WHAT IT DOES NOT DO

DataDrobe never predicts sales. No score, no probability, no "this will sell". It shows what has already been observed in the market: prices, markdowns, availability, coverage. The reading is yours to make.

HOW IT READS YOUR PHOTO

When you add a photo, the garment is separated from the background on your device, its dominant colour is measured locally, and visible text is read on-device to spot a brand. You confirm every attribute before it is used. In this version, no photo leaves your iPhone.

THE DATA

15 Brazilian women's fashion brands. Around 69,000 pieces currently active, observed daily. Prices, size grids and stock changes recorded as they happen, across 41 approved attributes.

PRIVACY

No account. No tracking. No advertising identifier. Photos are processed on the device.
```

## Keywords (máx. 100 caracteres, sem espaço depois da vírgula)

```
fashion,apparel,retail,pricing,markdown,brands,buying,merchandising,catalog,sizing,market,data
```

## What's New

```
First release.
```

---

# Português (Brasil)

## Subtitle (máx. 30)

```
Mercado de moda, medido
```

## Promotional text (máx. 170)

```
Adicione uma peça, marque o que ela é, e veja o que 15 marcas brasileiras estão fazendo com os mesmos atributos agora: preço, desconto, grade e as peças mais próximas.
```

## Description

```
O DataDrobe lê o mercado de moda feminina pela perspectiva do seu produto.

Adicione uma peça, marque o que ela é, e o DataDrobe mostra o que o mercado já está fazendo com essa mesma combinação de atributos.

O QUE VOCÊ VÊ

• Preço e desconto — quanto custam as peças comparáveis na coorte, o que ainda está a preço cheio e o que já foi remarcado.
• Grade de tamanhos — quais tamanhos sumiram das peças comparáveis. Grade quebrando é sinal que dá para ler hoje.
• Peças similares — as roupas mais próximas do catálogo, com marca, preço, disponibilidade atual e link para a loja.
• Índice semanal por atributo — como cada atributo se comportou semana a semana, com série desde 2021 vinda das pernas editorial e de busca.
• Seu armário — cada peça adicionada, com relatório próprio e comparação entre as suas peças.

O QUE ELE NÃO FAZ

O DataDrobe não prevê vendas. Nenhum score, nenhuma probabilidade, nenhum "isso vai vender". Ele mostra o que já foi observado no mercado: preço, remarcação, disponibilidade, cobertura. A leitura é sua.

COMO ELE LÊ SUA FOTO

Ao adicionar uma foto, a peça é separada do fundo no próprio aparelho, a cor predominante é medida localmente, e o texto visível é lido no dispositivo para identificar uma marca. Você confirma cada atributo antes do uso. Nesta versão, nenhuma foto sai do seu iPhone.

OS DADOS

15 marcas brasileiras de moda feminina. Cerca de 69.000 peças ativas, observadas diariamente. Preço, grade e mudança de estoque registrados conforme acontecem, em 41 atributos aprovados.

PRIVACIDADE

Sem conta. Sem rastreamento. Sem identificador de anúncio. Fotos processadas no aparelho.
```

## Keywords (máx. 100 caracteres)

```
moda,varejo,preço,remarcação,marcas,compras,coleção,grade,tamanho,mercado,dados,estratégia
```

## Novidades

```
Primeira versão.
```

---

# URLs — atenção, os campos estavam trocados

Você tinha "URL de marketing" apontando para `#privacy`. São três campos
distintos no App Store Connect:

| Campo | Valor |
|---|---|
| Support URL | `https://datadrobe.carrd.co` |
| Marketing URL | `https://datadrobe.carrd.co` |
| Privacy Policy URL | `https://datadrobe.carrd.co/#privacy` |

A Privacy Policy URL é obrigatória e é verificada na revisão. Confirme com o
Davi que a âncora `#privacy` mostra uma política de verdade, e não uma seção
vazia — a Apple abre esse link.

# Copyright

```
2026 Fundação Padre Leonel Franca
```

O nome do detentor deve bater com o time da conta de desenvolvedor, que é
quem publica. Se a intenção era publicar como DataDrobe, isso não se resolve
no campo de copyright: resolve-se na conta.

# Duas correções menores do texto original

- "acamponhando" → "acompanhando".
- "da perspective do seu produto" → "da perspectiva do seu produto".

# Uma promessa que foi retirada

O texto original dizia "Add your clothing's **sketch** or picture". O app
aceita imagem e PDF, então um croqui passa pelo mesmo caminho — mas nada foi
ajustado ou medido para croqui. Prometer isso na loja é convidar uma review de
uma estrela de quem tentar. Voltamos a incluir quando estiver testado.

# O que precisa mudar quando a Luna for ligada

A frase "Nesta versão, nenhuma foto sai do seu iPhone" é verdade **hoje**, com
`REMOTE_ANALYSIS_ENABLED` desligado. No dia em que a Edge Function entrar, esta
linha e a resposta do App Privacy têm de mudar junto, no mesmo envio. Deixar
para depois é declaração falsa de privacidade, que é assunto sério na Apple.
