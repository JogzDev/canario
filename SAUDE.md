# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-30T02:53:01.540639+00:00


## Varejo

- Produtos **visitados**: 51248

- Snapshots **gravados** (delta, B3): 6778

- Marcas coletando: 13 de 14


> ⚠️ Zero itens (alerta imediato, §20): Fabula


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 26791 | 755 | 26808 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41184, "coletados": 2500}, {"faixa": "0-1", "existem": 11379, "coletados": 2500}, {"faixa": "0-1", "existem": 7278, "coletados": 2500}, {"faixa": "0-1", "existem": 3459, "coletados": 2500}, {"faixa": "0-1", "existem": 6908, "coletados": 2500}]} |
| Hering | vtex | 7776 | 286 | 7776 | 0.983 | — |
| Farm | vtex | 2767 | 312 | 2767 | 0.985 | — |
| Zinzane | vtex | 2481 | 2481 | 2550 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2481, "paginavel": 2550}} |
| Lanca Perfume | vtex | 2333 | 2333 | 2621 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2333, "paginavel": 2621}} |
| Le Lis Blanc | vtex | 1649 | 81 | 1702 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1649, "paginavel": 1702}} |
| Animale | vtex | 1623 | 70 | 1623 | 1.0 | — |
| Maria Filo | vtex | 1493 | 325 | 1522 | 1.0 | — |
| Morena Rosa | vtex | 1158 | 15 | 1155 | 1.0 | — |
| NV | vtex | 1131 | 39 | 1733 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1131, "paginavel": 1733}} |
| Cantao | vtex | 907 | 17 | 917 | 1.0 | — |
| Bo.Bo | vtex | 813 | 15 | 812 | 1.0 | — |
| Dress To | vtex | 326 | 49 | 326 | 1.0 | — |
| Fabula | vtex | 0 | 0 | — | — | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
