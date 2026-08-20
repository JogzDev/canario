# Luna v7 — três rodadas responderam o que uma não conseguia

## A pergunta

Em 20/08 a v7 foi medida nas 24 imagens e deu **79,2%** em categoria e cor. O
portão corta em 80%, então fechou. A v6 tinha dado 83,3% e 91,7%.

A dúvida honesta era: a v7 piorou, ou a amostra oscila? A v7 mexeu **só no
parágrafo de cor** — ignorar zíper e etiqueta de marca —, e o movimento medido
foi em escolha de alvo, que ela não tocou.

## A resposta

Três rodadas do **mesmo prompt**, nas **mesmas 24 imagens**, com o **mesmo
segmentador**, sem mudar uma vírgula entre elas:

| rodada | categoria | cor primária | portão |
|---|---:|---:|---|
| A | 19/24 — 79,2% | 19/24 — 79,2% | **FECHADO** |
| B | 20/24 — 83,3% | 21/24 — 87,5% | ABERTO |
| C | 20/24 — 83,3% | 20/24 — 83,3% | ABERTO |

O portão fechou e abriu no mesmo dia, com o mesmo prompt. **Não era a v7.**

O motivo é aritmético: 80% de corte numa amostra de 24 significa que **uma
imagem vale 4,2 pontos**. A diferença entre passar e não passar é uma imagem — e
a amostra tem imagens que trocam de resposta sozinhas.

## O portão passa a somar as rodadas

`anexos/portao_luna_24.json` agora registra as três juntas:

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| categoria | 59/72 | **81,9%** | 71,5% – 89,1% |
| cor primária | 60/72 | **83,3%** | 73,1% – 90,2% |
| clareza do alvo | 58/72 | 80,6% | 70,0% – 88,0% |

**ABERTO**, com 72 observações em vez de 24. O intervalo encolheu de 31 pontos
de largura para 18. Isso não torna a medida mais generosa; torna-a mais difícil
de mover por sorteio.

`combinar_avaliacoes` exige o mesmo `prompt_sha256` nos arquivos somados. Somar
v6 com v7 daria um número que não descreve prompt nenhum.

## O que as três rodadas separam, e uma não separava

Este é o ganho real, maior que o portão em si: com três rodadas dá para
distinguir erro de prompt de erro de amostra.

**Erram nas três — limitação de prompt, reprodutível, endereçável:**

| imagem | ouro | o que a v7 responde |
|---|---|---|
| `3887.jpg` | camisa | vestido |
| `3142.jpg` | short | abstém (top branco + short laranja) |
| `12550.jpg` | camisa | abstém (conjunto listrado) |
| `1040.jpg` | vestido | lê como top preto + saia branca |

**Erram em uma das três — a amostra sorteando:**

| imagem | ouro | quando erra |
|---|---|---|
| `665.jpg` | saia | 1/3 — conjunto verde, top + saia longa |
| `3867.jpg` | vermelho_rosa | 1/3 — fronteira magenta/roxo |
| `1241.jpg` | clear | 1/3 — só clareza do alvo |

Três das quatro falhas estáveis são o mesmo caso: **foto de catálogo com duas
peças coordenadas**. É o pior caso para escolha de alvo, e é onde o prompt tem
trabalho real a fazer. Nenhuma delas é sobre cor, que foi o que a v7 mexeu.

## O que isso muda no app

Nada quebra e nada muda de comportamento. O portão guarda somente o benchmark
pago de 300 imagens, que **passa a estar liberado**. A edge function já roda a
v7, e as duas correções foram confirmadas no aparelho do JP em 19/08 —
quarter-zip lendo `Coats & jackets`, etiqueta de marca parando de virar cor. Ver
`relatorio-v6-v7-em-aparelho.md`.

## O que continua verdade sobre a amostra

Somar rodadas conserta a instabilidade da medida. **Não conserta a composição.**
As 24 continuam sem um único fleece, moletom, parka ou corta-vento, e sem
nenhuma peça com etiqueta de marca visível — os dois casos que a v6 e a v7
corrigiram e que só o aparelho do JP conseguiu verificar.

Enquanto isso não mudar, o benchmark mede bem o que ele contém, e continua cego
para o que não contém.

## Dois defeitos encontrados no caminho

**A consolidação morria com os dados pagos na mão.** `1040.jpg` foi a primeira
imagem a voltar com `analysis: null` — o avaliador guarda a linha que falhou de
propósito, para ela contar como erro sem levar junto as outras 23 medidas. O
consolidador ordenava `None` junto de strings na matriz de confusão:

```
TypeError: '<' not supported between instances of 'str' and 'NoneType'
```

**E, atrás desse, um pior.** A cor de uma imagem sem resposta virava
`not_visible`, que é resposta **legítima** quando o alvo é mesmo indeterminável.
Numa foto cujo gabarito é abster, uma falha de contrato seria contada como
acerto — dentro do número que autoriza gastar dinheiro. Agora ausência tem valor
próprio, `sem_resposta`, que não existe na taxonomia e nunca casa com o
gabarito.

## Custo

Quatro rodadas de 24 imagens em 20/08: **US$ 0,071** no total.
