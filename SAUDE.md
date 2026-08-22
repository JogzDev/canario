# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-22T06:59:39.331353+00:00

**Data observada:** 2026-08-22

**Estado:** sem alerta crítico · cobertura parcial — 6 de 15 marcas (6 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 42896

- Snapshots **gravados** (delta, B3): 6164

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 9142 | 2077 | 9142 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 1000003/1004161/1004167", "indisponiveis_fora_do_universo": 59035} |
| PatBo | shopify | 7464 | 182 | — | 1.0 | — |
| Hering | vtex | 5574 | 749 | 6146 | 0.99 | {"erro": "http 500 ao contar categoria VTEX 14", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5574, "paginavel": 6146}} |
| Dress To | vtex | 5267 | 403 | 6325 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 58/1 (300-349, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5267, "paginavel": 6325}} |
| Lanca Perfume | vtex | 2482 | 938 | 2482 | 1.0 | — |
| Farm | vtex | 2300 | 334 | 2937 | 0.976 | {"erro": "http 500 ao paginar categoria VTEX 1 (400-449, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2300, "paginavel": 2937}} |
| Zinzane | vtex | 2277 | 241 | 2277 | 1.0 | — |
| Le Lis Blanc | vtex | 1770 | 269 | 1770 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 2 (1300-1349, OrderByNameASC)"} |
| Maria Filo | vtex | 1606 | 195 | 1606 | 1.0 | — |
| Animale | vtex | 1500 | 164 | 1500 | 1.0 | — |
| Morena Rosa | vtex | 1126 | 199 | 1126 | 1.0 | — |
| Cantao | vtex | 792 | 70 | 792 | 1.0 | — |
| Bo.Bo | vtex | 782 | 253 | 782 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 2 (250-299, OrderByNameASC)"} |
| NV | vtex | 541 | 50 | 541 | 1.0 | — |
| Amaro | shopify | 273 | 40 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| Bo.Bo | incerta | — | — | http 500 ao paginar categoria VTEX 2 (250-299, OrderByNameASC) |
| C&A | incerta | — | — | http 500 ao contar categoria VTEX 1000003/1004161/1004167 |
| Dress To | incerta | — | — | http 500 ao paginar categoria VTEX 58/1 (300-349, OrderByNameASC) |
| Farm | incerta | — | — | http 500 ao paginar categoria VTEX 1 (400-449, OrderByNameASC) |
| Hering | incerta | — | — | http 500 ao contar categoria VTEX 14 |
| Le Lis Blanc | incerta | — | — | http 500 ao paginar categoria VTEX 2 (1300-1349, OrderByNameASC) |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 51 | 575 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 28, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-10", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
