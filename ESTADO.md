# ESTADO — DataDrobe

**Última atualização:** 19/08/2026, 15:30 UTC (12:30 em São Paulo)

Este é o **único** documento que descreve o estado atual do projeto. Se outro
arquivo discordar dele, ele está velho — e provavelmente está em `historico/`.

> **Por que este arquivo existe.** Em 18/08/2026 havia 24 markdowns de estado na
> raiz, vários contradizendo uns aos outros e misturando pendência viva com item
> já resolvido. Isso não é desorganização cosmética: foi a causa direta de pelo
> menos três retrabalhos, incluindo uma reversão de bundle que passou despercebida
> porque dois documentos afirmavam coisas diferentes sobre qual app estava na loja.
> A regra passa a ser: **estado mora aqui, o resto é guia ou história datada.**

---

## Como ler em 30 segundos

| Frente | Estado | Número que importa |
|---|---|---|
| Dados e pipeline | funcionando | 15 de 15 marcas coletando |
| Banco | **veredito veio e foi ruim** | 83,2% depois de emergência; bateu **97,2%** hoje |
| Rota paga de visão (Luna) | de pé, com credenciais | responde `invalid_image` |
| App na loja | **1.0 APROVADA E PUBLICADA** | `br.com.canario.ch3.app` |
| Testes | 183 Swift · 26 suítes Python | 0 telas com teste de interface |

---

## 1. Banco — o veredito do P8/P9 chegou, e foi ruim

A coleta de 19/08 foi a primeira a rodar com P8 e P9 no lugar:

```
antes    376.474.771 bytes    75,3%
depois   486.141.075 bytes    97,2%     +104,6 MiB numa noite
```

O portão de capacidade corta em 96%: a coleta de amanhã seria **bloqueada**, e o
limite do plano (banco em somente-leitura) estava a 14 MB. **P8 e P9 não
bastaram** — eles deram folga de página para a reescrita ser HOT, mas não
atacaram a reescrita em si, e sobrou reescrita demais para a folga absorver.

> **Cuidado com a unidade.** `pg_size_pretty` devolve **MiB**; o limite do plano
> é 500 **milhões** de bytes decimais, que é como `verificar_capacidade_banco.py`
> conta. Diferem 4,9% — o bastante para parecer queda onde não houve. Compare
> **bytes com bytes**.

### O que foi feito em 19/08

**1. Emergência — 97,2% → 83,2%.** `VACUUM FULL` em `indices_semanais`,
`eventos`, `series_semanais`, `produto_termos`, `artigos` e `snapshots`.
`produtos` ficou de fora de propósito: `VACUUM FULL` constrói uma cópia antes de
trocar, e o pico passaria de 500 MB.

**2. P10 — estágio do motor devolve as páginas.** As duas tabelas de estágio
ficam vazias entre execuções e seguravam 16,7 MB de índice, porque o motor
truncava no começo e limpava com `delete` no fim. Agora truncam nas duas pontas.
Estão em 48 kB.

**3. P11 e P12 — a causa raiz, nas duas tabelas que o motor reescrevia.** `publicar_atributos` reescrevia **os 82.666 produtos
toda noite** para gravar `segmento`, sem cláusula de mudança. A linha média tem
~1.079 bytes: ~89 MB de tupla nova por execução. E `segmento` tem dois valores
(89,2% `feminino_casual_br`, 10,8% nulo) e praticamente nunca muda — 82.920
linhas eram reescritas à toa. Agora só escreve `where p.segmento is distinct
from s.segmento`.

O mesmo padrão estava em `produto_termos`: `delete` da tabela inteira seguido de
`insert` das 208.811 ligações, toda noite, para um conjunto que vem do título do
produto — e título não muda de um dia para o outro. O P12 troca isso por duas
anti-junções: apaga o que saiu, insere o que entrou, não toca em quem ficou.

O P12 traz um `analyze` explícito no estágio, e ele **não é zelo**. O estágio é
preenchido segundos antes de publicar, o autovacuum ainda não passou, e sem
estatística o planejador o trata como tabela vazia. Medido com 208.811 linhas
dos dois lados: sem estatística vira `Nested Loop` com varredura completa por
linha; com estatística, `Merge Anti Join` pelos dois índices — 2,05 s no delete
e 0,61 s no insert.

