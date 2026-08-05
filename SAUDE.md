# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-05T09:34:08.103453+00:00

**Data observada:** 2026-08-05

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ busca sem observacao hoje

- ⚠️ varejo/Le Lis Blanc caiu 76% contra a media de 7 dias (400 vs 1679)


## Varejo

- Produtos **visitados**: 48920

- Snapshots **gravados** (delta, B3): 28562

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 14602 | 12584 | 22165 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 14602, "paginavel": 22165}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41254, "coletados": 2500}, {"faixa": "0-1", "existem": 11381, "coletados": 2500}, {"faixa": "0-1", "existem": 7280, "coletados": 2500}, {"faixa": "0-1", "existem": 3476, "coletados": 2500}, {"faixa": "0-1", "existem": 6922, "coletados": 2500}]} |
| PatBo | shopify | 7400 | 54 | — | 1.0 | — |
| Dress To | vtex | 6535 | 3528 | 6535 | 1.0 | — |
| Hering | vtex | 5284 | 4324 | 7804 | 0.983 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5284, "paginavel": 7804}} |
| Farm | vtex | 2861 | 2202 | 2861 | 0.986 | — |
| Lanca Perfume | vtex | 2726 | 959 | 2728 | 1.0 | — |
| Zinzane | vtex | 2409 | 87 | 2513 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2409, "paginavel": 2513}} |
| Animale | vtex | 1602 | 1299 | 1602 | 1.0 | — |
| Maria Filo | vtex | 1486 | 610 | 1486 | 1.0 | — |
| Morena Rosa | vtex | 1180 | 1021 | 1180 | 1.0 | — |
| Cantao | vtex | 827 | 440 | 827 | 1.0 | — |
| Bo.Bo | vtex | 814 | 700 | 814 | 1.0 | — |
| NV | vtex | 484 | 428 | 853 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 484, "paginavel": 853}} |
| Le Lis Blanc | vtex | 400 | 326 | 1721 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 400, "paginavel": 1721}} |
| Amaro | shopify | 310 | 0 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 17 | 60 | 533 | 0.882 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 14, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Vogue Business": 30, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | — | — | — | — | sem observação hoje |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
