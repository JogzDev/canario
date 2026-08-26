# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-26T07:19:20.030512+00:00

**Data observada:** 2026-08-26

**Estado:** sem alerta crítico · cobertura parcial — 9 de 15 marcas (9 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- varejo/Amaro retornou zero hoje (http 500); 2º dia

- varejo/PatBo retornou zero hoje (http 429 (persistiu apos backoff longo)); 2º dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 36853

- Snapshots **gravados** (delta, B3): 14089

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 8527 | 3498 | 8527 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1000003/1004161/1004170 (950-999, OrderByNameASC)", "indisponiveis_fora_do_universo": 59305} |
| Hering | vtex | 7830 | 2005 | 7830 | 0.994 | {"erro": "http 500 ao paginar categoria VTEX 581 (50-99, OrderByNameASC)"} |
| Dress To | vtex | 4707 | 1120 | 5851 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 58/1 (100-149, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 4707, "paginavel": 5851}} |
| Farm | vtex | 3016 | 2106 | 3035 | 0.981 | {"erro": "http 500 ao paginar categoria VTEX 1 (1400-1449, OrderByNameASC)"} |
| Lanca Perfume | vtex | 2364 | 1718 | 2364 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1 (1150-1199, OrderByNameASC)"} |
| Zinzane | vtex | 2290 | 174 | 2370 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1/8 (50-99, OrderByNameASC)", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2290, "paginavel": 2370}} |
| Le Lis Blanc | vtex | 1678 | 437 | 1678 | 1.0 | — |
| Maria Filo | vtex | 1623 | 456 | 1623 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 35 (950-999, OrderByNameASC)"} |
| Animale | vtex | 1533 | 919 | 1533 | 1.0 | — |
| Morena Rosa | vtex | 1123 | 605 | 1123 | 1.0 | — |
| Cantao | vtex | 806 | 397 | 806 | 1.0 | — |
| Bo.Bo | vtex | 781 | 393 | 781 | 1.0 | — |
| NV | vtex | 575 | 261 | 575 | 1.0 | — |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 500"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | incerta | — | — | http 500 ao paginar categoria VTEX 1000003/1004161/1004170 (950-999, OrderByNameASC) |
| Dress To | incerta | — | — | http 500 ao paginar categoria VTEX 58/1 (100-149, OrderByNameASC) |
| Farm | incerta | — | — | http 500 ao paginar categoria VTEX 1 (1400-1449, OrderByNameASC) |
| Hering | incerta | — | — | http 500 ao paginar categoria VTEX 581 (50-99, OrderByNameASC) |
| Lanca Perfume | incerta | — | — | http 500 ao paginar categoria VTEX 1 (1150-1199, OrderByNameASC) |
| Maria Filo | incerta | — | — | http 500 ao paginar categoria VTEX 35 (950-999, OrderByNameASC) |
| Zinzane | incerta | — | — | http 500 ao paginar categoria VTEX 1/8 (50-99, OrderByNameASC) |
| Amaro | incerta | — | — | http 500 |
| PatBo | incerta | — | — | http 429 (persistiu apos backoff longo) |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 26 | 93 | 837 | 0.923 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 30, "Claudia": 10, "Hypebeast": 20, "Glamour US": 30, "Refinery29": 10, "W Magazine": 50, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "The Zoe Report": 50, "Fashion Bubbles": 24, "Marie Claire US": 50, "Tom and Lorenzo": 10, "Fashion Bomb Daily": 10, "Fashion Gone Rogue": 10, "Fashion Week Daily": 10, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10, "Red Carpet Fashion Awards": 30}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 3132 | 1.0 | {"erro": null, "modo": "defasagem", "execucoes": {"0": {"itens": 3132, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 8, "termos_aprovados": 43, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-26", "termos_sem_perna_de_busca": ["geometrica"], "grupos_adiados_por_orcamento": 5} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
