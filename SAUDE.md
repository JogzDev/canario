# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-08T07:08:08.488835+00:00

**Data observada:** 2026-08-08

**Estado:** sem alerta crítico


## Portão operacional

- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 43553

- Snapshots **gravados** (delta, B3): 4243

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| C&A | vtex | 9031 | 431 | 10084 | 1.0 | {"truncou": "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada", "divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 9031, "paginavel": 10084}, "faixas_truncadas": [{"faixa": "0-1", "existem": 7244, "coletados": 2500}, {"faixa": "0-1", "existem": 3463, "coletados": 2500}, {"faixa": "0-1", "existem": 6921, "coletados": 2500}]} |
| PatBo | shopify | 7406 | 219 | — | 1.0 | — |
| Hering | vtex | 5881 | 489 | 7785 | 0.986 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 5881, "paginavel": 7785}} |
| Dress To | vtex | 4820 | 325 | 6603 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 4820, "paginavel": 6603}} |
| Farm | vtex | 2868 | 926 | 2868 | 0.985 | — |
| Lanca Perfume | vtex | 2712 | 414 | 2714 | 1.0 | — |
| Zinzane | vtex | 2368 | 127 | 2463 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 2368, "paginavel": 2463}} |
| Le Lis Blanc | vtex | 1791 | 404 | 1791 | 1.0 | — |
| Animale | vtex | 1625 | 169 | 1625 | 1.0 | — |
| Maria Filo | vtex | 1529 | 257 | 1529 | 1.0 | — |
| Morena Rosa | vtex | 1196 | 73 | 1196 | 1.0 | — |
| Cantao | vtex | 895 | 86 | 895 | 1.0 | — |
| Bo.Bo | vtex | 750 | 135 | 750 | 1.0 | — |
| NV | vtex | 416 | 24 | 903 | 1.0 | {"divergencia": {"obs": "coletado < paginavel; o normal e dedup (produto em duas categorias). Perda real aparece em faixas_truncadas.", "coletado": 416, "paginavel": 903}} |
| Amaro | shopify | 265 | 164 | — | 0.996 | — |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 16 | 65 | 498 | 0.875 | {"por_veiculo": {"FFW": 0, "WWD": 10, "Dazed": 15, "Vogue": 29, "Hypebeast": 20, "Refinery29": 10, "Elle Brasil": 10, "Highsnobiety": 10, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "Fashion Bubbles": 24, "Business of Fashion": 0, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10}, "veiculos_com_erro": {"FFW": "feed http 403", "Business of Fashion": "feed http 403"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 3120 | 1.0 | {"modo": "semanal", "execucoes": {"0": {"itens": 3120, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 10, "termos_aprovados": 40, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-08", "termos_sem_perna_de_busca": ["algodao"], "grupos_adiados_por_orcamento": 7} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
