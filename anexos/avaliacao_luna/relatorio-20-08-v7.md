# Luna v7 — o portão fechou, e o motivo não é a v7

## O que foi medido

Rodada de 20/08/2026, 24 imagens, com segmentador, prompt `alvo-estrutura-v7`
(`45f9ce7e…`). Custo US$ 0,0176, duração 165 s.

| medida | v5 | v6 | **v7** | portão |
|---|---:|---:|---:|---:|
| categoria | 20/24 — 83,3% | 20/24 — 83,3% | **19/24 — 79,2%** | ≥ 80% |
| cor primária | 22/24 — 91,7% | 22/24 — 91,7% | **19/24 — 79,2%** | ≥ 80% |

**Portão: FECHADO.** `anexos/portao_luna_24.json` passa a registrar a v7 com
`passed: false`, e o benchmark de 300 continua bloqueado — agora por uma medida
real da v7, não por divergência de hash com a v6.

## O que a v7 mudou no prompt

Só o parágrafo de cor. O diff inteiro:

> `Ignore colors from another garment, tiny trim, buttons, `**`zippers, `**`crystals,
> shadows, skin, and background.`**` Also ignore brand marks: a logo, a chest
> patch, a woven label, a tag, a printed wordmark, or embroidery is not a color
> of the garment, however saturated it is. A grey fleece with a purple brand
> patch is grey, not grey and purple.`**

Nenhuma palavra sobre escolher o alvo. E é exatamente na escolha do alvo que a
rodada se moveu.

## As mesmas imagens, quatro rodadas

| imagem | v5 | v5 + segmentador | v6 | v7 | ouro |
|---|---|---|---|---|---|
| `12550.jpg` | camisa ✅ | not_visible | casaco_jaqueta | not_visible | camisa |
| `665.jpg` | saia ✅ | saia ✅ | saia ✅ | **not_visible** | saia |
| `3867.jpg` (cor) | vermelho_rosa ✅ | vermelho_rosa ✅ | vermelho_rosa ✅ | **lilas_roxo** | vermelho_rosa |
| `1040.jpg` | not_visible | not_visible | not_visible | **sem resposta** | vestido |
| `3142.jpg` | not_visible | not_visible | not_visible | not_visible | short |
| `3887.jpg` | vestido | vestido | vestido | vestido | camisa |

Duas linhas dizem coisas opostas sobre a mesma amostra.

`3142.jpg` e `3887.jpg` deram **a mesma resposta errada nas quatro rodadas**.
São limitação de prompt: reprodutíveis, endereçáveis, e nenhuma delas mudou
agora.

`12550.jpg` deu **três respostas diferentes em quatro rodadas** de prompts quase
idênticos. Essa imagem não mede prompt nenhum — ela sorteia.

## Por que isso não autoriza dizer "a v7 piorou"

O portão é 80%. A amostra tem 24 itens. **Uma imagem vale 4,2 pontos.** A
diferença entre passar e não passar, aqui, é uma imagem — e a amostra tem pelo
menos uma imagem que comprovadamente troca de resposta sozinha.

Os intervalos de confiança dizem o mesmo com mais formalidade:

| | categoria | IC 95% Wilson |
|---|---:|---:|
| v6 | 83,3% | 64,1% – 93,3% |
| v7 | 79,2% | 59,5% – 90,8% |

Sobreposição quase total. Com uma rodada de cada lado, **não dá para afirmar que
a v7 é pior, e também não dá para afirmar que é igual.** O que dá para afirmar é
o que está escrito no topo: a medida de hoje ficou abaixo do portão.

## O que de fato aconteceu nas cinco perdas

Três das quatro perdas de cor e a única perda de categoria vêm de um
comportamento só: **a v7 se absteve em foto com duas peças coordenadas.**

- `665.jpg` — conjunto verde, top curto e saia longa. A v7 diz: *"Neither
  garment is clearly cropped or visually dominant enough to establish one
  target."* O ouro diz saia, porque o umbigo à mostra proíbe vestido e a saia
  domina.
- `12550.jpg` — camisa e parte de baixo listradas, mesma estampa. A v7 diz
  peers. O ouro diz camisa, porque a composição favorece a de cima.
- `3142.jpg` — top branco e short laranja. Abstenção nas quatro rodadas.
- `1040.jpg` — a v7 leu "top preto + saia branca" (é um vestido bicolor),
  marcou alvo ambíguo **e mesmo assim preencheu `pattern: liso`**. O validador
  recusou por contrato. Erro de leitura antigo, modo de falhar novo.

A quinta perda é outra coisa: `3867.jpg`, saia floral, a v7 chamou a base de
`lilas_roxo` (*"magenta-purple base"*) onde três rodadas anteriores e a revisão
humana disseram `vermelho_rosa`. Fronteira magenta/roxo — o único ponto onde o
parágrafo que a v7 mexeu poderia plausivelmente ter mexido.

## O que isso bloqueia, e o que não bloqueia

**Não afeta o app.** O portão guarda apenas o benchmark pago de 300 imagens. A
edge function já roda a v7, e as duas correções que a v7 e a v6 trouxeram foram
**confirmadas no aparelho do JP** em 19/08: o quarter-zip Patagonia passou a ler
`Coats & jackets`, e o cinza com etiqueta roxa parou de vir marcado como roxo.
Ver `relatorio-v6-v7-em-aparelho.md`.

**Bloqueia o benchmark de 300**, que já estava bloqueado antes desta rodada.

Vale notar de que tipo de foto se trata: as 24 são fotos de catálogo, com modelo
vestindo produção inteira. É o pior caso para escolha de alvo, e é onde a v7
recuou. Foto de peça única — que é o caso comum de quem fotografa a própria peça
— não é o que esta amostra estressa.

## O que responderia a pergunta

Três rodadas da mesma v7, sem mudar nada, custam US$ 0,053 e ~9 minutos. Se as
cinco perdas se repetirem nas três, é a v7. Se dançarem, é a amostra — e aí o
número a consertar não é o prompt, é o tamanho e a composição das 24.

Enquanto uma imagem valer 4,2 pontos e pelo menos uma imagem trocar de resposta
sozinha, **este portão é decidido por ruído tanto quanto por qualidade.** Isso
vale para o 83,3% da v6 exatamente como vale para o 79,2% de hoje.

## Um defeito encontrado no caminho

A consolidação **morreu** com os dados pagos já na mão:

```
TypeError: '<' not supported between instances of 'str' and 'NoneType'
```

`1040.jpg` foi a primeira linha a chegar com `analysis: null` — o avaliador
guarda a imagem que falhou de propósito, para ela contar como erro no portão sem
levar junto as outras 23 medidas já pagas. O consolidador não sabia ler essa
linha e ordenava `None` junto de strings na matriz de confusão.

Havia um segundo defeito escondido atrás do primeiro, pior: a cor de uma imagem
sem resposta virava `not_visible`, que é resposta **legítima** quando o alvo é
mesmo indeterminável. Numa foto cujo gabarito é abster, uma falha de contrato
seria contada como acerto — e justamente no número que autoriza gastar dinheiro.

Agora ausência de resposta tem valor próprio, `sem_resposta`, que não existe na
taxonomia e portanto nunca casa com o gabarito. Aparece na matriz de confusão
com esse nome. Teste em
`coletor/teste_consolidar_revisao_luna.py::testar_imagem_sem_analise_conta_como_erro_e_nao_derruba_o_relatorio`.
