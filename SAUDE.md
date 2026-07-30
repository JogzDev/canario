# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-30T08:43:30.314486+00:00


## Varejo

- Produtos **visitados**: 64717

- Snapshots **gravados** (delta, B3): 3937

- Marcas coletando: 15 de 16


> ⚠️ Zero itens (alerta imediato, §20): Fabula


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 26786 | 224 | 26786 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41199, "coletados": 2500}, {"faixa": "0-1", "existem": 11380, "coletados": 2500}, {"faixa": "0-1", "existem": 7281, "coletados": 2500}, {"faixa": "0-1", "existem": 3459, "coletados": 2500}, {"faixa": "0-1", "existem": 6908, "coletados": 2500}]} |
| Hering | vtex | 7776 | 314 | 7776 | 0.983 | — |
| PatBo | shopify | 7392 | 336 | — | 1.0 | — |
| Dress To | vtex | 5746 | 2162 | 6521 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5746, "paginavel": 6521}} |
| Farm | vtex | 2767 | 93 | 2767 | 0.985 | — |
| Lanca Perfume | vtex | 2648 | 340 | 2649 | 1.0 | — |
| Zinzane | vtex | 2517 | 39 | 2631 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2517, "paginavel": 2631}} |
| Le Lis Blanc | vtex | 1649 | 12 | 1646 | 1.0 | — |
| Animale | vtex | 1621 | 47 | 1621 | 1.0 | — |
| Maria Filo | vtex | 1493 | 45 | 1493 | 1.0 | — |
| Morena Rosa | vtex | 1158 | 0 | 1158 | 1.0 | — |
| NV | vtex | 1127 | 4 | 1726 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1127, "paginavel": 1726}} |
| Cantao | vtex | 907 | 2 | 907 | 1.0 | — |
| Bo.Bo | vtex | 813 | 2 | 813 | 1.0 | — |
| Amaro | shopify | 317 | 317 | — | 1.0 | — |
| Fabula | vtex | 0 | 0 | — | — | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
