# Revisao Luna — consolidacao

## Prompt contra gabarito adjudicado

Prompt: `alvo-estrutura-v7`. Amostra: **72** em 3 rodadas. Portao: **ABERTO**.
SHA-256 do prompt: `45f9ce7e00c66499847aa2dcf1effb1de347826f4ffa4ae76871b55c2b94dc4f`.

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| category | 59/72 | 81.9% | 71.5%–89.1% |
| primary_color | 60/72 | 83.3% | 73.1%–90.2% |
| target_clarity | 58/72 | 80.6% | 70.0%–88.0% |

### Rodada a rodada, mesmo prompt

| rodada | category | primary_color | target_clarity |
|---|---|---|---|
| 1 | 19/24 (79.2%) | 19/24 (79.2%) | 19/24 (79.2%) |
| 2 | 20/24 (83.3%) | 21/24 (87.5%) | 20/24 (83.3%) |
| 3 | 20/24 (83.3%) | 20/24 (83.3%) | 19/24 (79.2%) |

### Matriz de confusão — category

| ouro | Luna | n |
|---|---|---:|
| blusa_top | blusa_top | 9 |
| calca | calca | 9 |
| camisa | not_visible | 3 |
| camisa | vestido | 3 |
| casaco_jaqueta | casaco_jaqueta | 9 |
| macacao | macacao | 9 |
| not_visible | not_visible | 3 |
| saia | not_visible | 1 |
| saia | saia | 11 |
| short | not_visible | 3 |
| vestido | not_visible | 2 |
| vestido | sem_resposta | 1 |
| vestido | vestido | 9 |

### Matriz de confusão — primary_color

| ouro | Luna | n |
|---|---|---:|
| amarelo_laranja | amarelo_laranja | 3 |
| amarelo_laranja | not_visible | 3 |
| azul | azul | 6 |
| branco_cru | branco_cru | 6 |
| branco_cru/preto | not_visible | 2 |
| branco_cru/preto | sem_resposta | 1 |
| cinza | cinza | 3 |
| lilas_roxo | lilas_roxo | 3 |
| not_visible | not_visible | 3 |
| outras_cores | outras_cores | 3 |
| preto | preto | 15 |
| verde | not_visible | 1 |
| verde | verde | 5 |
| vermelho_rosa | lilas_roxo | 2 |
| vermelho_rosa | vermelho_rosa | 13 |
| vermelho_rosa/branco_cru | not_visible | 3 |

### Divergencias

Em quantas das 3 rodadas cada imagem divergiu. Imagem que erra em todas e limitacao de prompt; imagem que erra em algumas e a amostra sorteando.

- **1040.jpg** *(3/3 rodadas)*: category: vestido → not_visible; primary_color: branco_cru/preto → not_visible; target_clarity: clear → ambiguous_target · category: vestido → sem_resposta; primary_color: branco_cru/preto → sem_resposta; target_clarity: clear → sem_resposta
- **1241.jpg** *(1/3 rodadas)*: target_clarity: clear → multiple_garments_target_clear
- **12550.jpg** *(3/3 rodadas)*: category: camisa → not_visible; primary_color: vermelho_rosa/branco_cru → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **3142.jpg** *(3/3 rodadas)*: category: short → not_visible; primary_color: amarelo_laranja → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **3867.jpg** *(1/3 rodadas)*: primary_color: vermelho_rosa → lilas_roxo
- **3887.jpg** *(3/3 rodadas)*: category: camisa → vestido
- **665.jpg** *(1/3 rodadas)*: category: saia → not_visible; primary_color: verde → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **863.jpg** *(3/3 rodadas)*: primary_color: vermelho_rosa → lilas_roxo; target_clarity: multiple_garments_target_clear → clear · target_clarity: multiple_garments_target_clear → clear
