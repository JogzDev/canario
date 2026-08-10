# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-10T08:04:23.885381+00:00

**Data observada:** 2026-08-10

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ varejo/Amaro retornou zero


## Varejo

- Produtos **visitados**: 49845

- Snapshots **gravados** (delta, B3): 3116

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 15240 | 1215 | 18531 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 15240, "paginavel": 18531}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41119, "coletados": 2500}, {"faixa": "0-1", "existem": 11321, "coletados": 2500}, {"faixa": "0-1", "existem": 7225, "coletados": 2500}, {"faixa": "0-1", "existem": 3445, "coletados": 2500}, {"faixa": "0-1", "existem": 7358, "coletados": 2500}]} |
| PatBo | shopify | 7406 | 198 | — | 1.0 | — |
| Hering | vtex | 7321 | 312 | 7784 | 0.984 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 7321, "paginavel": 7784}} |
| Dress To | vtex | 4031 | 160 | 6603 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 4031, "paginavel": 6603}} |
| Farm | vtex | 2717 | 263 | 2812 | 0.985 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2717, "paginavel": 2812}} |
| Lanca Perfume | vtex | 2588 | 204 | 2590 | 1.0 | — |
| Zinzane | vtex | 2469 | 73 | 2469 | 1.0 | — |
| Le Lis Blanc | vtex | 1693 | 199 | 1693 | 1.0 | — |
| Animale | vtex | 1620 | 93 | 1620 | 1.0 | — |
| Maria Filo | vtex | 1517 | 232 | 1517 | 1.0 | — |
| Morena Rosa | vtex | 1196 | 49 | 1196 | 1.0 | — |
| Cantao | vtex | 859 | 66 | 859 | 1.0 | — |
| Bo.Bo | vtex | 771 | 39 | 771 | 1.0 | — |
| NV | vtex | 417 | 13 | 904 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 417, "paginavel": 904}} |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 56 | 498 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 10, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 5 | 5481 | 0.833 | {"modo": "semanal", "execucoes": {"0": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}, "1": {"itens": 2088, "tentados": 3, "responderam": 2, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2}]}}, "tentativa": 1, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 6, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2, "tentativa": 1}], "semana_mais_recente": "2026-08-10", "termos_sem_perna_de_busca": ["romantico"], "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
