# Revisao Luna — consolidacao

## Prompt contra gabarito adjudicado

Prompt: `alvo-estrutura-v7`. Amostra: **24**. Portao: **FECHADO**.
SHA-256 do prompt: `45f9ce7e00c66499847aa2dcf1effb1de347826f4ffa4ae76871b55c2b94dc4f`.

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| category | 19/24 | 79.2% | 59.5%–90.8% |
| primary_color | 19/24 | 79.2% | 59.5%–90.8% |
| target_clarity | 19/24 | 79.2% | 59.5%–90.8% |

### Matriz de confusão — category

| ouro | Luna | n |
|---|---|---:|
| blusa_top | blusa_top | 3 |
| calca | calca | 3 |
| camisa | not_visible | 1 |
| camisa | vestido | 1 |
| casaco_jaqueta | casaco_jaqueta | 3 |
| macacao | macacao | 3 |
| not_visible | not_visible | 1 |
| saia | not_visible | 1 |
| saia | saia | 3 |
| short | not_visible | 1 |
| vestido | sem_resposta | 1 |
| vestido | vestido | 3 |

### Matriz de confusão — primary_color

| ouro | Luna | n |
|---|---|---:|
| amarelo_laranja | amarelo_laranja | 1 |
| amarelo_laranja | not_visible | 1 |
| azul | azul | 2 |
| branco_cru | branco_cru | 2 |
| branco_cru/preto | sem_resposta | 1 |
| cinza | cinza | 1 |
| lilas_roxo | lilas_roxo | 1 |
| not_visible | not_visible | 1 |
| outras_cores | outras_cores | 1 |
| preto | preto | 5 |
| verde | not_visible | 1 |
| verde | verde | 1 |
| vermelho_rosa | lilas_roxo | 1 |
| vermelho_rosa | vermelho_rosa | 4 |
| vermelho_rosa/branco_cru | not_visible | 1 |

### Divergencias

- **1040.jpg**: category: vestido → sem_resposta; primary_color: branco_cru/preto → sem_resposta; target_clarity: clear → sem_resposta
- **12550.jpg**: category: camisa → not_visible; primary_color: vermelho_rosa/branco_cru → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **3142.jpg**: category: short → not_visible; primary_color: amarelo_laranja → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **3867.jpg**: primary_color: vermelho_rosa → lilas_roxo
- **3887.jpg**: category: camisa → vestido
- **665.jpg**: category: saia → not_visible; primary_color: verde → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **863.jpg**: target_clarity: multiple_garments_target_clear → clear
