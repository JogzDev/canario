# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-07T19:48:25.090565+00:00

**Data observada:** 2026-08-07

**Estado:** sem alerta crítico


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 49531

- Snapshots **gravados** (delta, B3): 12305

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 15984 | 1397 | 22146 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 15984, "paginavel": 22146}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41296, "coletados": 2500}, {"faixa": "0-1", "existem": 11395, "coletados": 2500}, {"faixa": "0-1", "existem": 7275, "coletados": 2500}, {"faixa": "0-1", "existem": 3478, "coletados": 2500}, {"faixa": "0-1", "existem": 6931, "coletados": 2500}]} |
| PatBo | shopify | 7406 | 7053 | — | 1.0 | — |
| Hering | vtex | 6158 | 1412 | 7804 | 0.983 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 6158, "paginavel": 7804}} |
| Dress To | vtex | 5128 | 404 | 6603 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5128, "paginavel": 6603}} |
| Lanca Perfume | vtex | 2732 | 437 | 2743 | 1.0 | — |
| Zinzane | vtex | 2349 | 100 | 2444 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2349, "paginavel": 2444}} |
| Le Lis Blanc | vtex | 1707 | 404 | 1776 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1707, "paginavel": 1776}} |
| Animale | vtex | 1627 | 233 | 1627 | 1.0 | — |
| Maria Filo | vtex | 1501 | 315 | 1521 | 1.0 | — |
| Farm | vtex | 1223 | 236 | 2861 | 0.966 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 1223, "paginavel": 2861}} |
| Morena Rosa | vtex | 1178 | 94 | 1178 | 1.0 | — |
| Cantao | vtex | 900 | 98 | 900 | 1.0 | — |
| Bo.Bo | vtex | 818 | 69 | 818 | 1.0 | — |
| NV | vtex | 548 | 32 | 1037 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 548, "paginavel": 1037}} |
| Amaro | shopify | 272 | 21 | — | 0.996 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 62 | 490 | 0.812 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 12, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 0}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403", "Harpers Bazaar Brasil": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 2871 | 1.0 | {"modo": "defasagem", "execucoes": {"0": {"itens": 2871, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 3, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-07", "termos_sem_perna_de_busca": ["algodao", "basico", "boho_artesanal"], "grupos_adiados_por_orcamento": 0} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
