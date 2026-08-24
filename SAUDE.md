# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-24T07:21:23.211870+00:00

**Data observada:** 2026-08-24

**Estado:** sem alerta crítico · cobertura parcial — 3 de 15 marcas (3 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 40846

- Snapshots **gravados** (delta, B3): 4876

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| PatBo | shopify | 7464 | 206 | — | 1.0 | — |
| Hering | vtex | 7035 | 573 | 7827 | 0.992 | {"erro": "http 500 ao paginar categoria VTEX 29 (1200-1249, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 7035, "paginavel": 7827}} |
| Dress To | vtex | 6253 | 237 | 6253 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 58/3/20"} |
| C&A | vtex | 4434 | 2478 | 4434 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 1000003/1004161/1004162", "indisponiveis_fora_do_universo": 18142} |
| Farm | vtex | 2869 | 249 | 2869 | 0.98 | — |
| Lanca Perfume | vtex | 2362 | 270 | 2362 | 1.0 | — |
| Zinzane | vtex | 2236 | 102 | 2236 | 1.0 | — |
| Le Lis Blanc | vtex | 1647 | 205 | 1647 | 1.0 | — |
| Maria Filo | vtex | 1572 | 117 | 1572 | 1.0 | — |
| Animale | vtex | 1492 | 113 | 1492 | 1.0 | — |
| Morena Rosa | vtex | 1123 | 103 | 1123 | 1.0 | — |
| Bo.Bo | vtex | 794 | 65 | 794 | 1.0 | — |
| Cantao | vtex | 765 | 61 | 765 | 1.0 | — |
| NV | vtex | 540 | 30 | 540 | 1.0 | — |
| Amaro | shopify | 260 | 67 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | incerta | — | — | http 500 ao contar categoria VTEX 1000003/1004161/1004162 |
| Dress To | incerta | — | — | http 500 ao contar categoria VTEX 58/3/20 |
| Hering | incerta | — | — | http 500 ao paginar categoria VTEX 29 (1200-1249, OrderByNameASC) |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 47 | 577 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-10", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
