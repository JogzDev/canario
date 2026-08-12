# Pendências

**O que este arquivo é:** o placar entre o que foi **decidido e registrado** e o
que foi **implementado**. Existe porque o pente fino que fiz em 30/07 checou
arquivos que faltavam, e não decisões registradas e não cumpridas — que é a
dívida que mais apareceu, e sempre no meio de outra conversa.

**Regra:** nenhuma etapa nova começa com item vermelho relevante para ela. Toda
decisão nova nasce com uma linha aqui. Atualizado a cada commit que mexe no
estado de algum item.

Última varredura: **12/08/2026** (atualizado ao fim de cada etapa).

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

## Decisões das instruções do JP (A1–A18)

| id | O que exige | Estado |
|---|---|---|
| A1 | `flag_tipo` presumido por categoria e palavra-chave | 🔴 Não feito — schema aceita os valores, nada preenche |
| A2 | Coletar amplo, classificar depois | ✅ Feito |
| A3 | Forma descritiva do marco de demo 2 | 🔴 Não feito |
| A6 | Cards de similar com identidade visual própria | 🟡 Funcional feito, **sem foto de terceiro**: bloco cuja altura mostra o estado da grade. A identidade visual é da Bianca e troca em `MarcaVisual` |
| A7 | Visão e referências internas fora da v1 | ✅ Feito (entrada por arquivo voltou em 30/07) |
| §28 | Entrada por arquivo (print, foto, PDF) com OCR, sem câmera | ✅ Feito — `LeitorDeArquivo.swift` |
| §28 | Formulário de confirmação de atributos (humano no circuito) | ✅ Feito — `ImportarPeca.swift` |
| §28 | Imagem original processada e descartada | ✅ Feito; A18 autoriza somente miniatura local sem metadados, após salvar no Closet |
| A8 | Vocabulário interno nunca vira produto | ✅ Feito — `teste_vocabulario.py` |
| A9 | Roadmap v1.1 | ⚪ Registrado, sem código |
| A10 | Abas orientadas ao objeto; Comparar dobra para dentro do Armário | ✅ Feito — Add · Closet · Analytics; Compare abre de dentro do Closet |
| A11 | Nome da aba volta a ser Armário | ✅ Feito |
| A12 | Câmera e fototeca; original não persiste | ✅ Feito — três entradas terminam no mesmo `LeitorDeArquivo`; A18 trata a miniatura local separadamente |
| A13 | Foto do similar por hotlink, com bloco visual como fallback | ✅ Feito |
| A14 | Gráfico do histórico dos atributos da peça | ✅ Feito — `serie_do_cluster()` e cobertura por ponto |
| A15 | OpenAI no runtime: visão + redator com coleira | 🟡 Secret e contrato validados; smoke Luna: 24/24 respostas válidas. Os 19/24 eram concordância com rótulo fraco, não acurácia; revisão cega e prompt estrutural A17 prontos, nova rodada e integração pendentes |
| A16 | Interface da v1 em inglês | 🔴 Decidido; tradução e nome definitivo pendentes |
| A17 | Calibrar Luna nas mesmas 24; só então abrir holdout de 300 | 🟡 Gabarito 24/24 adjudicado com comentários do JP; prompt v3 fechado e testado offline. Falta repetir as 24; só ≥20/24 em categoria e cor abre o holdout |
| A18 | Home do Figma em Liquid Glass, paleta aprovada, menu e duas peças recentes | ✅ Feito e verificado no iPhone Simulator — miniaturas reais, locais, 720 px, sem EXIF e excluídas de backup |

---

## Requisitos do documento ainda em aberto

| Onde | O que exige | Estado |
|---|---|---|
| §20 | Alerta quando uma fonte cai mais de 70% vs. média de 7 dias | ✅ Feito — as 3 pernas gravam `saude`; queda para menos de 30% da média dos 7 dias anteriores bloqueia e tem regressão em `teste_saude.py` |
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
| V10 | **4 dias sem coleta nenhuma em julho** | Snapshots existem em 24, 29, 30, 31/07 e 01/08. Faltam 25, 26, 27, 28/07. O alerta da §20 agora pega queda >70%; a lacuna histórica não é reconstruível |
| V11 | **76,6% dos produtos foram vistos uma vez só** | 51.455 de 67.202 com um único snapshot. A `taxa_quebra` da §24 precisa de 2+ observações. É maturidade, não defeito — mas o marco de demo 1 hoje se apoia em ~23% do catálogo |

