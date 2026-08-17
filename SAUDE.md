# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-17T20:52:29.777746+00:00

**Data observada:** 2026-08-17

**Estado:** ATENÇÃO


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia

- varejo/Zinzane retornou zero hoje (http 503 ao contar categoria VTEX 1); 1º dia



- ⚠️ varejo/NV caiu 89% contra a media de 7 dias (50 vs 456)


## Varejo

- Produtos **visitados**: 48693

- Snapshots **gravados** (delta, B3): 3353

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 14365 | 465 | 14367 | 1.0 | {"erro": "http 503 ao contar categoria VTEX 1000003/1004161/1004164", "truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41035, "coletados": 2500}, {"faixa": "0-1", "existem": 7210, "coletados": 2500}, {"faixa": "0-1", "existem": 6875, "coletados": 2500}]} |
| Hering | vtex | 7698 | 824 | 7809 | 0.988 | — |
| PatBo | shopify | 7444 | 0 | — | 1.0 | — |
| Dress To | vtex | 6221 | 177 | 6221 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28"} |
| Farm | vtex | 2919 | 256 | 2920 | 0.983 | — |
| Lanca Perfume | vtex | 2445 | 883 | 2451 | 1.0 | — |
| Le Lis Blanc | vtex | 1722 | 204 | 1722 | 1.0 | — |
| Maria Filo | vtex | 1678 | 226 | 1678 | 1.0 | — |
| Animale | vtex | 1505 | 61 | 1505 | 1.0 | — |
| Morena Rosa | vtex | 850 | 208 | 1188 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 850, "paginavel": 1188}} |
| Cantao | vtex | 779 | 26 | 779 | 1.0 | — |
| Bo.Bo | vtex | 759 | 15 | 759 | 1.0 | — |
| Amaro | shopify | 258 | 0 | — | 1.0 | — |
| NV | vtex | 50 | 8 | 341 | 1.0 | {"erro": "http 503 ao contar categoria VTEX 29", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 50, "paginavel": 341}} |
| Zinzane | vtex | 0 | 0 | — | — | {"erro": "http 503 ao contar categoria VTEX 1"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 31 | 566 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 0, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": ["Steal the Look"]} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
