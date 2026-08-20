# Revisao Luna — consolidacao

## Prompt contra gabarito adjudicado

Prompt: `alvo-estrutura-v6`. Amostra: **24**. Portao: **ABERTO**.
SHA-256 do prompt: `328ea36b48453d3bddd2c26140500a3c6711bca160935cb4d4868f4b49c12719`.

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| category | 20/24 | 83.3% | 64.1%–93.3% |
| primary_color | 22/24 | 91.7% | 74.2%–97.7% |
| target_clarity | 20/24 | 83.3% | 64.1%–93.3% |

### Matriz de confusão — category

| ouro | Luna | n |
|---|---|---:|
| blusa_top | blusa_top | 3 |
| calca | calca | 3 |
| camisa | casaco_jaqueta | 1 |
| camisa | vestido | 1 |
| casaco_jaqueta | casaco_jaqueta | 3 |
| macacao | macacao | 3 |
| not_visible | not_visible | 1 |
| saia | saia | 4 |
| short | not_visible | 1 |
| vestido | not_visible | 1 |
| vestido | vestido | 3 |

### Matriz de confusão — primary_color

| ouro | Luna | n |
|---|---|---:|
| amarelo_laranja | amarelo_laranja | 1 |
| amarelo_laranja | not_visible | 1 |
| azul | azul | 2 |
| branco_cru | branco_cru | 2 |
| branco_cru/preto | not_visible | 1 |
| cinza | cinza | 1 |
| lilas_roxo | lilas_roxo | 1 |
| not_visible | not_visible | 1 |
| outras_cores | outras_cores | 1 |
| preto | preto | 5 |
| verde | verde | 2 |
| vermelho_rosa | vermelho_rosa | 5 |
| vermelho_rosa/branco_cru | branco_cru | 1 |

### Divergencias

- **1040.jpg**: category: vestido → not_visible; primary_color: branco_cru/preto → not_visible; target_clarity: clear → ambiguous_target
- **1241.jpg**: target_clarity: clear → multiple_garments_target_clear
- **12550.jpg**: category: camisa → casaco_jaqueta
- **3142.jpg**: category: short → not_visible; primary_color: amarelo_laranja → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **3887.jpg**: category: camisa → vestido
- **863.jpg**: target_clarity: multiple_garments_target_clear → clear
