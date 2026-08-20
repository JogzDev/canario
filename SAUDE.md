# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-20T20:20:13.236395+00:00

**Data observada:** 2026-08-20

**Estado:** sem alerta crítico · cobertura parcial — 5 de 15 marcas (1 com catálogo cortado; 4 sem contagem confiável)


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 49722

- Snapshots **gravados** (delta, B3): 18227

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 16052 | 7404 | 17832 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 16052, "paginavel": 17832}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41018, "coletados": 2500}, {"faixa": "0-1", "existem": 11269, "coletados": 2500}, {"faixa": "0-1", "existem": 7192, "coletados": 2500}, {"faixa": "0-1", "existem": 6874, "coletados": 2500}]} |
| Hering | vtex | 7523 | 3342 | 7797 | 0.989 | {"erro": "http 500 ao contar categoria VTEX 38", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 7523, "paginavel": 7797}} |
| PatBo | shopify | 7461 | 401 | — | 1.0 | — |
| Dress To | vtex | 5288 | 2029 | 6607 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 28", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5288, "paginavel": 6607}} |
| Zinzane | vtex | 2126 | 1407 | 2208 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2126, "paginavel": 2208}} |
| Lanca Perfume | vtex | 1944 | 712 | 1946 | 1.0 | — |
| Le Lis Blanc | vtex | 1708 | 891 | 1708 | 1.0 | — |
| Maria Filo | vtex | 1654 | 1091 | 1654 | 1.0 | — |
| Animale | vtex | 1508 | 145 | 1509 | 1.0 | — |
| Morena Rosa | vtex | 1167 | 106 | 1167 | 1.0 | — |
| Farm | vtex | 912 | 150 | 2978 | 0.941 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 912, "paginavel": 2978}} |
| Cantao | vtex | 784 | 226 | 784 | 1.0 | {"erro": "http 500 ao contar categoria VTEX 60"} |
| Bo.Bo | vtex | 756 | 44 | 756 | 1.0 | — |
| NV | vtex | 564 | 220 | 1330 | 1.0 | {"erro": "catalogo VTEX declarou zero na categoria 138", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 564, "paginavel": 1330}} |
| Amaro | shopify | 275 | 59 | — | 1.0 | — |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | parcial | 4 | 56.353 | paginação parou antes do fim |
| Cantao | incerta | — | — | http 500 ao contar categoria VTEX 60 |
| Dress To | incerta | — | — | catalogo VTEX declarou zero na categoria 28 |
| Hering | incerta | — | — | http 500 ao contar categoria VTEX 38 |
| NV | incerta | — | — | catalogo VTEX declarou zero na categoria 138 |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 41 | 576 | 0.875 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 3132 | 1.0 | {"erro": null, "modo": "defasagem", "execucoes": {"1": {"itens": 3132, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 1, "grupos_totais": 7, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-20", "termos_sem_perna_de_busca": ["geometrica"], "grupos_adiados_por_orcamento": 4} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
