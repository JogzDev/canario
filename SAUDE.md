# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-12T08:50:47.815611+00:00

**Data observada:** 2026-08-12

**Estado:** ATENÇÃO


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- varejo/PatBo retornou zero hoje (http 429 (persistiu apos backoff longo)); 2º dia



- ⚠️ busca retornou zero sem dizer por quê


## Varejo

- Produtos **visitados**: 40580

- Snapshots **gravados** (delta, B3): 18049

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 12811 | 6627 | 13111 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 12811, "paginavel": 13111}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41114, "coletados": 2500}, {"faixa": "0-1", "existem": 11334, "coletados": 2500}, {"faixa": "0-1", "existem": 6884, "coletados": 2500}]} |
| Hering | vtex | 6587 | 3010 | 7782 | 0.989 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 6587, "paginavel": 7782}} |
| Dress To | vtex | 5807 | 1877 | 5815 | 1.0 | — |
| Farm | vtex | 2866 | 1329 | 2866 | 0.985 | — |
| Zinzane | vtex | 2180 | 94 | 2265 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2180, "paginavel": 2265}} |
| Lanca Perfume | vtex | 1903 | 591 | 1904 | 1.0 | — |
| Le Lis Blanc | vtex | 1763 | 527 | 1763 | 1.0 | — |
| Animale | vtex | 1625 | 1168 | 1625 | 1.0 | — |
| Maria Filo | vtex | 1557 | 670 | 1557 | 1.0 | — |
| Morena Rosa | vtex | 1200 | 890 | 1200 | 1.0 | — |
| Cantao | vtex | 826 | 397 | 826 | 1.0 | — |
| Bo.Bo | vtex | 789 | 516 | 789 | 1.0 | — |
| NV | vtex | 416 | 283 | 905 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 416, "paginavel": 905}} |
| Amaro | shopify | 250 | 70 | — | 1.0 | {"erro": "http 500"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 55 | 503 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 15, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 0 | 0 | 0.0 | {"modo": "semanal", "execucoes": {"0": {"itens": 0, "tentados": 3, "responderam": 0, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3}]}, "1": {"itens": 0, "tentados": 3, "responderam": 0, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3}]}}, "tentativa": 1, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 6, "grupos_que_falharam": [{"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3, "tentativa": 0}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 1, "tentativa": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 2, "tentativa": 1}, {"erro": "falhou apos 4 tentativas (HTTP 429)", "grupo": 3, "tentativa": 1}], "semana_mais_recente": "2026-08-12", "termos_sem_perna_de_busca": null, "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
