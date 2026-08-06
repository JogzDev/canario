# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-06T09:44:34.151075+00:00

**Data observada:** 2026-08-06

**Estado:** ATENÇÃO


## Portão operacional

- ⚠️ busca caiu 87% contra a media de 7 dias (462 vs 3626)


## Varejo

- Produtos **visitados**: 62408

- Snapshots **gravados** (delta, B3): 21624

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 24118 | 9869 | 24468 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "faixas_truncadas": [{"faixa": "0-1", "existem": 41287, "coletados": 2500}, {"faixa": "0-1", "existem": 11390, "coletados": 2500}, {"faixa": "0-1", "existem": 7261, "coletados": 2500}, {"faixa": "0-1", "existem": 3480, "coletados": 2500}, {"faixa": "0-1", "existem": 6928, "coletados": 2500}]} |
| Hering | vtex | 7803 | 2800 | 7803 | 0.983 | — |
| PatBo | shopify | 7405 | 287 | — | 1.0 | — |
| Dress To | vtex | 6603 | 2407 | 6603 | 1.0 | — |
| Farm | vtex | 2841 | 535 | 2841 | 0.985 | — |
| Lanca Perfume | vtex | 2744 | 1678 | 2746 | 1.0 | — |
| Zinzane | vtex | 2375 | 2029 | 2472 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2375, "paginavel": 2472}} |
| Le Lis Blanc | vtex | 1658 | 1138 | 1658 | 1.0 | — |
| Animale | vtex | 1623 | 133 | 1629 | 1.0 | — |
| Maria Filo | vtex | 1507 | 263 | 1507 | 1.0 | — |
| Morena Rosa | vtex | 1168 | 89 | 1168 | 1.0 | — |
| Cantao | vtex | 909 | 238 | 909 | 1.0 | — |
| Bo.Bo | vtex | 819 | 51 | 819 | 1.0 | — |
| NV | vtex | 546 | 81 | 1031 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 546, "paginavel": 1031}} |
| Amaro | shopify | 289 | 26 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 61 | 490 | 0.812 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 28, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 13, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 0, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Steal the Look": "feed http 404", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 3 | 462 | 0.5 | {"modo": "semanal", "execucoes": {"0": {"itens": 165, "tentados": 3, "responderam": 1, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3}]}, "1": {"itens": 297, "tentados": 3, "responderam": 2, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}]}}, "tentativa": 1, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 6, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1, "tentativa": 1}], "semana_mais_recente": "2026-08-06", "termos_sem_perna_de_busca": ["romantico"], "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
