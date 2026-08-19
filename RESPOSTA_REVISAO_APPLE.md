# Resposta à revisão da Apple — Guideline 2.1, Information Needed

Rejeição de 14/08/2026, 21:25. **Não é bug nem crash.** A Apple pediu
informação para conseguir revisar; é das rejeições mais leves que existem.

Atenção à ordem: a rejeição foi sobre a build **0.1 (2)**, antiga. A resposta
tem de ir junto com a build **1.0 (1)** enviada, senão você grava um vídeo de um
app que não é o que vai publicar.

## Sequência

1. Subir a build 1.0 (1) pelo Organizer.
2. Instalar via TestFlight interno no seu iPhone.
3. Gravar a tela **no iPhone físico** (item 1 — só você faz).
4. Colar os textos abaixo em **Informações de revisão de apps → Notas**.
5. Responder na Central de Resoluções anexando o vídeo.

---

## Item 1 — Gravação de tela (sua, no iPhone)

A Apple exige aparelho físico. Simulador não é aceito.

No iPhone: Ajustes → Central de Controle → adicionar **Gravação de Tela**.
Abra a Central de Controle, grave, e faça este roteiro:

1. Comece na **tela de início do iOS**, tocando no ícone do DataDrobe. Eles
   exigem que o vídeo comece pelo lançamento do app.
2. Espere a tela **Add your clothes** carregar.
3. Toque em **Trends**. Espere os dados aparecerem e role a lista.
4. Toque em um termo (ex.: **Midi**) e mostre o relatório.
5. Volte e toque na **lupa**. Digite `floral` e mostre o resultado.
6. Volte para **Add** e toque em **+**.
7. Toque em **Choose from Photos**. **Deixe o pedido de permissão da fototeca
   aparecer na gravação e aceite** — eles pedem explicitamente que prompts de
   acesso a dados sensíveis apareçam no vídeo.
8. Escolha uma foto de roupa. Mostre a peça sendo isolada do fundo, a escolha do
   alvo e a confirmação dos atributos.
9. Mostre o painel de mercado da peça: preço, similares, grade.
10. Toque em **Take a photo** uma vez para o prompt da **câmera** aparecer
    também, e aceite.

Sem pressa e sem cortes. Vídeo de 2 a 3 minutos.

### Duas coisas para decidir ANTES de gravar

**O passo 8 pode travar por ~30 segundos no seu iPhone 15.** Foi o que você
relatou no vídeo de 18/08, e eu não consegui reproduzir no Mac — lá a mesma
operação leva 241 ms. A causa continua sem prova. Numa gravação de revisão, meio
minuto de tela parada parece app quebrado, e é exatamente o tipo de coisa que
gera uma segunda rejeição.

Duas saídas, e a escolha é sua:

* **Gravar no iPhone 16 do Davi**, onde o fluxo respondeu bem. Continua sendo
  aparelho físico, que é o que a Apple exige. É o que eu faria.
* **Gravar no seu**, e nesse caso não corte a espera: deixe a tela carregando no
  vídeo. Espera visível é honesta; corte no meio parece que você escondeu algo.

Se gravar no seu e demorar, me mande o vídeo — o tempo medido em aparelho real é
justamente a prova que falta para eu achar a causa.

**O passo 3 mudou hoje.** Até 19/08 a tela de tendências se chamava "Trends" no
iOS 26 e "Analytics" no iOS 17–25. Se você gravar com a build antiga num iPhone
com iOS 18, o vídeo mostra "Analytics" e este roteiro diz "Trends" — o revisor vê
divergência entre o que você escreveu e o que ele assiste. **Grave com a build
mais recente**, onde os dois dizem "Trends" em qualquer iPhone.

---

## Itens 2 a 7 — cole em Informações de revisão de apps → Notas

