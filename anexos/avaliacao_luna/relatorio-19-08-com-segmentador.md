# Luna com segmentador — 19/08/2026

Rodada pedida pelo JP para responder uma pergunta específica: **o número de
13/08 ainda vale, agora que o app manda a peça recortada em vez da foto
inteira?**

## Resposta: vale. O segmentador não mudou a acurácia.

Mesmas 24 imagens, mesmo gabarito humano adjudicado (Fadul + Bianca + JP),
mesmo prompt (`alvo-estrutura-v5`, sha `f376aba9…`).

| | categoria | cor primária |
|---|---:|---:|
| 13/08 — sem segmentador | **20/24 (83,3%)** | 20/24 |
| 19/08 — com segmentador | **20/24 (83,3%)** | 20/24 |

Duas imagens trocaram de resultado, e elas se anulam:

| imagem | humano | 13/08 | 19/08 |
|---|---|---|---|
| `12550.jpg` | camisa | camisa ✓ | `not_visible` ✗ |
| `3867.jpg` | saia | short ✗ | saia ✓ |

## O 70,8% que aparece no log NÃO é este número

O log da execução imprime `Concordância de categoria: 17/24 (70,8%)`. Essa
medida compara com a **categoria do título do catálogo**, que é diagnóstico e
mais ruidoso — o próprio `avaliar_luna.py` diz isso no cabeçalho. `3867.jpg` é o
exemplo: o catálogo diz `short`, os humanos disseram `saia`, e a Luna acertou o
humano e "errou" o catálogo.

O portão da A15 é contra o gabarito humano. Quem for comparar rodadas precisa
usar a mesma régua, e casar **por imagem** — o `sample_id` muda de ordem entre
execuções, então comparar por id devolve lixo.

## Ressalva de honestidade

A acurácia de cor que calculei aqui deu 83,3%, e o portão gravado em
`portao_luna_24.json` registra 91,7%. A diferença é de critério de comparação,
não de dados: minha checagem exige igualdade exata do `primary_color`, e a do
portão provavelmente aceita a cor em qualquer posição da lista `colors`. O
número oficial continua sendo o do portão; o meu serve só para comparar as duas
rodadas entre si, que é o que esta página faz.

## O que isto libera e o que não libera

* **Libera:** o portão técnico de 80% continua aberto, agora medido no pipeline
  que o app realmente usa. A dúvida de 19/08 está respondida.
* **Não libera:** a meta de produto de 90% em categoria continua sem ser
  alcançada. Ligar a Luna com 83,3% é decisão de produto.

## As divergências, para quem for melhorar o prompt

Sete divergências contra o catálogo, concentradas em duas confusões:

* **camisa → `not_visible`** (3 casos). O modelo se recusa a nomear.
* **short → saia** (2 casos). Peça recortada sobre branco perde a referência de
  entrepernas.

Custo desta rodada: ~US$ 0,019.
