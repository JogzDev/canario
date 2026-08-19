# ESTADO — DataDrobe

**Última atualização:** 19/08/2026, 05:40 UTC (02:40 em São Paulo)

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
| Banco | apertado, veredito pendente | **75,3% de 500 MB** (376.474.771 bytes) |
| Rota paga de visão (Luna) | de pé, com credenciais | responde `invalid_image` |
| App na loja | **aguardando resposta da Apple** | 1.0 · `br.com.canario.ch3.app` |
| Testes | 165 Swift · 25 suítes Python | 0 telas com teste de interface |

---

## 1. Banco — o número mais apertado do projeto

**376.474.771 bytes — 75,3% de 500 MB**, medido em 19/08 às 05:40 UTC.

> **Cuidado com a unidade, porque ela já me enganou.** `pg_size_pretty` devolve
> **MiB** (1.048.576 bytes), e o limite do plano é 500 **milhões** de bytes
> decimais — é assim que `verificar_capacidade_banco.py` conta. Os dois diferem
> em 4,9%, o bastante para parecer que o banco encolheu quando não encolheu.
> Sempre compare **bytes com bytes**.

Estava em 393.216.000 bytes (78,6%) e caiu 16 MiB em 19/08 com um `REINDEX` nas
duas tabelas de estágio do motor — ver abaixo. As migrações P8 e P9, sozinhas,
**não** reduziram nada: o banco ficou parado nos 78,6% desde 18/08.

**O veredito do P8/P9 continua pendente.** A pergunta que importa — "uma coleta
ainda faz o banco crescer dezenas de MB?" — só é respondida depois de uma coleta
rodar com as migrações no lugar, e isso ainda não aconteceu.

Como conferir (dois minutos):

```bash
python3 coletor/verificar_capacidade_banco.py
```

Maiores tabelas, com heap e índice separados — a distinção importa, porque duas
vezes o problema estava no índice e não no dado:

| Tabela | Heap | Índices | Situação |
|---|---:|---:|---|
| `produtos` | 134 MB | 5 MB | alvo do P8; 40% de updates HOT |
| `produto_termos` | 22 MB | **31 MB** | índice maior que o dado; apagada e reinserida a cada motor |
| `snapshots` | 35 MB | 16 MB | delta diário, crescimento esperado |
| `artigos` | 26 MB | 18 MB | **95,2% de aproveitamento — não está inchada** |
| `series_semanais` | 27 MB | 2 MB | alvo do P9 |

### O que o REINDEX de 19/08 recuperou, e por que volta

`motor_termos_stage` e `motor_produtos_stage` são tabelas de estágio, **vazias**
entre execuções. Mesmo assim carregavam **16,7 MB de índice** — 4,5% de tudo.

A causa: o motor `truncate` no começo da execução, mas limpa com `delete` no
fim. `delete` remove as linhas e **deixa as páginas de índice alocadas**. O
`REINDEX` derrubou os quatro índices de 16,7 MB para 32 KB.

Isso **volta a crescer** a cada execução do motor. A correção permanente é
trocar o `delete` final por `truncate`, que devolve as páginas — ainda não foi
feita, e está na lista de abertos.

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

O que falta é a **rodada cega das 24 imagens** com a dica de alvo que o app
manda. O mecanismo está provado; o número honesto de acerto, não. O `1,3%`
que circulou em documentos antigos foi medido com um segmentador quebrado e
**não vale** — não use esse número.

Luna entra na versão 1.1, não na que está em revisão.

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
2. **Rodada cega da Luna** nas 24 imagens
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
