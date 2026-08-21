# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-21T04:09:19.766630+00:00

**Data observada:** 2026-08-21

**Estado:** sem alerta crítico · cobertura parcial — 4 de 15 marcas (1 com catálogo cortado; 3 sem contagem confiável)


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 55702

- Snapshots **gravados** (delta, B3): 11837

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 17884 | 2340 | 17884 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1000003/1004161/1004164 (450-499, OrderByNameASC)", "truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41013, "coletados": 2500}, {"faixa": "0-1", "existem": 11266, "coletados": 2500}, {"faixa": "0-1", "existem": 7194, "coletados": 2500}, {"faixa": "0-1", "existem": 6878, "coletados": 2500}]} |
| Hering | vtex | 7815 | 553 | 7815 | 0.99 | — |
| PatBo | shopify | 7461 | 6481 | — | 1.0 | — |
| Dress To | vtex | 6628 | 1392 | 6628 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28"} |
| Farm | vtex | 2935 | 56 | 2943 | 0.981 | — |
| Zinzane | vtex | 2375 | 136 | 2454 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2375, "paginavel": 2454}} |
| Lanca Perfume | vtex | 2123 | 148 | 2125 | 1.0 | — |
| Le Lis Blanc | vtex | 1760 | 110 | 1765 | 1.0 | — |
| Maria Filo | vtex | 1630 | 151 | 1630 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 35 (1050-1099, OrderByNameASC)"} |
| Animale | vtex | 1509 | 199 | 1509 | 1.0 | — |
| Morena Rosa | vtex | 1177 | 68 | 1177 | 1.0 | — |
| Cantao | vtex | 812 | 58 | 812 | 1.0 | — |
| Bo.Bo | vtex | 754 | 78 | 754 | 1.0 | — |
| NV | vtex | 563 | 0 | 1329 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 138", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 563, "paginavel": 1329}} |
| Amaro | shopify | 276 | 67 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | parcial | 4 | 56.351 | http 500 ao paginar categoria VTEX 1000003/1004161/1004164 (450-499, OrderByNameASC) |
| Dress To | incerta | — | — | catalogo VTEX declarou zero na categoria 28 |
| Maria Filo | incerta | — | — | http 500 ao paginar categoria VTEX 35 (1050-1099, OrderByNameASC) |
| NV | incerta | — | — | catalogo VTEX declarou zero na categoria 138 |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 41 | 576 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 2871 | 1.0 | {"erro": null, "modo": "defasagem", "execucoes": {"0": {"itens": 2871, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 4, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-21", "termos_sem_perna_de_busca": ["romantico"], "grupos_adiados_por_orcamento": 1} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
