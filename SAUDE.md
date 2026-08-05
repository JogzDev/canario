# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-05T01:44:52.193478+00:00

**Data observada:** 2026-08-04

**Estado:** sem alerta crítico


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 57836

- Snapshots **gravados** (delta, B3): 2529

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 21184 | 378 | 22235 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 21184, "paginavel": 22235}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41215, "coletados": 2500}, {"faixa": "0-1", "existem": 11371, "coletados": 2500}, {"faixa": "0-1", "existem": 7269, "coletados": 2500}, {"faixa": "0-1", "existem": 3474, "coletados": 2500}, {"faixa": "0-1", "existem": 6917, "coletados": 2500}]} |
| Hering | vtex | 7736 | 884 | 7774 | 0.983 | — |
| PatBo | shopify | 7400 | 163 | — | 1.0 | — |
| Dress To | vtex | 5476 | 171 | 6535 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5476, "paginavel": 6535}} |
| Farm | vtex | 2703 | 320 | 2719 | 0.986 | — |
| Lanca Perfume | vtex | 2597 | 150 | 2599 | 1.0 | — |
| Zinzane | vtex | 2410 | 33 | 2515 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2410, "paginavel": 2515}} |
| Le Lis Blanc | vtex | 1619 | 47 | 1623 | 1.0 | — |
| Animale | vtex | 1603 | 80 | 1603 | 1.0 | — |
| Maria Filo | vtex | 1466 | 125 | 1466 | 1.0 | — |
| Morena Rosa | vtex | 1180 | 46 | 1180 | 1.0 | — |
| Cantao | vtex | 849 | 36 | 849 | 1.0 | — |
| Bo.Bo | vtex | 816 | 35 | 816 | 1.0 | — |
| NV | vtex | 484 | 29 | 853 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 484, "paginavel": 853}} |
| Amaro | shopify | 313 | 32 | — | 1.0 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 17 | 68 | 529 | 0.882 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 10, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Vogue Business": 30, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 4 | 4437 | 0.667 | {"modo": "backfill", "execucoes": {"0": {"itens": 1044, "tentados": 3, "responderam": 1, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2}]}, "1": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 1, "grupos_totais": 9, "termos_aprovados": 40, "termos_com_serie": 17, "grupos_planejados": 6, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2, "tentativa": 0}], "semana_mais_recente": "2026-08-04", "termos_sem_perna_de_busca": ["basico", "boho_artesanal"], "grupos_adiados_por_orcamento": 6} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