### O que observar na próxima coleta

O retorno do motor passou a trazer três números novos. Em noite normal os três
ficam perto de zero; se algum voltar para as dezenas ou centenas de milhares, é
ele que aponta o que voltou a reescrever tudo:

| Campo | O que significa |
|---|---|
| `produtos_alterados` | produtos cujo `segmento` mudou de verdade |
| `ligacoes_inseridas` | ligações novas |
| `ligacoes_removidas` | ligações que saíram |

```bash
python3 coletor/verificar_capacidade_banco.py
```

| Tabela | Heap | Índices | Situação |
|---|---:|---:|---|
| `produtos` | 190 MB | 5 MB | **85 MB úteis** — 105 MB de inchaço ainda não recuperado |
| `snapshots` | 35 MB | 16 MB | delta diário, crescimento esperado |
| `produto_termos` | 11 MB | 16 MB | 86% de aproveitamento depois do VACUUM FULL; P12 impede reinchar |
| `artigos` | 26 MB | 18 MB | 95,2% de aproveitamento — não está inchada |
| `series_semanais` | 27 MB | 2 MB | alvo do P9 |

`produtos` ainda carrega ~105 MB de inchaço. Recuperá-lo exige `VACUUM FULL`
numa janela com folga — ou seja, depois de a próxima coleta provar que o P11
segurou o crescimento.

## 2. Pipeline e coleta

Verde em 18/08. Antes disso falhou **cinco execuções seguidas** (14 a 17/08) e
ninguém soube.

Desde 19/08 existe alerta: quando o pipeline falha, abre uma **issue** no
próprio repositório — o GitHub já notifica por e-mail e push, sem serviço
externo nem secret novo. Uma issue por incidente, não por noite; as falhas
seguintes viram comentário nela; e ela **fecha sozinha** na primeira execução
verde, o que faz "issue aberta" significar "está quebrado agora". Dia bom não
notifica ninguém.

O que ele ainda não cobre está na lista de abertos abaixo.

O relatório diário fica em [`SAUDE.md`](SAUDE.md), gerado pela própria coleta.

Desde 19/08 ele responde **duas** perguntas, que antes eram uma só:

* **volume** — a coleta rodou e trouxe quantidade normal?
* **cobertura** — o catálogo veio inteiro?

A segunda existe porque em 18/08 a C&A entregou volume normal, portão verde, e
**quatro faixas de preço truncadas em 2.500** na mesma página. Teto de perda:
56.423 produtos. Hoje a cobertura é medida e reportada, mas **não bloqueia** — o
número que define "catálogo faltando demais" é decisão de método do JP, e
enquanto ele não existir bloquear seria chutar.

## 3. Rota paga de visão (Luna)

**De pé e com credenciais cadastradas**, medido em 19/08:

```bash
python3 ferramentas/testar_edge_luna.py --so-contrato   # custo zero
```

Responde `invalid_image`, que significa "subo e tenho `OPENAI_API_KEY` e
`AI_RATE_LIMIT_SALT`". Entre 14 e 18/08 ela respondeu `BOOT_ERROR` por quatro
dias sem ninguém perceber; agora a workflow `sonda-edge-luna.yml` pergunta isso
ao servidor uma vez por dia.

### O portão humano existe, está alinhado com a v7 — e FECHOU

`anexos/portao_luna_24.json` está no repositório, com o gabarito humano das 24
imagens congelado. Medido em 20/08 com a v7 e com o segmentador atual, que é o
pipeline que o app de fato usa:

| medida | v5 (13/08) | v6 (19/08) | **v7 (20/08)** | mínimo |
|---|---:|---:|---:|---:|
| categoria | 83,3% | 83,3% | **79,2%** (19/24) | 80% |
| cor primária | 91,7% | 91,7% | **79,2%** (19/24) | 80% |
| clareza do alvo | 87,5% | 83,3% | 79,2% | — |

`passed: false`. O benchmark de 300 está bloqueado, com a mensagem
`Benchmark de 300 bloqueado: categoria e cor precisam de 80%`.

