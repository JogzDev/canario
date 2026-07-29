# SAÚDE — coletores do Canário

**Última coleta (UTC):** 2026-07-29T22:00:26.610381+00:00


## Varejo

- Produtos **visitados**: 49563

- Snapshots **gravados** (delta, B3): 30721

- Marcas coletando: 12 de 16


> ⚠️ Zero itens (alerta imediato, §20): Lanca Perfume, Zinzane, Amaro, Fabula


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 25083 | 7549 | 26808 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 25083, "paginavel": 26808}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41184, "coletados": 2500}, {"faixa": "0-1", "existem": 11379, "coletados": 2500}, {"faixa": "0-1", "existem": 7278, "coletados": 2500}, {"faixa": "0-1", "existem": 3459, "coletados": 2500}, {"faixa": "0-1", "existem": 6908, "coletados": 2500}]} |
| Hering | vtex | 7777 | 7777 | 7777 | 0.983 | — |
| Dress To | vtex | 4540 | 4540 | 7178 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < declarado; ver truncamento ou multi-categoria", "coletado": 4540, "declarado": 7178}} |
| Farm | vtex | 2767 | 2767 | 2796 | 0.985 | — |
| Le Lis Blanc | vtex | 1719 | 1719 | 1702 | 1.0 | — |
| Animale | vtex | 1629 | 1629 | 1628 | 1.0 | — |
| Maria Filo | vtex | 1516 | 1516 | 1522 | 1.0 | — |
| Morena Rosa | vtex | 1155 | 1155 | 1155 | 1.0 | — |
| NV | vtex | 1148 | 1148 | 1755 | 1.0 | {"divergencia": {"obs": "coletado < declarado; ver truncamento ou multi-categoria", "coletado": 1148, "declarado": 1755}} |
| Cantao | vtex | 917 | 0 | 917 | 1.0 | — |
| Bo.Bo | vtex | 812 | 812 | 812 | 1.0 | — |
| PatBo | shopify | 500 | 109 | — | 1.0 | {"erro": "http 429 (persistiu apos backoff longo)"} |
| Lanca Perfume | vtex | 0 | 0 | 2639 | — | {"divergencia": {"obs": "coletado < declarado; ver truncamento ou multi-categoria", "coletado": 0, "declarado": 2639}} |
| Zinzane | vtex | 0 | 0 | 2706 | — | {"divergencia": {"obs": "coletado < declarado; ver truncamento ou multi-categoria", "coletado": 0, "declarado": 2706}} |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| Fabula | vtex | 0 | 0 | — | — | — |

---

*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; *visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).
