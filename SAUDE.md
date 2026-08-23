# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-23T07:02:14.185442+00:00

**Data observada:** 2026-08-23

**Estado:** sem alerta crítico · cobertura parcial — 2 de 15 marcas (2 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 42331

- Snapshots **gravados** (delta, B3): 3502

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| PatBo | shopify | 7464 | 84 | — | 1.0 | — |
| C&A | vtex | 7373 | 855 | 9058 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1000003/1004161/1004162 (1100-1149, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 7373, "paginavel": 9058}, "indisponiveis_fora_do_universo": 66283} |
| Dress To | vtex | 6325 | 650 | 6325 | 1.0 | — |
| Hering | vtex | 5291 | 562 | 5933 | 0.992 | {"erro": "http 500 ao contar categoria VTEX 26", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5291, "paginavel": 5933}} |
| Farm | vtex | 2923 | 357 | 2923 | 0.981 | — |
| Lanca Perfume | vtex | 2412 | 171 | 2412 | 1.0 | — |
| Zinzane | vtex | 2254 | 148 | 2254 | 1.0 | — |
| Le Lis Blanc | vtex | 1699 | 112 | 1699 | 1.0 | — |
| Maria Filo | vtex | 1596 | 158 | 1596 | 1.0 | — |
| Animale | vtex | 1504 | 168 | 1504 | 1.0 | — |
| Morena Rosa | vtex | 1123 | 23 | 1123 | 1.0 | — |
| Cantao | vtex | 780 | 106 | 780 | 1.0 | — |
| Bo.Bo | vtex | 779 | 56 | 779 | 1.0 | — |
| NV | vtex | 540 | 40 | 540 | 1.0 | — |
| Amaro | shopify | 268 | 12 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | incerta | — | — | http 500 ao paginar categoria VTEX 1000003/1004161/1004162 (1100-1149, OrderByNameASC) |
| Hering | incerta | — | — | http 500 ao contar categoria VTEX 26 |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 49 | 576 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-10", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