### 🔵 Rastreabilidade e limpeza

| # | O que | Evidência |
|---|---|---|
| V12 | **`artigo_termos` está vazia, e com ela morre a auditoria da regra 3** | A tela diz "baseado em: editorial BR", e **não existe caminho até QUAIS matérias sustentaram a leitura**. A tabela existe exatamente para isso e tem 0 linhas |
| V13 | **`outras_cores` tem 0 peças** | Criado em 28/07 para ser preenchido por exclusão pelo motor; o motor nunca o preenche. 38,6% das peças seguem sem nenhum termo de cor |
| V14 | **`_vocabulario_por_termo` é legível pelo `anon`** | View sem RLS e sem policy, exposta pelo PostgREST. O app nunca a lê; ela publica o vocabulário do matcher |
| V15 | **3 views passam por cima da RLS sem estar documentado** | `cobertura_por_celula`, `eventos_da_semana` e `_vocabulario_por_termo` rodam como dono (padrão do Postgres, `security_invoker` desligado). Para as duas primeiras é intencional e correto — é a mesma janela controlada da §29 — mas não está escrito em lugar nenhum |

### O que a madrugada de 02/08 fechou dessa lista

| # | Estado |
|---|---|
| V1 | 🟡 **Os 4 picos falsos saíram da tela**, mas por um portão de cobertura, não porque o método esteja certo. Ver V6 |
| V2 | ✅ Zeros materializados. `z` do editorial BR passou de negativo em 13/13 semanas para média −0,03 |
| V3 | ✅ Janela virou calendário (`range interval '84 days'`). A frase "últimas 12 semanas" na tela voltou a ser verdade |
| V5 | ✅ Share of voice de verdade, e no motor (§33), porque o coletor só vê o feed recente |
| **V16** | 🔴 **NOVO, achado ao consertar:** `computar_indice()` fazia upsert e **nunca apagava**. Leitura que perdia a base ficava na tela para sempre. Corrigido — mas vale perguntar onde mais o projeto tem upsert sem delete |
| **V17** | 🔴 **NOVO, e é o que sobra de maior:** z-score é o modelo errado para contagem esparsa. Com os zeros, `azul` deu z = 10,27 com 5 matérias. Resíduo de Poisson **piorou** (desvio observado 1,74 = variância 3× a de Poisson): a contagem editorial é superdispersa porque matéria de moda vem em rajada. Modelo correto: **binomial negativa**. Decisão de método, do JP |
| V4, V6–V15 | 🔴 Seguem abertos |

**Decisão pendente e ela é de produto:** o piso de 10 matérias esvazia a tela — na semana de 27/07 sobram 6 termos com leitura e nenhum estado. Alternativas medidas: piso 5 → 2.823 leituras, maior |z| 10,3 · piso 10 → 1.410 leituras, maior 6,8 · piso 20 → 499 leituras, maior 6,8. Nenhum valor conserta o modelo; o piso só evita publicar o pior.

---

## Noite de 05/08 — perna de busca destravada, e o que ficou mapeado

### ✅ Resolvido

| O que | Evidência |
|---|---|
| **Fila de busca por defasagem** | O mesmo defeito congelou a série **duas vezes** (19 e 16 dias). Causa real: **4 termos sem série prendiam 36** — em modo backfill o coletor filtrava para esses 4, sobrava 1 grupo, esse grupo apanhava de 429, e o resto ficava parado. Não existe mais modo: existe fila por defasagem. A pergunta deixou de ser "tem série?" e virou "há quanto tempo?". `teste_fila_de_busca.py` tranca, com os nomes reais dos 4 termos |
| **Os 4 termos travados coletaram** | `reta_wide`, `romantico`, `saia`, `short` — os 40 termos agora têm série |
| **Piso editorial: fica em 10** | Medido em 12 semanas: piso 0, 5 e 10 dão **exatamente as mesmas 109 leituras e 79 pares com 2 fontes**. O piso só corta leitura construída sobre zero matéria. Não é ele que esvazia a tela |
| **Interface parou de falar como documentação** | `§8`, `§22`, `z-score`, `perna`, `cluster` saíram das strings de tela |

### 🔴 Mapeado e NÃO resolvido — o de maior valor para amanhã

