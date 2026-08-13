# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-13T07:43:58.216457+00:00

**Data observada:** 2026-08-13

**Estado:** sem alerta crítico


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 50876

- Snapshots **gravados** (delta, B3): 267

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 15710 | 4 | 15710 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41040, "coletados": 2500}, {"faixa": "0-1", "existem": 11297, "coletados": 2500}, {"faixa": "0-1", "existem": 7229, "coletados": 2500}, {"faixa": "0-1", "existem": 6875, "coletados": 2500}]} |
| Hering | vtex | 7779 | 17 | 7783 | 0.987 | — |
| PatBo | shopify | 7424 | 0 | — | 1.0 | — |
| Dress To | vtex | 4524 | 7 | 4524 | 1.0 | — |
| Farm | vtex | 2935 | 141 | 2935 | 0.985 | — |
| Zinzane | vtex | 2180 | 0 | 2267 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2180, "paginavel": 2267}} |
| Lanca Perfume | vtex | 1869 | 0 | 1870 | 1.0 | — |
| Le Lis Blanc | vtex | 1744 | 0 | 1744 | 1.0 | — |
| Animale | vtex | 1611 | 66 | 1611 | 1.0 | — |
| Maria Filo | vtex | 1574 | 26 | 1574 | 1.0 | — |
| Morena Rosa | vtex | 1188 | 2 | 1188 | 1.0 | — |
| Cantao | vtex | 817 | 0 | 817 | 1.0 | — |
| Bo.Bo | vtex | 796 | 0 | 796 | 1.0 | — |
| NV | vtex | 479 | 4 | 1086 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 479, "paginavel": 1086}} |
| Amaro | shopify | 246 | 0 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 26 | 500 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 19, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 13, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
