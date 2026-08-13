# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-13T05:43:15.472775+00:00

**Data observada:** 2026-08-13

**Estado:** sem alerta crítico


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 52553

- Snapshots **gravados** (delta, B3): 16358

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 15707 | 4864 | 15707 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41040, "coletados": 2500}, {"faixa": "0-1", "existem": 11297, "coletados": 2500}, {"faixa": "0-1", "existem": 7229, "coletados": 2500}, {"faixa": "0-1", "existem": 6875, "coletados": 2500}]} |
| Hering | vtex | 7762 | 3664 | 7766 | 0.986 | — |
| PatBo | shopify | 7424 | 416 | — | 1.0 | — |
| Dress To | vtex | 6221 | 2281 | 6221 | 1.0 | — |
| Farm | vtex | 2935 | 526 | 2935 | 0.985 | — |
| Zinzane | vtex | 2180 | 1588 | 2267 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2180, "paginavel": 2267}} |
| Lanca Perfume | vtex | 1869 | 885 | 1870 | 1.0 | — |
| Le Lis Blanc | vtex | 1744 | 1034 | 1744 | 1.0 | — |
| Animale | vtex | 1611 | 171 | 1611 | 1.0 | — |
| Maria Filo | vtex | 1574 | 295 | 1574 | 1.0 | — |
| Morena Rosa | vtex | 1188 | 123 | 1188 | 1.0 | — |
| Cantao | vtex | 817 | 144 | 817 | 1.0 | — |
| Bo.Bo | vtex | 796 | 66 | 796 | 1.0 | — |
| NV | vtex | 479 | 162 | 1086 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 479, "paginavel": 1086}} |
| Amaro | shopify | 246 | 139 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 25 | 500 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 19, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 13, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
