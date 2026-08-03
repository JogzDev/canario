# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-03T18:53:30.190500+00:00

**Data observada:** 2026-08-03

**Estado:** sem alerta crítico


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 54322

- Snapshots **gravados** (delta, B3): 2759

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 17264 | 329 | 22200 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 17264, "paginavel": 22200}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41216, "coletados": 2500}, {"faixa": "0-1", "existem": 11374, "coletados": 2500}, {"faixa": "0-1", "existem": 7259, "coletados": 2500}, {"faixa": "0-1", "existem": 3474, "coletados": 2500}, {"faixa": "0-1", "existem": 6920, "coletados": 2500}]} |
| PatBo | shopify | 7394 | 45 | — | 1.0 | — |
| Hering | vtex | 7102 | 1062 | 7826 | 0.984 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 7102, "paginavel": 7826}} |
| Dress To | vtex | 6360 | 63 | 6526 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 6360, "paginavel": 6526}} |
| Farm | vtex | 2677 | 303 | 2677 | 0.984 | — |
| Lanca Perfume | vtex | 2602 | 163 | 2620 | 1.0 | — |
| Zinzane | vtex | 2410 | 21 | 2517 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2410, "paginavel": 2517}} |
| Le Lis Blanc | vtex | 1639 | 220 | 1645 | 1.0 | — |
| Animale | vtex | 1597 | 53 | 1597 | 1.0 | — |
| Maria Filo | vtex | 1452 | 372 | 1452 | 1.0 | — |
| Morena Rosa | vtex | 1183 | 56 | 1183 | 1.0 | — |
| NV | vtex | 1129 | 44 | 1722 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1129, "paginavel": 1722}} |
| Cantao | vtex | 851 | 19 | 851 | 1.0 | — |
| Bo.Bo | vtex | 350 | 5 | 815 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 350, "paginavel": 815}} |
| Amaro | shopify | 312 | 4 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 17 | 71 | 526 | 0.882 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 7, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Vogue Business": 30, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 3 | 2 | 2349 | 0.667 | {"modo": "backfill", "grupos_totais": 9, "termos_aprovados": 40, "termos_com_serie": 13, "grupos_planejados": 3, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}], "semana_mais_recente": "2026-08-03", "termos_sem_perna_de_busca": null, "grupos_adiados_por_orcamento": 6} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
