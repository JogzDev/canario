# Calibração Luna v5 — resultado final

- Execução: `31765004896`.
- Custo estimado: **US$ 0,018898**; 119,4 s; mediana 4,6 s; p95 7,3 s.
- Mesmas 24 imagens e mesmo gabarito humano congelado da v4.
- O piso combinado abriu, mas a categoria ainda ficou abaixo da meta de produto de 90%; as 300 não foram executadas.


## Prompt contra gabarito adjudicado

Prompt: `alvo-estrutura-v5`. Amostra: **24**. Portao: **ABERTO**.
SHA-256 do prompt: `f376aba99183b6c0277a856b7aaac3abe954bdb2016d3c20c31076fdfd6444c5`.

| medida | acertos | resultado | IC 95% Wilson |
|---|---:|---:|---:|
| category | 20/24 | 83.3% | 64.1%–93.3% |
| primary_color | 22/24 | 91.7% | 74.2%–97.7% |
| target_clarity | 21/24 | 87.5% | 69.0%–95.7% |

### Matriz de confusão — category

| ouro | Luna | n |
|---|---|---:|
| blusa_top | blusa_top | 3 |
| calca | calca | 3 |
| camisa | camisa | 1 |
| camisa | vestido | 1 |
| casaco_jaqueta | casaco_jaqueta | 3 |
| macacao | macacao | 3 |
| not_visible | not_visible | 1 |
| saia | saia | 3 |
| saia | short | 1 |
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

- **S10**: category: vestido → not_visible; primary_color: branco_cru/preto → not_visible; target_clarity: clear → ambiguous_target
- **S17**: target_clarity: clear → multiple_garments_target_clear
- **S18**: category: saia → short
- **S20**: category: camisa → vestido
- **S21**: category: short → not_visible; primary_color: amarelo_laranja → not_visible; target_clarity: multiple_garments_target_clear → ambiguous_target