**Isso não é a v7 piorando o app, e não é evidência de que ela piorou.** A v7
mexeu só no parágrafo de cor; o movimento medido foi em escolha de alvo. E a
amostra não sustenta essa distinção: **uma imagem vale 4,2 pontos**, a diferença
entre passar e não passar é uma imagem, e `12550.jpg` deu **três respostas
diferentes em quatro rodadas** de prompts quase idênticos. Os IC 95% de v6
(64,1–93,3%) e v7 (59,5–90,8%) se sobrepõem quase por inteiro.

Conta completa, imagem a imagem, em
`anexos/avaliacao_luna/relatorio-20-08-v7.md`.

O `1,3%` que circulou em documentos antigos foi de outra coisa — o benchmark de
300 com o segmentador quebrado — e **não vale**.

### O que o portão fechado bloqueia

**Não afeta o app.** O portão guarda apenas o benchmark pago de 300. A edge
function roda a v7, e as duas correções de prompt foram confirmadas no aparelho
do JP em 19/08 — quarter-zip lendo `Coats & jackets`, etiqueta de marca parando
de virar cor. Ver `anexos/avaliacao_luna/relatorio-v6-v7-em-aparelho.md`.

**Bloqueia o benchmark de 300**, que já estava bloqueado antes — antes por
divergência de hash, agora por medida.

### Meta de produto ≠ portão técnico

O portão técnico é 80%. O relatório de calibração registra uma **meta de produto
de 90%** para categoria, que nenhuma das três versões alcançou. Ligar a Luna
para o público é decisão de produto do JP.

Luna entra na versão 1.1, não na 1.0 que está publicada.

## 4. App e loja

* Bundle em revisão: **`br.com.canario.ch3.app`** — este, e não `com.canario.app`
* Versão: **1.0**, vinda de `MARKETING_VERSION` no `project.pbxproj`
* Time: `67AYPRFZH8`
* Alvo mínimo: iOS 17

A identidade é conferida no CI a cada push por
`coletor/teste_identidade_do_app.py`, que exige que gerador, `project.pbxproj`,
`Info.plist` e os guias digam a mesma coisa. Isso existe porque bundle e versão
já divergiram **três vezes** sem ninguém ver.

**Adicionar uma tela:** crie o `.swift` e rode `python3 app/gerar_projeto.py`.

O manifesto `PrivacyInfo.xcprivacy` declara `NSPrivacyCollectedDataTypePhotosorVideos`,
mas na 1.0 **nenhuma foto sai do aparelho** — o flag `REMOTE_ANALYSIS_ENABLED`
está desligado e o código é fail-closed (só liga com `YES`, `TRUE` ou `1`).
Declarar a mais é conservador e não é violação, mas cria atrito com a frase das
notas que diz que a 1.0 não chama a OpenAI. As notas passaram a explicar isso.
Conferido em 19/08 nas três superfícies que mencionam OpenAI — alerta de
consentimento, texto da tela de importação e tela de Privacidade: as três são
condicionadas ao flag e, com ele desligado, dizem que a análise é local.

Status na Apple: rejeitada uma vez por **Guideline 2.1 — Information Needed**.
As respostas aos itens 2 a 7 estão escritas em
[`RESPOSTA_REVISAO_APPLE.md`](RESPOSTA_REVISAO_APPLE.md). Faltam duas coisas, e
as duas são do JP: o vídeo gravado em aparelho físico e a posição jurídica sobre
fotos, títulos e preços de terceiros (item 7).

## 5. Testes

* **165** testes Swift de lógica pura — rodam em macOS sem simulador (`cd app && swift test`)
* **25** suítes Python — rodam a cada push
* **0** telas com teste de interface, de 13 telas

O zero de interface é conhecido e tem um motivo prático: um alvo de UI test
exige mexer no `project.pbxproj`, que é justamente o arquivo mais frágil do
projeto. A estratégia enquanto isso é tirar a decisão de dentro da `View` e
testá-la no pacote de lógica — foi assim que a divergência "Analytics/Trends" e
os defeitos do formulário passaram a ser detectáveis.

---

## O que está aberto

### Só o JP pode fazer

1. Gravar o vídeo de demonstração em iPhone físico e responder à Apple
2. Fechar a posição jurídica sobre conteúdo de terceiros (item 7 da revisão)
3. Aceite manual em aparelho: instalação limpa, câmera, fototeca, offline,
   links, modo escuro, Dynamic Type, VoiceOver
