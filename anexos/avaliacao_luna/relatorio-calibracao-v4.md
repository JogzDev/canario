# Calibração Luna v4 — resultado preservado

- Execução definitiva: `31764541034`.
- Custo estimado: **US$ 0,015997**; 112,1 s; mediana 4,5 s.
- A tentativa anterior `31764281649` consumiu cinco respostas (~US$ 0,006) e falhou num limite local de texto; nenhum resultado foi reaproveitado.
- O gabarito permaneceu congelado antes da inferência.


## Prompt contra gabarito adjudicado

Prompt: `alvo-estrutura-v4`. Amostra: **24**. Portao: **FECHADO**.
SHA-256 do prompt: `1d33b7fc2e8215cf80556767700b80650cf0bcfb0f743855cd41dcd2c97dc736`.

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| category | 17/24 | 70.8% | 50.8%–85.1% |
| primary_color | 17/24 | 70.8% | 50.8%–85.1% |
| target_clarity | 18/24 | 75.0% | 55.1%–88.0% |

### Matriz de confusão — category

| ouro | Luna | n |
|---|---|---:|
| blusa_top | blusa_top | 3 |
| calca | calca | 2 |
| calca | not_visible | 1 |
| camisa | camisa | 1 |
| camisa | vestido | 1 |
| casaco_jaqueta | casaco_jaqueta | 3 |
| macacao | macacao | 3 |
| not_visible | camisa | 1 |
| saia | not_visible | 1 |
| saia | saia | 2 |
| saia | short | 1 |
| short | not_visible | 1 |
| vestido | not_visible | 1 |
| vestido | vestido | 3 |

### Matriz de confusão — primary_color

| ouro | Luna | n |
|---|---|---:|
| amarelo_laranja | not_visible | 1 |
| amarelo_laranja | outras_cores | 1 |
| azul | azul | 2 |
| branco_cru | branco_cru | 2 |
| branco_cru/preto | not_visible | 1 |
| cinza | cinza | 1 |
| lilas_roxo | lilas_roxo | 1 |
| not_visible | branco_cru | 1 |
| outras_cores | outras_cores | 1 |
| preto | preto | 5 |
| verde | not_visible | 1 |
| verde | verde | 1 |
| vermelho_rosa | lilas_roxo | 1 |
| vermelho_rosa | not_visible | 1 |
| vermelho_rosa | vermelho_rosa | 3 |
| vermelho_rosa/branco_cru | vermelho_rosa | 1 |

### Divergencias

- **S02**: primary_color: vermelho_rosa → lilas_roxo
- **S07**: category: calca → not_visible; primary_color: vermelho_rosa → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **S09**: primary_color: amarelo_laranja → outras_cores
- **S10**: category: vestido → not_visible; primary_color: branco_cru/preto → not_visible; target_clarity: clear → ambiguous_target
- **S11**: category: saia → not_visible; primary_color: verde → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
- **S14**: category: not_visible → camisa; primary_color: not_visible → branco_cru; target_clarity: ambiguous_target → multiple_garments_target_clear
- **S17**: target_clarity: clear → multiple_garments_target_clear
- **S18**: category: saia → short
- **S20**: category: camisa → vestido
- **S21**: category: short → not_visible; primary_color: amarelo_laranja → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
