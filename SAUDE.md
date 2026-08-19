# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-19T07:12:10.035988+00:00

**Data observada:** 2026-08-19

**Estado:** sem alerta crítico · cobertura parcial — 3 de 15 marcas (1 com catálogo cortado; 2 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 51009

- Snapshots **gravados** (delta, B3): 15072

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 14847 | 4681 | 15008 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 1000003/1004161/1004167", "truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41017, "coletados": 2500}, {"faixa": "0-1", "existem": 11269, "coletados": 2500}, {"faixa": "0-1", "existem": 6873, "coletados": 2500}]} |
| Hering | vtex | 7777 | 2591 | 7777 | 0.989 | — |
| PatBo | shopify | 7454 | 404 | — | 1.0 | — |
| Dress To | vtex | 5224 | 1375 | 6221 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5224, "paginavel": 6221}} |
| Farm | vtex | 2947 | 1515 | 2948 | 0.983 | — |
| Lanca Perfume | vtex | 2453 | 505 | 2453 | 1.0 | — |
| Zinzane | vtex | 1986 | 134 | 2065 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1986, "paginavel": 2065}} |
| Le Lis Blanc | vtex | 1687 | 463 | 1687 | 1.0 | — |
| Maria Filo | vtex | 1677 | 553 | 1679 | 1.0 | — |
| Animale | vtex | 1512 | 955 | 1512 | 1.0 | — |
| Morena Rosa | vtex | 1151 | 786 | 1151 | 1.0 | — |
| Cantao | vtex | 762 | 364 | 762 | 1.0 | — |
| Bo.Bo | vtex | 757 | 440 | 757 | 1.0 | — |
| NV | vtex | 496 | 252 | 1133 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 138", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 496, "paginavel": 1133}} |
| Amaro | shopify | 279 | 54 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | parcial | 3 | 51.659 | http 500 ao contar categoria VTEX 1000003/1004161/1004167 |
| Dress To | incerta | — | — | catalogo VTEX declarou zero na categoria 28 |
| NV | incerta | — | — | catalogo VTEX declarou zero na categoria 138 |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 34 | 577 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