4. Decidir o número que separa "cobertura aceitável" de "dia inútil"

### Decisões de produto, sem prazo

Conta e sincronização do Closet · taxonomia `blusa_top` · fluxo semanal
unificado de Trends e Search · curadoria visual dos similares. Nenhuma é dívida
técnica; são escopos não decididos, e só entram na fila quando forem decididos.

### Técnico, em ordem de valor

1. **Alerta de "o pipeline nem começou"** — o alerta de falha existe desde
   19/08 (abre uma issue, agrupa noites seguidas, fecha sozinha no verde), mas
   ele roda no mesmo Mac que executa a coleta. Se a máquina estiver parada,
   ninguém é avisado. O certo seria um runner independente: medido em 19/08,
   `ubuntu-latest` **falha antes de começar** nesta conta, por bloqueio de
   billing. Sem gastar, a saída é algo fora do GitHub
2. **Portão das 24 é decidido por ruído** — a rodada v7 de 20/08 deu 79,2% em
   categoria e cor, contra 83,3% e 91,7% da v6, e o portão fechou. Uma imagem
   vale 4,2 pontos e pelo menos uma delas (`12550.jpg`) troca de resposta
   sozinha entre rodadas do mesmo prompt. Três rodadas repetidas da v7 custam
   US$ 0,053 e separam prompt de amostra; enquanto isso não for feito, nem o
   79,2% nem o 83,3% descrevem qualidade com confiança. Conta em
   `anexos/avaliacao_luna/relatorio-20-08-v7.md`
3. **Artefato de cor na tela Add** — o feixe do topo deixou de pintar oliva
   sobre o fundo escuro em 19/08, mas o relato original era de algo **rosa**, e
   isso eu não consegui reproduzir: só há runtime iOS 26.2 nesta máquina, e o
   iPhone 15 com 18.7 usa o caminho de compatibilidade. Pode ter sido o mesmo
   defeito visto noutro renderizador, pode ser outro. Precisa de uma foto
4. **Loading de ~30 s ao importar peça no iPhone 15** — reduzido o que era
   reproduzível no Mac (242 → 241 ms), mas **a causa dos 30 s continua sem
   prova**. Precisa de medição no aparelho, não de mais otimização no escuro
6. **Motor limpa o estágio com `delete`, não `truncate`** — deixa ~16 MB de
   página de índice alocada entre execuções. Recuperado à mão em 19/08; volta a
   crescer até a limpeza virar `truncate`
7. Primeiro teste de interface de verdade
8. `String Catalog` antes de abrir PT-BR
9. Apagar as branches remotas já mescladas

---

## Onde procurar cada coisa

**Vivos — consulte estes**

| Arquivo | Para quê |
|---|---|
| [`CANARIO.md`](CANARIO.md) | as regras invioláveis e a especificação. É a constituição |
| [`SETUP.md`](SETUP.md) | abrir o projeto numa máquina nova |
| [`TESTFLIGHT.md`](TESTFLIGHT.md) | subir build para o TestFlight |
| [`RELEASE_DATADROBE.md`](RELEASE_DATADROBE.md) | assinar e exportar para a loja |
| [`DEPLOY_ANALISE_VISUAL.md`](DEPLOY_ANALISE_VISUAL.md) | publicar a Edge Function |
| [`RUNNER.md`](RUNNER.md) | os runners self-hosted |
| [`FICHA_APP_STORE_1.0.md`](FICHA_APP_STORE_1.0.md) | textos publicados na loja |
| [`RESPOSTA_REVISAO_APPLE.md`](RESPOSTA_REVISAO_APPLE.md) | a revisão em aberto |

**Gerados por código — não edite à mão**

`SAUDE.md` · `SONDA_ACTIONS.md` · `PENTE_FINO_DATACENTER.md` ·
`VERIFICACAO_TRENDS.md` · `AUDITORIA_LINKS_APP.md`

**História** — `historico/`. Fotografias datadas de um estado que já passou.
Úteis para entender *por que* algo é como é; inúteis para saber como está hoje.

---

## A regra que evita tudo isso voltar

Nada entra sem evidência. Se não dá para mostrar o comando que prova, não está
feito. Foi assim que o "1,3%", a função quebrada e a reversão do bundle passaram.