| # | O que | Evidência |
|---|---|---|
| N1 | **FFW e Business of Fashion dão 403 no datacenter e funcionam residencial** | `saude.alertas` registra `"feed http 403"` para os dois **todo dia**. Testado local: FFW 3 itens, BoF 100 itens, sem erro. É a mesma família do Shopify, que por isso já roda em `[self-hosted, macOS]`. **O desenho certo é um job separado só para os bloqueados** — mover o editorial inteiro troca 2 veículos por 6 se o Mac dormir |
| N2 | **Vogue Business já está sendo fundida na Vogue** | As duas linhas do `veiculos.csv` apontam para `https://www.vogue.com/feed/rss`. Com `on_conflict=url` em `artigos`, o último a escrever vence e um dos dois some. Não é risco futuro: está acontecendo |
| N3 | **FashionNetwork BR e Lyst: abandonar** | FashionNetwork = 403 anti-bot em todos os caminhos, falha definitiva do site. Lyst = dado agregado, nunca foi feed editorial (entra pela §12) |
| N4 | **A busca pode ter defasagem estrutural** | Mesmo com a fila destravada e 2.871 pontos gravados por execução, `ultima_semana` continua **20/07** para os 40 termos. Se a próxima execução não mover isso, o atraso é do Google e o app precisa **declarar** o lag em vez de esperar por ele |

### Da lista do JP, ainda não tocado
reestruturação das abas · câmera e fototeca

> **Sobre o 500 do Explorar:** eu o atribuí à lista do JP, ele disse que nunca viu, e eu concluí que tinha inventado — errado nas duas vezes. Quem viu foi o **companheiro de time**, na revisão de 03/08: *"Primeiro recebi 'Não consegui consultar. O servidor respondeu 500'. Depois que cliquei em tentar novamente foi."* O erro é real e transitório. Consertado em 06/08 com uma segunda tentativa automática para 5xx em `Supabase.buscar`.

---

## Sessão seguinte (05–06/08) — a defasagem era rótulo, não fonte

### ✅ Resolvido

| O que | Evidência |
|---|---|
| **N4 estava errado: a defasagem era nossa** | O Trends marca a semana pelo **domingo**. O coletor fazia `quando - timedelta(days=quando.weekday())`; `weekday()` de domingo é 6, então a linha jogava o ponto para a segunda **anterior**. A semana 26/07–01/08 virava "semana de 20/07". Os 16 dias que reportei eram 6 de rótulo + ~4 de atraso real da fonte. Sonda em 5 janelas no mesmo minuto: `today 5-y` e `12-m` param em 26/07; `3-m` e `1-m` chegam em **05/08** |
| **§22 comparava períodos diferentes** | O editorial usa `date_trunc('week')` (segunda ISO de verdade). O mesmo rótulo "20/07" significava 20–26/07 numa perna e 26/07–01/08 na outra: **1 dia em comum**. Não levantava exceção, não aparecia em log — o número existia e media outro período. `teste_semana_da_busca.py` tranca comparando com a função real do coletor editorial em 400 dias seguidos |
| **Perna de busca montada dia a dia** | Janela de 240 dias ainda vem em **diário** (241 pontos, 34 semanas ISO completas, contra as 12 que a §21 usa). Fronteira medida: 269d ainda diário, 280d já semanal. Guarda nova estoura se o Trends mudar a granularidade, em vez de devolver série vazia |
| **10.460 linhas de busca realinhadas (+7d)** | Migração `20260805160000`. Busca e `editorial_br` agora começam ambas em **26/07/2021** — o deslocamento estava visível ali desde o primeiro dia |
| **Corte de "em dia" deixou de ser chute** | Era `hoje − 2 semanas`, número escolhido à mão para compensar o atraso. Virou a última semana ISO fechada: a fonte, e não o relógio, diz o teto |
| **2 críticos do Supabase** | `cobertura_por_celula` e `eventos_da_semana` com `security_invoker=false`. Ligar o invoker sem mais nada **esvaziaria o Explorar e travaria o portão da §8 em "sem dados" para sempre**, em silêncio. Feito com permissão **coluna a coluna**: conferido como `anon` antes e depois — 3431/120/113/11, idêntico; `marcas.detalhe_teste` agora dá `permission denied` |
| **N1: FFW e BoF não é rate-limit** | 403 do datacenter, **200 residencial** (64 KB e 116 KB), com o `CanarioBot/1.0` e o mesmo código de fetch. Regra 7 intacta. Dois endereços estavam velhos: FFW saiu da UOL (`ffw.com.br`), BoF mudou para `/arc/outboundfeeds/rss/` |
| **N2: Vogue Business fora** | Pior que fusão: **nunca trouxe artigo nenhum**. A descoberta seguiu o link-alternate e caiu no feed da *Vogue*; o `on_conflict=url` deu tudo para a Vogue. Era fonte fantasma contando como veículo. `voguebusiness.com/feed/rss` dá 404. São **16 veículos ativos**, não 17 |

