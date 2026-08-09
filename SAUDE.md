# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-09T07:23:15.426847+00:00

**Data observada:** 2026-08-09

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ varejo/Amaro retornou zero

- ⚠️ varejo/PatBo retornou zero


## Varejo

- Produtos **visitados**: 42947

- Snapshots **gravados** (delta, B3): 4821

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 13357 | 1595 | 18939 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 13357, "paginavel": 18939}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41074, "coletados": 2500}, {"faixa": "0-1", "existem": 11306, "coletados": 2500}, {"faixa": "0-1", "existem": 7201, "coletados": 2500}, {"faixa": "0-1", "existem": 3442, "coletados": 2500}, {"faixa": "0-1", "existem": 6879, "coletados": 2500}]} |
| Hering | vtex | 6833 | 715 | 7784 | 0.986 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 6833, "paginavel": 7784}} |
| Dress To | vtex | 6603 | 586 | 6603 | 1.0 | — |
| Farm | vtex | 2854 | 369 | 2854 | 0.986 | — |
| Lanca Perfume | vtex | 2667 | 195 | 2669 | 1.0 | — |
| Zinzane | vtex | 2486 | 292 | 2486 | 1.0 | — |
| Le Lis Blanc | vtex | 1756 | 269 | 1756 | 1.0 | — |
| Animale | vtex | 1625 | 126 | 1625 | 1.0 | — |
| Maria Filo | vtex | 1532 | 404 | 1532 | 1.0 | — |
| Morena Rosa | vtex | 1198 | 27 | 1198 | 1.0 | — |
| Cantao | vtex | 877 | 189 | 877 | 1.0 | — |
| Bo.Bo | vtex | 742 | 30 | 742 | 1.0 | — |
| NV | vtex | 417 | 24 | 904 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 417, "paginavel": 904}} |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 59 | 498 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 10, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 6 | 6786 | 1.0 | {"modo": "semanal", "execucoes": {"0": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}, "1": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 1, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 6, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-09", "termos_sem_perna_de_busca": ["geometrica"], "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