```
2. DEVICES AND OS TESTED

[PREENCHER COM O SEU APARELHO REAL, por exemplo:]
- iPhone 15 Pro, iOS 26.2
- iPhone 13, iOS 26.2

3. PURPOSE AND TARGET AUDIENCE

DataDrobe is a business tool for people who work in Brazilian women's fashion:
designers, buyers, product and merchandising teams at apparel brands.

The problem it solves: deciding what to produce is usually done on intuition, or
on sales data that only arrives after the season is over. DataDrobe shows what is
already observable in the market today — what comparable pieces cost across a
fixed cohort of brands, what has already been marked down, which sizes have gone
missing from the grid, and which attributes are drawing above-usual search
interest.

The app deliberately does not predict sales. It reports observed market state and
leaves the interpretation to the professional using it. There is no score, no
probability and no recommendation of how much to produce.

4. HOW TO ACCESS THE MAIN FEATURES

There is no account, no login, no paywall and no purchase. Every feature is
available immediately on first launch. No credentials are needed.

The app has four areas, reachable from the bar at the bottom:

- TRENDS is the fastest way to see the core value and needs no input at all.
  Launch the app and tap "Trends". It lists fashion attributes whose search
  interest in Brazil is above or below their own previous 12 weeks. Tapping any
  row opens a detailed report for that attribute.

- SEARCH (the magnifying glass) accepts an attribute or a plain description.
  Try "floral", "midi" or "polka-dot dress".

- ADD analyses a garment. Tap the "+" button, then "Choose from Photos" or
  "Take a photo", and pick any photo showing a single piece of clothing. The app
  separates the garment from the background on the device, measures its dominant
  colour locally, and reads any visible text on the device to spot a brand. You
  then confirm the attributes and see the market panel for that combination.

- CLOSET keeps the pieces you chose to save. It is empty until you save one.

SAMPLE FILE: any photo of a single garment works — a product photo saved from a
clothing website is ideal. If the review device has no such photo in its library,
please save one before testing the Add flow. The Trends and Search areas need no
file at all.

5. EXTERNAL SERVICES USED AT RUNTIME

- Supabase (PostgreSQL, REST API and Edge Functions). This is the only backend.
  The app performs read-only queries for the market index, weekly series, the
  approved attribute list, similar pieces, retail events and size curves. The app
  authenticates with a publishable API key; access is restricted by row-level
  security. There are no user accounts.

- Brand retailer image CDNs. Product images are hotlinked and rendered directly
  from the retailer's own servers. The app never copies, re-hosts or stores those
  images.

- OpenAI: a code path exists for optional garment attribute suggestion, but it is
  DISABLED in this build by the REMOTE_ANALYSIS_ENABLED build flag. Version 1.0
  makes no call to OpenAI or to any other AI service. All image processing in this
  version happens on the device, using Apple's Vision framework.

There is no analytics SDK, no advertising SDK, no third-party authentication and
no payment processor in the app.

NOTE ON THE PRIVACY MANIFEST

PrivacyInfo.xcprivacy in this build declares NSPrivacyCollectedDataTypePhotosorVideos,
with purpose App Functionality, not linked to identity and not used for tracking.
That declaration describes the optional cloud analysis path above. In version 1.0
that path is switched off by the REMOTE_ANALYSIS_ENABLED build flag and no photo
leaves the device.

We left the declaration in place rather than removing it. The app does request
photo library and camera access, and we would rather over-declare than ship a
manifest that understates what the app asks for. If you would prefer the manifest
to describe only what version 1.0 actually does, we will remove that entry in the
next build.

For completeness: the market database is built by a separate server-side pipeline
that reads public product catalogues of Brazilian retailers, public fashion
editorial coverage and Google Trends. That pipeline is not part of the app and is
never invoked from the device.

6. REGIONAL DIFFERENCES

None. The app behaves identically in every region and requires no regional
setup. Its data describes the Brazilian women's fashion market, so prices are
shown in Brazilian Real. The interface is in English. There is no geographic
gating and no region-specific feature.

7. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL

The app does not operate in a regulated industry.

Regarding third-party material: the app displays product photographs, product
titles and publicly listed prices from Brazilian fashion retailers, and links out
to the retailer's own website. Images are displayed by hotlink from the
retailer's own server and are never copied or re-hosted. [JP: confirme aqui com o
Davi a base sob a qual vocês exibem esse material e acrescente uma frase. Não
invente autorização que não existe.]
```

---

## Sobre as capturas de tela

A Apple citou a diretriz 2.3.3 nas dicas: capturas têm de mostrar o app em uso,
não arte de título nem tela de abertura. As três que geramos mostram telas reais
com dados reais, então estão certas.

Só uma observação: a de busca (`03-busca.png`) está bastante vazia. Se quiser
substituir por algo mais forte, eu capturo o relatório completo de uma peça
depois que a build nova estiver rodando — é a tela mais convincente do app.

## Os purpose strings estão bons

A Apple citou a 5.1.1 nas dicas. Conferi no binário e os dois já explicam
motivo e uso:

- Câmera: *"Take a garment photo to suggest its attributes. Before cloud
  analysis, DataDrobe shows exactly what will be sent and asks for your
  permission."*
- Fototeca: idem, com "Choose".

Nada a mudar.

## O que eu não posso fazer por você

O item 1 exige gravação em aparelho físico. Não tenho como. E o item 7 termina
numa afirmação jurídica sobre direitos de terceiros, que é sua e do Davi — eu
descrevi com precisão o que o app faz para vocês responderem com base em fato.
