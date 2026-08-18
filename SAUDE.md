# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-18T07:12:26.493031+00:00

**Data observada:** 2026-08-18

**Estado:** sem alerta crítico


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 53326

- Snapshots **gravados** (delta, B3): 7074

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 16489 | 3836 | 17739 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 1000003/1004161/1004167", "truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 16489, "paginavel": 17739}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41053, "coletados": 2500}, {"faixa": "0-1", "existem": 11280, "coletados": 2500}, {"faixa": "0-1", "existem": 7215, "coletados": 2500}, {"faixa": "0-1", "existem": 6875, "coletados": 2500}]} |
| Hering | vtex | 7789 | 1094 | 7789 | 0.987 | — |
| PatBo | shopify | 7444 | 46 | — | 1.0 | — |
| Dress To | vtex | 5907 | 113 | 5907 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28"} |
| Farm | vtex | 2964 | 935 | 2975 | 0.983 | — |
| Lanca Perfume | vtex | 2445 | 160 | 2445 | 1.0 | — |
| Zinzane | vtex | 2009 | 234 | 2093 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2009, "paginavel": 2093}} |
| Le Lis Blanc | vtex | 1695 | 98 | 1695 | 1.0 | — |
| Maria Filo | vtex | 1684 | 160 | 1684 | 1.0 | — |
| Animale | vtex | 1508 | 89 | 1508 | 1.0 | — |
| Morena Rosa | vtex | 1108 | 137 | 1108 | 1.0 | — |
| Cantao | vtex | 773 | 41 | 773 | 1.0 | — |
| Bo.Bo | vtex | 756 | 41 | 756 | 1.0 | — |
| NV | vtex | 497 | 77 | 1134 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 138", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 497, "paginavel": 1134}} |
| Amaro | shopify | 258 | 13 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 33 | 576 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
