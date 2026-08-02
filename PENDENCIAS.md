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
| K5 | Índice do cluster ponderado por raridade (IDF) | `computar_raridade()` + `indice_do_cluster()`, migração 0010, no motor e na tela | ✅ Feito — **e a fórmula da §22 teve de ser corrigida em 3 pontos** (dimensão, categoria, encolhimento). Ver changelog de 02/08 |
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
| A6 | Cards de similar com identidade visual própria | 🟡 Funcional feito, **sem foto de terceiro**: bloco cuja altura mostra o estado da grade. A identidade visual é da Bianca e troca em `MarcaVisual` |
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
| §22 | Índice do cluster (conjunto de atributos de uma peça) | ✅ Feito — migração 0010, com dispersão e recusa de direção quando os atributos discordam |
| §24 | Curva de tamanhos | ✅ Feito — migração 0008, no motor, com tela própria. **Marco de demo 1 fechado** |
| §29 | Bloco de similares com preço, remarcação e estado da grade | ✅ Feito — migração 0009, `similares_da_peca()`, com o parágrafo-resumo da §29.1 e o percentil de preço da §29.5 |
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

---

## Varredura completa de 02/08/2026 — o que a auditoria achou

**Como ler esta seção:** tudo abaixo foi **medido**, não suspeitado. Cada linha
traz o número que a sustenta. Ordenado por gravidade: o primeiro bloco está
errado **na tela, agora**.

### 🔴 Errado na tela agora

| # | O que | Evidência medida |
|---|---|---|
| V1 | **Os 4 `pico` da semana de 27/07 são três revistas novas, não o mercado** | Todos os 4 (`vermelho_rosa`, `preto`, `branco_cru`, `azul`) vêm da perna BR com z de 2,50 a 4,62 e o internacional neutro/negativo, apoiados em 5 a 9 artigos. Nos veículos que já eram medidos (Elle, Steal the Look, Harper's, Fashion Bubbles) a cobertura desses 4 termos naquela semana caiu para **1 artigo — o menor de toda a série**. Os outros **14 vieram de Marie Claire, Vogue Brasil e Glamour, que entraram entre 23 e 27/07** |
| V2 | **A perna editorial não materializa zeros** | `editorial_br`: 0 linhas com valor 0, mínimo 0,25, e só **30,6%** das células (termo × semana) existem. `editorial_intl`: 48,5%. Semana sem matéria vira **ausência**, não zero. A janela de 12 linhas então só contém as semanas boas do termo: média inflada, desvio subestimado, z puxado para baixo. Medido: **z médio do BR negativo em 13 de 13 semanas** e `em alta` = **0** em toda semana desde 01/06. Com os zeros preenchidos, a semana de 27/07 sai de z médio +0,04 (6 termos acima de +1) para **+2,07 (17 termos)** |
| V3 | **A "janela móvel de 12 semanas" da §21 não é de 12 semanas** | O SQL usa `rows between 12 preceding and 1 preceding` — 12 **linhas**. Com 30% de preenchimento isso cobre **29,2 semanas em média no `editorial_br`, e até 216 semanas (4 anos) no pior caso**. E o app escreve na tela, literalmente: *"desvios da média das últimas 12 semanas deste mesmo atributo"*. Regra 3: o caminho até a origem está errado |
| V4 | **O painel de veículos dobrou e nada o congela** | 6 veículos com história (desde 2021/2024) e **8 que entraram entre 23 e 29/07 sem backfill**. O denominador BR de 4 semanas foi de ~460 para **896 (+90%)** numa semana. A **regra 5 congela o painel de marcas exatamente para proteger o z-score** — o painel de veículos não tem essa proteção |

### 🟠 Método frágil, ainda não errado na tela

| # | O que | Evidência |
|---|---|---|
| V5 | **Editorial se chama "share of voice" e é contagem absoluta** | O docstring do `coletor_editorial.py` e o nome do workflow dizem "share of voice"; a linha 271 faz `sum(janela)/4` — divide pelo número de **semanas**, não pelo total de artigos. Share de verdade cancelaria o V4 sozinho, e é o mesmo princípio que a §15 já usa no varejo ("share do sortimento") |
| V6 | **z com 12 observações usa cauda normal** | Com σ estimado de n observações, a referência é t(n−1), não normal. Na exceção editorial (n=6): `pico` em z ≥ 2,5 tem p ≈ **3,4%** sob t(5), contra 0,6% sob normal — **5,5× mais falsos positivos**. Alternativa robusta: z modificado de Iglewicz-Hoaglin (mediana + MAD) |
| V7 | **41 termos testados toda semana, sem correção de múltiplas comparações** | Mesmo com o limiar certo, testar 35–41 séries semanalmente produz achado por acaso. A §22 já diz que "quem corrige os limiares é o termômetro (§31)" — mas o termômetro depende de dado externo, e a correção FDR de Benjamini-Hochberg está disponível agora |
| V8 | **Trends parado há 3 semanas e a fonte não é reprodutível** | Última semana de busca: **13/07**. 20 de 40 termos. A literatura registra que o Google Trends devolve valores diferentes para a mesma consulta em dias diferentes (amostragem), e recomenda **média de várias extrações** — hoje extraímos uma vez |

### 🟡 Operacional

| # | O que | Evidência |
|---|---|---|
| V9 | **A coleta de 01/08 falhou no mesmo conflito de git que o commit da noite corrigiu** | `Pulling is not possible because you have unmerged files`. A correção do `commitar.sh` entrou às 19:52Z, depois da falha das 08:04Z — ou seja, **ainda não foi exercitada por nenhum run agendado** |
| V10 | **4 dias sem coleta nenhuma em julho** | Snapshots existem em 24, 29, 30, 31/07 e 01/08. Faltam 25, 26, 27, 28/07. O alerta da §20 (queda >70% vs média de 7 dias) pegaria isso e continua não implementado |
| V11 | **76,6% dos produtos foram vistos uma vez só** | 51.455 de 67.202 com um único snapshot. A `taxa_quebra` da §24 precisa de 2+ observações. É maturidade, não defeito — mas o marco de demo 1 hoje se apoia em ~23% do catálogo |

### 🔵 Rastreabilidade e limpeza

| # | O que | Evidência |
|---|---|---|
| V12 | **`artigo_termos` está vazia, e com ela morre a auditoria da regra 3** | A tela diz "baseado em: editorial BR", e **não existe caminho até QUAIS matérias sustentaram a leitura**. A tabela existe exatamente para isso e tem 0 linhas |
| V13 | **`outras_cores` tem 0 peças** | Criado em 28/07 para ser preenchido por exclusão pelo motor; o motor nunca o preenche. 38,6% das peças seguem sem nenhum termo de cor |
| V14 | **`_vocabulario_por_termo` é legível pelo `anon`** | View sem RLS e sem policy, exposta pelo PostgREST. O app nunca a lê; ela publica o vocabulário do matcher |
| V15 | **3 views passam por cima da RLS sem estar documentado** | `cobertura_por_celula`, `eventos_da_semana` e `_vocabulario_por_termo` rodam como dono (padrão do Postgres, `security_invoker` desligado). Para as duas primeiras é intencional e correto — é a mesma janela controlada da §29 — mas não está escrito em lugar nenhum |
