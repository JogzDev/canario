# Pendências

**O que este arquivo é:** o placar entre o que foi **decidido e registrado** e o
que foi **implementado**. Existe porque o pente fino que fiz em 30/07 checou
arquivos que faltavam, e não decisões registradas e não cumpridas — que é a
dívida que mais apareceu, e sempre no meio de outra conversa.

**Regra:** nenhuma etapa nova começa com item vermelho relevante para ela. Toda
decisão nova nasce com uma linha aqui. Atualizado a cada commit que mexe no
estado de algum item.

Última varredura: **31/07/2026** (atualizado ao fim de cada etapa).

**Lição de 31/07, que mudou como este arquivo é lido:** K1 e K4 estavam marcados
como ✅ porque `computar_eventos()` existia e estava correta. Só que **nada a
chamava** — não estava no motor. A tabela de eventos ficou parada um dia inteiro
enquanto a coleta rodava, e quem descobriu foi o JP olhando a tela, não o placar.
Daqui em diante, uma linha só fica verde quando existe **o caminho inteiro**:
função escrita, chamada por alguém, e o resultado visível onde deveria estar.

---

## Constantes da auditoria inicial (K1–K11)

| id | O que exige | Onde vive | Estado |
|---|---|---|---|
| K1 | Saída de linha: 14 dias ausente **com a marca coletando** | `computar_eventos()`, chamada pelo `motor_computar.py` | ✅ Feito |
| K2 | Continuativo: idade ≥ 26 semanas | — | 🔴 Não feito |
| K3 | Continuativo: 3 reposições em 12 semanas | — | 🔴 Não feito |
| K4 | Remarcação só com queda ≥ 5% | `computar_eventos()`, chamada pelo `motor_computar.py` | ✅ Feito |
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
| §20 | Alerta quando uma fonte cai mais de 70% vs. média de 7 dias | 🟡 Parcial — as 3 pernas agora gravam `saude` (busca entrou em 01/08); falta o limiar dos 70% |
| §22 | Índice do cluster (conjunto de atributos de uma peça) | 🔴 Não feito — só existe índice por atributo |
| §24 | Curva de tamanhos | ✅ Feito — migração 0008, no motor, com tela própria. **Marco de demo 1 fechado** |
| §29 | Bloco de similares com preço, remarcação e estado da grade | 🔴 Não feito |
| §31 | Termômetro (validação retroativa) | ⚪ Depende dos dados do Pedro |
| B5 | `anexos/mapa_categorias.csv` | 🟡 Substituído na prática por `departamentos_vtex.json` — decidir se descarta formalmente |

---

## Dívidas de engenharia

| O que | Estado |
|---|---|
| Testes rodando no CI a cada push | ✅ Feito — `.github/workflows/testes.yml`, verde nos dois jobs |
| Aba Comparar verificada visualmente | ✅ Feito — refeita em 31/07 e conferida no simulador |
| Backfill do Trends completo | 🟡 20 de 40 termos. **Estava parado há 19 dias** — cron semanal + retomada permanente. Corrigido em 01/08: cron diário, modo semanal, e linha de `saude` |
| `artigo_termos` | ⚪ Tabela existe e não é usada; os veículos passaram a viver em `series_semanais.meta`, que é onde o app lê |

---

## Bloco de reclamações do JP (31/07)

| O que ele apontou | Estado |
|---|---|
| Reposições e remarcações mostrando dado de anteontem | ✅ Feito — `computar_eventos()` entrou no motor; roda todo dia às 04:10 |
| "*3ª reposição dos tamanhos PP/P em menos de 2 meses" | ✅ Feito — ordinal na view; **só acende com história**, hoje todo evento é o 1º |
| Agrupar eventos por marca | ✅ Feito |
| Número sem unidade ("1,15 o quê?") | ✅ Feito — `Explicacao.numeroComUnidade` |
| Explicar ao usuário por que é "pico" | ✅ Feito — `Explicacao.porQue`, testado contra `computar_indice()` |
| Nome dos sites que sustentam a conclusão | 🟡 Coletor grava `meta.veiculos` a partir de 01/08; as linhas já no banco só ganham os nomes na próxima coleta editorial |
| Aba Comparar sem propósito claro | ✅ Feito — dois eixos (painel × editorial) e a distância entre eles |
| Atalho de importar aparecendo duas vezes | ✅ Feito — o do canto superior direito saiu |
| Busca "vestido de bolinha" devolvendo só "Vestido" | ✅ Feito — `bolinha` no vocabulário + leitura do conjunto |
| PDF de imagem não era lido | ✅ Feito — rasteriza e passa pelo OCR |
| Aceitar JPG | ✅ Feito — tipos nomeados um a um |
| "Entender do que se trata e classificar a peça principal" | 🟡 **Parcial e declarado.** Cor sai do pixel (`cinza`, 94% de cobertura, no arquivo dele). **Nomear a peça exige modelo treinado e não existe** |

---

## Curva de tamanhos (01/08) — o que ficou de dívida nova

| O que | Estado |
|---|---|
| Grade da Amaro com nome de COR no lugar de tamanho | 🟡 Coletor corrigido em 01/08; **os 335 produtos no banco só se corrigem na próxima coleta pelo runner residencial**. O normalizador já os descarta, então não contaminam a curva |
| Escada plus size da C&A (GG1–GG6, X1, XGGG) | ⚪ Fica fora da curva de propósito: é outra escada, e encaixá-la à força inventaria degraus. Decidir se ganha leitura própria |
| Acessório e calçado no painel | ✅ Feito — 2.057 produtos fora do segmento; filtro pelo início do título, calibrado por medição |
| Nome da marca virando atributo | ✅ Feito — 5.710 ligações erradas apagadas; `motor_atributos.py` limpa o nome antes de casar |
| Janela de 14 dias com 8 dias de coleta | 🟡 A janela é maior que a história; ela se preenche sozinha até o Demo Day |

### O que a entrada por arquivo ainda deve

| O que falta | Por quê |
|---|---|
| Calibrar a cor no catálogo inteiro | Hoje são 5 fotos. Temos 180 mil imagens rotuladas, mas os CDNs devolvem 429 para o datacenter — **precisa do runner residencial**, a 1 req/s (regra 7) |
| Classificar categoria a partir da imagem | Exige modelo treinado. O conjunto rotulado já existe (título → `produto_termos`); falta baixar as imagens e treinar |

---

## O que está de pé e verificado

Para o placar não parecer só dívida:

- Coleta diária de varejo, busca e editorial, com cron e runner residencial
- Motor: série de varejo, z-score, índice, estados, eventos
- Portão de cobertura da §8 bloqueando célula abaixo do mínimo
- RLS verificada por requisição real: app lê 3 tabelas, toma 401 nas demais
- App com as 3 abas lendo dado real, 21 testes verdes
- Lista negra de vocabulário (§6) varrendo a interface
