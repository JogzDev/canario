# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-29T19:15:41.654670+00:00


## Varejo

- Produtos **visitados**: 19940

- Snapshots **gravados** (delta, B3): 18632

- Marcas coletando: 10 de 16


> ⚠️ Zero itens (alerta imediato, §20): Amaro, C&A, Dress To, Fabula, Lanca Perfume, Zinzane


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| Hering | vtex | 7777 | 7777 | 7777 | 0.983 | — |
| Farm | vtex | 2767 | 2767 | 2796 | 0.985 | — |
| Le Lis Blanc | vtex | 1719 | 1719 | 1702 | 1.0 | — |
| Animale | vtex | 1629 | 1629 | 1628 | 1.0 | — |
| Maria Filo | vtex | 1516 | 1516 | 1522 | 1.0 | — |
| Morena Rosa | vtex | 1155 | 1155 | 1155 | 1.0 | — |
| NV | vtex | 1148 | 1148 | 1755 | 1.0 | {"divergencia": {"declarado": 1755, "coletado": 1148, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |
| Cantao | vtex | 917 | 0 | 917 | 1.0 | — |
| Bo.Bo | vtex | 812 | 812 | 812 | 1.0 | — |
| PatBo | shopify | 500 | 109 | — | 1.0 | {"erro": "http 429 (persistiu apos backoff longo)"} |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| C&A | vtex | 0 | 0 | 143841 | — | {"divergencia": {"declarado": 143841, "coletado": 0, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |
| Dress To | vtex | 0 | 0 | 7178 | — | {"divergencia": {"declarado": 7178, "coletado": 0, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |
| Fabula | vtex | 0 | 0 | — | — | — |
| Lanca Perfume | vtex | 0 | 0 | 2639 | — | {"divergencia": {"declarado": 2639, "coletado": 0, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |
| Zinzane | vtex | 0 | 0 | 2706 | — | {"divergencia": {"declarado": 2706, "coletado": 0, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
