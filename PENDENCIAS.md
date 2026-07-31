# Pendências

**O que este arquivo é:** o placar entre o que foi **decidido e registrado** e o
que foi **implementado**. Existe porque o pente fino que fiz em 30/07 checou
arquivos que faltavam, e não decisões registradas e não cumpridas — que é a
dívida que mais apareceu, e sempre no meio de outra conversa.

**Regra:** nenhuma etapa nova começa com item vermelho relevante para ela. Toda
decisão nova nasce com uma linha aqui. Atualizado a cada commit que mexe no
estado de algum item.

Última varredura: **30/07/2026** (atualizado ao fim de cada etapa).

---

## Constantes da auditoria inicial (K1–K11)

| id | O que exige | Onde vive | Estado |
|---|---|---|---|
| K1 | Saída de linha: 14 dias ausente **com a marca coletando** | `computar_eventos()` | ✅ Feito |
| K2 | Continuativo: idade ≥ 26 semanas | — | 🔴 Não feito |
| K3 | Continuativo: 3 reposições em 12 semanas | — | 🔴 Não feito |
| K4 | Remarcação só com queda ≥ 5% | `computar_eventos()` | ✅ Feito |
| K5 | Índice do cluster ponderado por raridade (IDF) | — | 🔴 Não feito |
| K6 | Variação % como unidade principal, z entre parênteses | `Leitura.swift` | ✅ Feito |
| K7 | Trends em grupos de 5 com âncora fixa | `coletor_trends.py` | ✅ Feito |
| K8 | Editorial casa só título + resumo | `coletor_editorial.py` | ✅ Feito |
| K9 | Alerta de saúde vira issue no repositório | — | 🔴 Não feito |
| K10 | Termômetro recalibra limiares, nunca pesos | — | ⚪ Depende do termômetro |
| K11 | Coorte fixa; célula com >25% de ausência vira "cobertura insuficiente" | Coorte congelada ✅; regra dos 25% ❌ | 🟡 Parcial |

**K2 e K3 dependem de história que o projeto não tem** — 26 semanas de presença
contínua não existem em 6 dias de coleta. O A1 foi criado justamente para isso,
e também não está feito (abaixo). Enquanto nenhum dos dois existir, **o badge de
peça clássica da §27 não aparece**, e o §23 não consegue separar continuativo de
coleção.

---

## Decisões das instruções do JP (A1–A9)

| id | O que exige | Estado |
|---|---|---|
| A1 | `flag_tipo` presumido por categoria e palavra-chave | 🔴 Não feito — schema aceita os valores, nada preenche |
| A2 | Coletar amplo, classificar depois | ✅ Feito |
| A3 | Forma descritiva do marco de demo 2 | 🔴 Não feito |
| A6 | Cards de similar com identidade visual própria | 🔴 Não feito — depende do design |
| A7 | Visão e referências internas fora da v1 | ✅ Feito (entrada por arquivo voltou em 30/07) |
| §28 | Entrada por arquivo (print, foto, PDF) com OCR, sem câmera | ✅ Feito — `LeitorDeArquivo.swift` |
| §28 | Formulário de confirmação de atributos (humano no circuito) | ✅ Feito — `ImportarPeca.swift` |
| §28 | Retenção zero: arquivo processado e descartado | ✅ Feito — lido em memória, nada em disco |
| A8 | Vocabulário interno nunca vira produto | ✅ Feito — `teste_vocabulario.py` |
| A9 | Roadmap v1.1 | ⚪ Registrado, sem código |

---

## Requisitos do documento ainda em aberto

| Onde | O que exige | Estado |
|---|---|---|
| §20 | Alerta quando uma fonte cai mais de 70% vs. média de 7 dias | 🔴 Não feito — só existe alerta de marca zerada |
| §22 | Índice do cluster (conjunto de atributos de uma peça) | 🔴 Não feito — só existe índice por atributo |
| §24 | Curva de tamanhos (velocidade relativa por tamanho) | 🔴 Não feito — é o marco de demo 1 |
| §29 | Bloco de similares com preço, remarcação e estado da grade | 🔴 Não feito |
| §31 | Termômetro (validação retroativa) | ⚪ Depende dos dados do Pedro |
| B5 | `anexos/mapa_categorias.csv` | 🟡 Substituído na prática por `departamentos_vtex.json` — decidir se descarta formalmente |

---

## Dívidas de engenharia

| O que | Estado |
|---|---|
| Testes rodando no CI a cada push | ✅ Feito — `.github/workflows/testes.yml`, verde nos dois jobs |
| Aba Comparar verificada visualmente | 🔴 Não feito |
| Backfill do Trends completo | 🟡 20 de 41 termos; avança sozinho a cada noite |
| `artigo_termos` | ⚪ Tabela existe e não é usada; contagem vai direto para `series_semanais` |

---

## O que está de pé e verificado

Para o placar não parecer só dívida:

- Coleta diária de varejo, busca e editorial, com cron e runner residencial
- Motor: série de varejo, z-score, índice, estados, eventos
- Portão de cobertura da §8 bloqueando célula abaixo do mínimo
- RLS verificada por requisição real: app lê 3 tabelas, toma 401 nas demais
- App com as 3 abas lendo dado real, 21 testes verdes
- Lista negra de vocabulário (§6) varrendo a interface
