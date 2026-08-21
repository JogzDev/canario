# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-21T05:39:07.749054+00:00

**Data observada:** 2026-08-21

**Estado:** sem alerta crítico · cobertura parcial — 1 de 15 marcas (1 sem contagem confiável)


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 45683

- Snapshots **gravados** (delta, B3): 230

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 7876 | 16 | 7876 | 1.0 | {"indisponiveis_fora_do_universo": 66353} |
| Hering | vtex | 7810 | 37 | 7810 | 0.99 | — |
| PatBo | shopify | 7461 | 0 | — | 1.0 | — |
| Dress To | vtex | 6628 | 15 | 6628 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28"} |
| Farm | vtex | 2942 | 67 | 2942 | 0.981 | — |
| Zinzane | vtex | 2376 | 1 | 2376 | 1.0 | — |
| Lanca Perfume | vtex | 2122 | 19 | 2122 | 1.0 | — |
| Le Lis Blanc | vtex | 1752 | 7 | 1752 | 1.0 | — |
| Maria Filo | vtex | 1629 | 8 | 1629 | 1.0 | — |
| Animale | vtex | 1507 | 58 | 1507 | 1.0 | — |
| Morena Rosa | vtex | 1177 | 2 | 1177 | 1.0 | — |
| Cantao | vtex | 810 | 0 | 810 | 1.0 | — |
| Bo.Bo | vtex | 754 | 0 | 754 | 1.0 | — |
| NV | vtex | 563 | 0 | 563 | 1.0 | — |
| Amaro | shopify | 276 | 0 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| Dress To | incerta | — | — | catalogo VTEX declarou zero na categoria 28 |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 40 | 576 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 1 | 1 | 1044 | 1.0 | {"erro": null, "modo": "defasagem", "execucoes": {"0": {"itens": 1044, "tentados": 1, "responderam": 1, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 1, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 1, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-21", "termos_sem_perna_de_busca": null, "grupos_adiados_por_orcamento": 0} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
