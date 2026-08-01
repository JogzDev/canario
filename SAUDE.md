# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-08-01T08:38:36.988033+00:00


## Varejo

- Produtos **visitados**: 7722

- Snapshots **gravados** (delta, B3): 497

- Marcas coletando: 2 de 2


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| PatBo | shopify | 7392 | 167 | — | 1.0 | — |
| Amaro | shopify | 330 | 330 | — | 1.0 | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
