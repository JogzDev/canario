# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-08-02T08:41:22.826908+00:00


## Varejo

- Produtos **visitados**: 53378

- Snapshots **gravados** (delta, B3): 2957

- Marcas coletando: 14 de 16


> ⚠️ Zero itens (alerta imediato, §20): PatBo, Fabula


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 22333 | 724 | 22333 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41146, "coletados": 2500}, {"faixa": "0-1", "existem": 11352, "coletados": 2500}, {"faixa": "0-1", "existem": 7252, "coletados": 2500}, {"faixa": "0-1", "existem": 3466, "coletados": 2500}, {"faixa": "0-1", "existem": 6902, "coletados": 2500}]} |
| Hering | vtex | 7776 | 317 | 7776 | 0.983 | — |
| Dress To | vtex | 6526 | 119 | 6526 | 1.0 | — |
| Farm | vtex | 2786 | 303 | 2786 | 0.985 | — |
| Lanca Perfume | vtex | 2632 | 206 | 2634 | 1.0 | — |
| Zinzane | vtex | 2439 | 106 | 2506 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2439, "paginavel": 2506}} |
| Le Lis Blanc | vtex | 1674 | 140 | 1674 | 1.0 | — |
| Animale | vtex | 1605 | 71 | 1605 | 1.0 | — |
| Maria Filo | vtex | 1341 | 509 | 1344 | 1.0 | — |
| Morena Rosa | vtex | 1172 | 9 | 1172 | 1.0 | — |
| NV | vtex | 1141 | 48 | 1737 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1141, "paginavel": 1737}} |
| Cantao | vtex | 883 | 361 | 883 | 1.0 | — |
| Bo.Bo | vtex | 820 | 38 | 820 | 1.0 | — |
| Amaro | shopify | 250 | 6 | — | 1.0 | {"erro": "http 500"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| Fabula | vtex | 0 | 0 | — | — | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
