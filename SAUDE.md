# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-21T12:37:48.581784+00:00

**Data observada:** 2026-08-21

**Estado:** sem alerta crítico · cobertura completa nas 15 marcas


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 45677

- Snapshots **gravados** (delta, B3): 501

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 7880 | 203 | 7880 | 1.0 | {"indisponiveis_fora_do_universo": 66355} |
| Hering | vtex | 7815 | 47 | 7815 | 0.99 | — |
| PatBo | shopify | 7461 | 6 | — | 1.0 | — |
| Dress To | vtex | 6628 | 29 | 6628 | 1.0 | — |
| Farm | vtex | 2941 | 63 | 2941 | 0.981 | — |
| Zinzane | vtex | 2376 | 0 | 2376 | 1.0 | — |
| Lanca Perfume | vtex | 2122 | 12 | 2122 | 1.0 | — |
| Le Lis Blanc | vtex | 1750 | 0 | 1750 | 1.0 | — |
| Maria Filo | vtex | 1617 | 81 | 1617 | 1.0 | — |
| Animale | vtex | 1507 | 55 | 1507 | 1.0 | — |
| Morena Rosa | vtex | 1177 | 0 | 1177 | 1.0 | — |
| Cantao | vtex | 810 | 3 | 810 | 1.0 | — |
| Bo.Bo | vtex | 754 | 0 | 754 | 1.0 | — |
| NV | vtex | 563 | 2 | 563 | 1.0 | — |
| Amaro | shopify | 276 | 0 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


- Nenhuma marca acusou corte de paginação ou falha de contagem.


## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 39 | 552 | 0.812 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 0, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None", "Fashion Bubbles": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-10", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
