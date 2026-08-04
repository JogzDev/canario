# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-04T09:19:20.573227+00:00

**Data observada:** 2026-08-04

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ busca caiu 78% contra a media de 7 dias (1044 vs 4828)

- ⚠️ varejo/PatBo retornou zero


## Varejo

- Produtos **visitados**: 50373

- Snapshots **gravados** (delta, B3): 2340

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 21184 | 378 | 22235 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 21184, "paginavel": 22235}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41215, "coletados": 2500}, {"faixa": "0-1", "existem": 11371, "coletados": 2500}, {"faixa": "0-1", "existem": 7269, "coletados": 2500}, {"faixa": "0-1", "existem": 3474, "coletados": 2500}, {"faixa": "0-1", "existem": 6917, "coletados": 2500}]} |
| Hering | vtex | 7736 | 884 | 7774 | 0.983 | — |
| Dress To | vtex | 5476 | 171 | 6535 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5476, "paginavel": 6535}} |
| Farm | vtex | 2703 | 320 | 2719 | 0.986 | — |
| Lanca Perfume | vtex | 2597 | 150 | 2599 | 1.0 | — |
| Zinzane | vtex | 2410 | 33 | 2515 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2410, "paginavel": 2515}} |
| Le Lis Blanc | vtex | 1619 | 47 | 1623 | 1.0 | — |
| Animale | vtex | 1603 | 80 | 1603 | 1.0 | — |
| Maria Filo | vtex | 1466 | 125 | 1466 | 1.0 | — |
| Morena Rosa | vtex | 1180 | 46 | 1180 | 1.0 | — |
| Cantao | vtex | 849 | 36 | 849 | 1.0 | — |
| Bo.Bo | vtex | 816 | 35 | 816 | 1.0 | — |
| NV | vtex | 484 | 29 | 853 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 484, "paginavel": 853}} |
| Amaro | shopify | 250 | 6 | — | 1.0 | {"erro": "http 500"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 17 | 68 | 529 | 0.882 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 10, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Vogue Business": 30, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 3 | 1 | 1044 | 0.333 | {"modo": "backfill", "grupos_totais": 9, "termos_aprovados": 40, "termos_com_serie": 8, "grupos_planejados": 3, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2}], "semana_mais_recente": "2026-08-04", "termos_sem_perna_de_busca": null, "grupos_adiados_por_orcamento": 6} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
