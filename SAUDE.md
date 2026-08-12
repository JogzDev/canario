# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-12T00:21:04.488885+00:00

**Data observada:** 2026-08-11

**Estado:** sem alerta crítico


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- varejo/PatBo retornou zero hoje (http 429 (persistiu apos backoff longo)); 1º dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 41291

- Snapshots **gravados** (delta, B3): 11021

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 10661 | 5808 | 12011 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 10661, "paginavel": 12011}, "faixas_truncadas": [{"faixa": "0-1", "existem": 41114, "coletados": 2500}, {"faixa": "0-1", "existem": 11334, "coletados": 2500}, {"faixa": "0-1", "existem": 6884, "coletados": 2500}]} |
| Hering | vtex | 7781 | 1147 | 7781 | 0.986 | — |
| Dress To | vtex | 6603 | 2340 | 6603 | 1.0 | — |
| Farm | vtex | 2858 | 42 | 2858 | 0.984 | — |
| Lanca Perfume | vtex | 2538 | 439 | 2539 | 1.0 | — |
| Zinzane | vtex | 2508 | 292 | 2569 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2508, "paginavel": 2569}} |
| Le Lis Blanc | vtex | 1683 | 271 | 1683 | 1.0 | — |
| Animale | vtex | 1614 | 122 | 1614 | 1.0 | — |
| Maria Filo | vtex | 1561 | 293 | 1561 | 1.0 | — |
| Morena Rosa | vtex | 1196 | 98 | 1196 | 1.0 | — |
| Cantao | vtex | 841 | 83 | 841 | 1.0 | — |
| Bo.Bo | vtex | 781 | 53 | 781 | 1.0 | — |
| NV | vtex | 416 | 33 | 903 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 416, "paginavel": 903}} |
| Amaro | shopify | 250 | 0 | — | 1.0 | {"erro": "http 500"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 61 | 496 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 30, "Hypebeast": 19, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 8, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 6 | 6 | 6525 | 1.0 | {"modo": "semanal", "execucoes": {"0": {"itens": 3132, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}, "1": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 1, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 6, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-11", "termos_sem_perna_de_busca": ["algodao", "basico", "boho_artesanal"], "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
