# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-03T11:17:59.447853+00:00

**Data observada:** 2026-08-03

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ varejo/Fabula retornou zero


## Varejo

- Produtos **visitados**: 60475

- Snapshots **gravados** (delta, B3): 2158

- Marcas coletando: 16 de 16


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 22189 | 533 | 22190 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41209, "coletados": 2500}, {"faixa": "0-1", "existem": 11365, "coletados": 2500}, {"faixa": "0-1", "existem": 7270, "coletados": 2500}, {"faixa": "0-1", "existem": 3475, "coletados": 2500}, {"faixa": "0-1", "existem": 6915, "coletados": 2500}]} |
| Hering | vtex | 7776 | 191 | 7776 | 0.983 | — |
| PatBo | shopify | 7392 | 154 | — | 1.0 | — |
| Dress To | vtex | 6526 | 124 | 6526 | 1.0 | — |
| Farm | vtex | 2741 | 517 | 2748 | 0.985 | — |
| Lanca Perfume | vtex | 2620 | 175 | 2622 | 1.0 | — |
| Zinzane | vtex | 2377 | 50 | 2442 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2377, "paginavel": 2442}} |
| Le Lis Blanc | vtex | 1661 | 128 | 1661 | 1.0 | — |
| Animale | vtex | 1598 | 41 | 1598 | 1.0 | — |
| Maria Filo | vtex | 1297 | 137 | 1297 | 1.0 | — |
| Morena Rosa | vtex | 1172 | 10 | 1172 | 1.0 | — |
| NV | vtex | 1135 | 27 | 1729 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1135, "paginavel": 1729}} |
| Cantao | vtex | 861 | 57 | 861 | 1.0 | — |
| Bo.Bo | vtex | 817 | 10 | 817 | 1.0 | — |
| Amaro | shopify | 313 | 4 | — | 1.0 | — |
| Fabula | vtex | 0 | 0 | — | — | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 17 | 75 | 518 | 0.824 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 20, "Refinery29": 0, "Elle Brasil": 10, "Highsnobiety": 9, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Vogue Business": 30, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Refinery29": "feed http None", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 9 | 3 | 3393 | 0.333 | {"modo": "backfill", "termos_aprovados": 40, "termos_com_serie": 4, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 4}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 7}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 8}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 9}], "semana_mais_recente": "2026-08-03", "termos_sem_perna_de_busca": null} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