### 🔴 Aberto — o de maior valor

| # | O que | Evidência |
|---|---|---|
| ~~M1~~ | ~~43% dos "em alta" se apoiam num par que não co-move~~ — **decidido em 06/08: só perna brasileira confirma** | Medido: `busca × editorial_br` dá r=**0,235** e **67,7%** de mesmo sinal quando ambos \|z\|≥1 (n=167) — sinal real. `busca × editorial_intl` dá r=**−0,070**, dentro de 1 erro-padrão de zero (n=179). E **49 dos 114 "em alta"** vêm do par `{busca, editorial_intl}`, contra 47 de `{busca, editorial_br}`. A ambiguidade 2 já suspeitava disso em palavras; agora tem número. **Decisão de método do JP**: imprensa internacional pode ser a perna que confirma um índice de mid-market brasileiro? |
| M2 | **`computar_indice()` não filtra `varejo`, o meta diz que filtra** | O CTE `ativas` pega toda fonte com z não nulo. Hoje é inofensivo porque `computar_z()` não calcula z para varejo — mas o índice depende de um comportamento de outra função, não de uma regra própria. B1 diz que varejo não entra |
| M3 | **Editorial de 4 semanas comparado com busca de semana crua** | A §18 alisa o editorial em janela móvel de 4 semanas (volume baixo, semana crua é ruído); a busca é semana fechada. A varredura de defasagem tem pico em −2 semanas, que é ~o centro de massa da janela de 4 — ou seja, é o alisamento aparecendo, não antecipação. A §22 compara grandezas de resolução temporal diferente |
| M4 | **Coleta editorial não pode ser dividida entre runners** | O coletor calcula a série a partir dos **feeds que leu naquela execução**, não de `artigos`. Duas execuções parciais se sobrescrevem. O workflow já aceita `RUNNER_COLETA`, mas ligá-lo move a coleta inteira para o Mac — Mac dormindo = vermelho. O conserto certo é `computar_serie_editorial()` no banco, como o próprio comentário do coletor já aponta |
| ~~M5~~ | ~~Erro 500 do Explorar~~ | **Real, e consertado em 06/08.** Quem viu foi o companheiro de time em 03/08 — eu atribuí ao JP, ele disse que não viu, e eu concluí que tinha inventado. Errado nas duas vezes. É 5xx transitório (o próprio relatório diz "cliquei em tentar novamente e foi"): a tela abre 4 pedidos simultâneos e o pipeline noturno segura conexões por 1h17. `Supabase.buscar` passa a repetir uma vez em 5xx, só no que é transitório — 4xx não repete |

---

## 06/08 — a janela diária foi um erro meu, revertida

### O que eu quebrei e consertei no mesmo dia

| O que | Estado |
|---|---|
| **Troquei `today 5-y` por janela diária de 240 dias** por ter concluído um atraso que não existia. Contando semanas ISO fechadas, as duas janelas chegam na **mesma semana** (27/07). O atraso aparente era o rótulo errado, não a fonte | **Revertido.** O conserto do rótulo (domingo → segunda ISO seguinte) fica |
| **A diária apaga termo de volume baixo.** Semanas em zero, mesmo termo: `viscose_fluido` 0,9% → 73,5%; `animal_print` 10,6% → 88,2%. Eu tinha escrito que o semanal "mascarava série vazia" — era o contrário | Medido e registrado no cabeçalho do coletor |
| **Piso `MEDIA_MINIMA` tirou a perna de busca de 3 termos** — calibrado na escala semanal, aplicado a outra escala | Resolvido pela reversão da janela |
| **Portão de saúde barrou o pipeline**: "busca caiu 87%". `itens` conta PONTO, e ponto é unidade de janela, não de cobertura | Passa a usar `gravados` para a busca. `teste_saude.py` tranca |
| **A limpeza de escala que pus no coletor apagou histórico.** Com a reversão, 13 termos ficaram sem série de busca | Recuperável: `today 5-y` devolve 5 anos por consulta e a fila põe termo sem série na frente. Em recoleta |

### ✅ Decidido pelo JP e implementado

