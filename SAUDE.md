# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-14T07:35:59.553800+00:00

**Data observada:** 2026-08-14

**Estado:** ATENÇÃO


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- busca não consultada hoje: séries já estavam em dia

- varejo/Amaro retornou zero hoje (http 429 (persistiu apos backoff longo)); 1º dia

- varejo/PatBo retornou zero hoje (http 429 (persistiu apos backoff longo)); 1º dia



- ⚠️ varejo/Bo.Bo retornou zero sem dizer por quê


## Varejo

- Produtos **visitados**: 34186

- Snapshots **gravados** (delta, B3): 6411

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| Hering | vtex | 7776 | 1085 | 7782 | 0.986 | — |
| C&A | vtex | 6574 | 471 | 7224 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 6574, "paginavel": 7224}, "faixas_truncadas": [{"faixa": "0-1", "existem": 11286, "coletados": 2500}, {"faixa": "0-1", "existem": 7219, "coletados": 2500}]} |
| Dress To | vtex | 5819 | 2158 | 5819 | 1.0 | — |
| Farm | vtex | 3008 | 508 | 3008 | 0.985 | — |
| Zinzane | vtex | 2169 | 150 | 2248 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2169, "paginavel": 2248}} |
| Lanca Perfume | vtex | 1857 | 543 | 1858 | 1.0 | — |
| Le Lis Blanc | vtex | 1851 | 451 | 1851 | 1.0 | — |
| Maria Filo | vtex | 1679 | 569 | 1679 | 1.0 | — |
| Animale | vtex | 1606 | 220 | 1606 | 1.0 | — |
| Cantao | vtex | 812 | 86 | 812 | 1.0 | — |
| Morena Rosa | vtex | 550 | 115 | 1193 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 550, "paginavel": 1193}} |
| NV | vtex | 485 | 55 | 1098 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 485, "paginavel": 1098}} |
| Bo.Bo | vtex | 0 | 0 | — | — | — |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 30 | 482 | 0.812 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 18, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 0, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Fashion Bubbles": "feed http None", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 0 | 0 | 0 | — | {"motivo": "todas as series de busca estao em dia", "termos_em_dia": 40, "termos_aprovados": 40, "corte_de_frescura": "2026-08-03", "adiado_por_cadencia": true} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
