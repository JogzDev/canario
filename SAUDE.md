# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-29T19:24:29.557840+00:00


## Varejo

- Produtos **visitados**: 4540

- Snapshots **gravados** (delta, B3): 4540

- Marcas coletando: 1 de 1


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| Dress To | vtex | 4540 | 4540 | 7178 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"declarado": 7178, "coletado": 4540, "obs": "coletado < declarado; ver truncamento ou multi-categoria"}} |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