| O que | Como ficou |
|---|---|
| **§22: quem confirma direção é sinal brasileiro** | O app posiciona peça no mercado nacional. `busca` e `editorial_br` confirmam; `editorial_intl` e `varejo` viram contexto — gravados e visíveis em `meta`, sem mover o índice nem acender estado. Medido: busca × editorial_br r=0,235 e 67,7% de mesmo sinal; busca × editorial_intl r=−0,070, dentro de um erro-padrão de zero. Resultado: 114 "em alta" → **78**, todos com duas fontes daqui |
| **Portal que nunca contribuiu sai** | FashionNetwork Brasil removido do CSV (403 definitivo). Vogue Business já tinha saído. Lyst fica: é `dado_agregado` pela §12, não feed que falhou |
| **Nada roda do Mac pessoal (M5)** | Sondas do Trends e testes de FFW/BoF de 05/08 rodaram de lá. Não se repete |

---

## 10/08 — primeiro smoke test do Luna (A15)

Execução: [GitHub Actions #31452732941](https://github.com/JogzDev/canario/actions/runs/31452732941).
Foram três imagens de cada uma das oito categorias, amostradas com semente fixa
do cache do i7. O modelo não recebeu título, nome de arquivo nem rótulo.

| medida | resultado |
|---|---:|
| Respostas que completaram e obedeceram ao JSON Schema | **24/24** |
| Concordância de categoria com o rótulo fraco do catálogo | **19/24 (79,2%)** |
| Custo exibido na execução (fórmula de preço errada) | US$ 0,010906 |
| Custo corrigido com os mesmos tokens e preço oficial de 11/08 | **US$ 0,054530** |
| Duração total | **82,8s** |
| Latência por imagem | **3,3s mediana; 4,4s p95** |

Por categoria: vestido, blusa/top, calça, casaco/jaqueta e macacão 3/3; saia
2/3; camisa 1/3; short 1/3. Das cinco divergências, quatro viraram
`blusa_top` e uma virou `saia`.

**Isto valida a rota técnica, não abre o portão de 80%.** As pastas foram
rotuladas pelo matcher dos títulos de e-commerce. O próximo passo é revisar as
cinco divergências nas imagens e montar verdade humana de categoria **e cor**;
só depois vale gastar o benchmark de 300. A execução inicialmente exibiu
US$ 0,010906, mas a fórmula usava preço 5× menor que o oficial atual; com os
mesmos tokens, o valor correto é US$ 0,054530.

## 11/08 — auditoria das 24 e protocolo de calibração (A17)

As 24 imagens e as categorias impressas no log foram recuperadas em um artefato
privado sem nova inferência. Auditoria visual das cinco divergências:

| amostra | catálogo | Luna | leitura pelos pixels |
|---|---|---|---|
| S10 | saia | blusa/top | look com top e saia igualmente plausíveis; alvo de venda não é inferível |
| S14 | camisa | blusa/top | conjunto de camisa e short; alvo ambíguo, mas a construção de camisa está visível |
| S17 | short | saia | exterior visível parece saia; entrepernas/duas aberturas não aparecem |
| S20 | camisa | blusa/top | camisa isolada com colarinho e abertura frontal: erro real de fronteira |
| S21 | short | blusa/top | look com top e short; pixels não dizem qual item está à venda |

Logo, **19/24 não mede a acurácia do modelo**: mistura erro do Luna, rótulo fraco
do catálogo e imagens cujo alvo não pode ser deduzido. Separar `blusa_top` em
duas classes não resolve nenhuma das cinco e cria uma fronteira nova sem série
de mercado própria.

O prompt `alvo-estrutura-v2` primeiro decide se existe um alvo visual, depois
escolhe uma estrutura observável. A categoria é derivada por código: painel
inferior contínuo → saia; duas pernas curtas → short; construção de camisaria →
camisa; superior residual → blusa/top. Alvo ambíguo obriga `not_visible`. Duas
revisões humanas cegas precisam ser comparadas e as divergências adjudicadas.

As mesmas 24 viram **calibração**, não benchmark. Nessa amostra, o primeiro
valor inteiro acima de 80% é 20/24 = 83,3%; categoria e cor primária precisam
atingi-lo separadamente. Só então o avaliador aceita 300 imagens. As 300 formam
um holdout determinístico que exclui todas as 24, impedindo vazamento. As
respostas completas das próximas rodadas ficam em artefato privado por três
dias, para não ser necessário pagar outra inferência só para auditá-las.

Os dois gabaritos chegaram completos em 11/08. Acordo entre Fadul e Bianca:
19/24 em alvo, categoria e estrutura; 17/24 em cor primária; 14/24 em cores
secundárias. O portão depende de dez amostras (`S02`, `S05`, `S07`, `S10`,
`S14`, `S16`, `S19`, `S20`, `S21`, `S23`); divergências somente em cores
secundárias ficam fora. Foi gerado um pacote de adjudicação cego apenas com
essas dez, sem rótulo de catálogo ou do Luna. Nenhuma chamada à OpenAI foi feita.

## 11/08 — vermelho do pipeline e paginação VTEX

O pipeline #10 bloqueou corretamente: C&A caiu de média 16.217 para 4.011
itens visitados (75%) e Farm de 2.581 para 766 (70%). O limiar da §20 já
existia; o placar que dizia o contrário estava desatualizado.

A causa estava na paginação VTEX por preço: muitos produtos empatados podiam
mudar de posição entre páginas, repetir ids e encerrar com cobertura parcial sem
erro HTTP. A ordem agora é estável por nome, ids são deduplicados e cobertura
abaixo de 98% abre uma passada complementar na ordem inversa. O portão de 70%
foi preservado. Regressão local: 150/150 ids únicos mesmo com empate e reparo
ASC/DESC. Na prova ao vivo, Farm voltou a 2.858 itens visitados.

Uma execução manual logo depois das 21h revelou ainda que `date.today()` usava
UTC no runner e podia gravar o dia seguinte no Brasil. Coleta e saúde agora
compartilham uma única data operacional em `America/Sao_Paulo`; coleta manual
de uma marca também não roda mais o pente fino completo. Testes do commit e duas
execuções focadas da Farm ficaram verdes. A prova da C&A subiu de 4.011 para
10.661 de 12.011 itens pagináveis e também ficou verde. Por fim, o portão
consolidado respondeu "nenhuma fonte obrigatória bloqueada" e o motor publicou
atomicamente 75.004 produtos, 186.960 ligações e todos os cálculos. Recuperação
de ponta a ponta concluída.

## 07/08 — visão da peça: o que foi medido e por que eu parei

### O que existe de número

| tentativa | imagens/categoria | validação |
|---|---|---|
| Centroide da Vision | ~320 | 49,6% |
| **Create ML, 4 aumentos** | **~320** | **64,1%** |
| Create ML com 4.790 imagens | ~600 | *nunca terminou* |

Piso da §28: **80%**. Acaso com 8 categorias: ~12,5%.

### O que travou

Seis execuções no i7, **um** número aproveitável — o da primeira. As outras cinco:

| causa | de quem |
|---|---|
| Filtrei por dimensão `peca`, que não existe (é `categoria`). Deu `0/0` e quase virou "a visão não acerta" | **minha** |
| Download descartava o motivo do erro; 62% de falha sem diagnóstico | **minha** |
| Imagens baixadas iam para `NSTemporaryDirectory` e o runner apagava. ~8.100 imagens jogadas fora | **minha** |
| Código de balanceamento da curva travou 90 min sem imprimir um patamar | **minha** |
| Create ML com 4.790 imagens não termina em 90 min, contra 6 min com 2.574 | limite da máquina, não medido antes |

Diagnóstico que só apareceu ao contar o motivo da falha: **5.411 de 5.413 recusas eram HTTP 429**. Eu contava e seguia batendo na mesma cadência — descumprindo a regra 7, não só perdendo eficiência. Corrigido com recuo exponencial por domínio.

### Recomendação: parar por agora

Três medições dizem a mesma coisa, e continuar é apostar que a quarta contraria as três. **O app não depende disso**: a entrada por arquivo já lê texto (OCR) e cor (pixel), que é o escopo aprovado na §28 desde 30/07. Sugestão de categoria a 64% erraria uma peça a cada três — custa mais confiança do que economiza toque.

Caminho medido para retomar depois do Demo Day: **recortar a peça do fundo antes de treinar** (`VNGenerateForegroundInstanceMaskRequest`). Foto de e-commerce carrega modelo, cenário e props, e o classificador está aprendendo cenário junto com roupa.

### Fica pronto para quem retomar

- **4.790 imagens em cache** no i7 (`~/canario-imagens-treino`), zero falha, sem precisar de rede
- Recuo no 429 implementado
- Teto de 90 min no job, para nenhuma tentativa custar uma tarde
- Portão da §28 no código: segurou nas seis execuções, nada vazou para a tela
