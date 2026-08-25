# SAÚDE — coletores do Canário

**Gerado (UTC):** 2026-08-25T07:15:42.667088+00:00

**Data observada:** 2026-08-25

**Estado:** sem alerta crítico · cobertura parcial — 6 de 15 marcas (6 sem contagem confiável)


## Portão operacional


**Avisos (não travam):** fonte que recusou hoje mas voltou antes de 3 dias seguidos.


- varejo/Amaro retornou zero hoje (http 429 (persistiu apos backoff longo)); 1º dia

- varejo/PatBo retornou zero hoje (http 429 (persistiu apos backoff longo)); 1º dia



- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.


## Varejo

- Produtos **visitados**: 36392

- Snapshots **gravados** (delta, B3): 6781

- Marcas coletando: 15 de 15


| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |
|---|---|---|---|---|---|---|
| Hering | vtex | 7718 | 958 | 7718 | 0.994 | {"erro": "http 500 ao paginar categoria VTEX 14 (150-199, OrderByNameASC)"} |
| C&A | vtex | 6648 | 912 | 6648 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 1000003/1004161/1004162 (850-899, OrderByNameASC)", "indisponiveis_fora_do_universo": 52344} |
| Dress To | vtex | 6639 | 2417 | 6639 | 1.0 | {"erro": "http 500 ao paginar categoria VTEX 58/3/17 (0-49, OrderByNameASC)"} |
| Farm | vtex | 2909 | 917 | 2950 | 0.981 | {"erro": "http 500 ao paginar categoria VTEX 1 (1700-1749, OrderByNameASC)"} |
| Zinzane | vtex | 2282 | 248 | 2282 | 1.0 | — |
| Lanca Perfume | vtex | 2203 | 344 | 2203 | 1.0 | — |
| Maria Filo | vtex | 1666 | 317 | 1666 | 1.0 | — |
| Le Lis Blanc | vtex | 1624 | 164 | 1624 | 1.0 | — |
| Animale | vtex | 1510 | 131 | 1510 | 1.0 | — |
| Morena Rosa | vtex | 1101 | 169 | 1101 | 1.0 | — |
| Bo.Bo | vtex | 789 | 63 | 789 | 1.0 | — |
| Cantao | vtex | 760 | 52 | 760 | 1.0 | — |
| NV | vtex | 543 | 89 | 543 | 1.0 | — |
| Amaro | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |
| PatBo | shopify | 0 | 0 | — | — | {"erro": "http 429 (persistiu apos backoff longo)"} |

## Cobertura do catálogo


Volume e cobertura são perguntas diferentes: a tabela acima diz **quanto veio**, esta diz **se veio inteiro**. Marca com volume normal e faixa truncada passa verde no portão e mesmo assim entregou catálogo cortado.


> A perda é **teto**, não valor exato: as faixas são contadas por categoria e o mesmo produto aparece em mais de uma, então a soma conta repetido.


| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |
|---|---|---:|---:|---|
| C&A | incerta | — | — | http 500 ao paginar categoria VTEX 1000003/1004161/1004162 (850-899, OrderByNameASC) |
| Dress To | incerta | — | — | http 500 ao paginar categoria VTEX 58/3/17 (0-49, OrderByNameASC) |
| Farm | incerta | — | — | http 500 ao paginar categoria VTEX 1 (1700-1749, OrderByNameASC) |
| Hering | incerta | — | — | http 500 ao paginar categoria VTEX 14 (150-199, OrderByNameASC) |
| Amaro | incerta | — | — | http 429 (persistiu apos backoff longo) |
| PatBo | incerta | — | — | http 429 (persistiu apos backoff longo) |

## Outras fontes

| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |
|---|---:|---:|---:|---:|---|
| editorial | 26 | 92 | 836 | 0.923 | {"por_veiculo": {"FFW": 3, "WWD": 10, "Dazed": 0, "Vogue": 29, "Claudia": 10, "Hypebeast": 20, "Glamour US": 30, "Refinery29": 10, "W Magazine": 50, "Elle Brasil": 10, "Highsnobiety": 0, "Vogue Brasil": 100, "Who What Wear": 50, "Glamour Brasil": 100, "Steal the Look": 10, "The Zoe Report": 50, "Fashion Bubbles": 24, "Marie Claire US": 50, "Tom and Lorenzo": 10, "Fashion Bomb Daily": 10, "Fashion Gone Rogue": 10, "Fashion Week Daily": 10, "Business of Fashion": 100, "Marie Claire Brasil": 100, "Harpers Bazaar Brasil": 10, "Red Carpet Fashion Awards": 30}, "veiculos_com_erro": {"Dazed": "feed http None", "Highsnobiety": "feed http None"}, "veiculos_sem_itens": null} |
| busca | 3 | 3 | 3393 | 1.0 | {"erro": null, "modo": "defasagem", "execucoes": {"0": {"itens": 3393, "tentados": 3, "responderam": 3, "grupos_que_falharam": []}}, "tentativa": 0, "grupos_totais": 11, "termos_aprovados": 43, "termos_com_serie": 40, "grupos_planejados": 3, "grupos_que_falharam": null, "semana_mais_recente": "2026-08-25", "termos_sem_perna_de_busca": ["algodao", "basico", "boho_artesanal", "cintura_alta"], "grupos_adiados_por_orcamento": 8} |

---

Queda crítica = volume do dia abaixo de 30% da média das observações positivas dos sete dias anteriores. Ausência e zero também bloqueiam. O motor só deve publicar depois de todas as fontes obrigatórias.
