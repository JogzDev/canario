# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-31T09:11:53.536351+00:00


## Varejo

- Produtos **visitados**: 57907

- Snapshots **gravados** (delta, B3): 6281

- Marcas coletando: 13 de 14


> ⚠️ Zero itens (alerta imediato, §20): Fabula


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 26765 | 1642 | 26766 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41222, "coletados": 2500}, {"faixa": "0-1", "existem": 11393, "coletados": 2500}, {"faixa": "0-1", "existem": 7291, "coletados": 2500}, {"faixa": "0-1", "existem": 3469, "coletados": 2500}, {"faixa": "0-1", "existem": 6919, "coletados": 2500}]} |
| Hering | vtex | 7769 | 1182 | 7769 | 0.983 | — |
| Dress To | vtex | 6524 | 794 | 6524 | 1.0 | — |
| Farm | vtex | 2783 | 351 | 2783 | 0.985 | — |
| Lanca Perfume | vtex | 2709 | 516 | 2710 | 1.0 | — |
| Zinzane | vtex | 2484 | 94 | 2552 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2484, "paginavel": 2552}} |
| Le Lis Blanc | vtex | 1724 | 384 | 1726 | 1.0 | — |
| Animale | vtex | 1606 | 145 | 1606 | 1.0 | — |
| Maria Filo | vtex | 1539 | 888 | 1539 | 1.0 | — |
| Morena Rosa | vtex | 1162 | 39 | 1162 | 1.0 | — |
| NV | vtex | 1131 | 108 | 1729 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1131, "paginavel": 1729}} |
| Cantao | vtex | 891 | 73 | 891 | 1.0 | — |
| Bo.Bo | vtex | 820 | 65 | 820 | 1.0 | — |
| Fabula | vtex | 0 | 0 | — | — | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
