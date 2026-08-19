# ESTADO — DataDrobe

**Última atualização:** 19/08/2026, 04:20 UTC (01:20 em São Paulo)

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
| Banco | apertado, veredito pendente | **375 MB — 75,0% de 500 MB** |
| Rota paga de visão (Luna) | de pé, com credenciais | responde `invalid_image` |
| App na loja | **aguardando resposta da Apple** | 1.0 · `br.com.canario.ch3.app` |
| Testes | 165 Swift · 25 suítes Python | 0 telas com teste de interface |

---

## 1. Banco — o número mais apertado do projeto

**375 MB de 500 MB (75,0%)**, medido em 19/08 às 03:58 UTC.

Caiu de 393,4 MB (78,7%) depois das migrações P8 e P9. **Isso ainda não é o
veredito.** A queda é autovacuum recuperando espaço; a pergunta que importa —
"uma coleta ainda faz o banco crescer dezenas de MB?" — só é respondida depois
de uma coleta rodar com as migrações no lugar, e isso não aconteceu até agora.

Como conferir (dois minutos):

```bash
python3 coletor/verificar_capacidade_banco.py
```

Maiores tabelas e o que se sabe sobre cada uma:

| Tabela | Tamanho | Situação |
|---|---:|---|
| `produtos` | 142 MB | alvo do P8; 40% de updates HOT |
| `produto_termos` | 53 MB | só inserção, sem reescrita |
| `snapshots` | 51 MB | delta diário, crescimento esperado |
| `artigos` | 44 MB | **próximo suspeito**: 3,3% de HOT, sem vacuum desde 01/08 |
| `series_semanais` | 29 MB | alvo do P9 |

Se depois da próxima coleta o banco subir muito, `artigos` é onde olhar: ela é
re-upsertada por `url` a cada coleta editorial, o mesmo padrão que o P8 corrigiu
em `produtos`.

## 2. Pipeline e coleta

Verde em 18/08. Antes disso falhou **cinco execuções seguidas** (14 a 17/08) e
ninguém soube — não havia canal de alerta, e ainda não há um que chegue a uma
pessoa. Esta é a maior lacuna operacional aberta.

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

1. **Canal de alerta que chegue a alguém** — cinco execuções vermelhas e quatro
   dias de função quebrada passaram em silêncio
2. **Rodada cega da Luna** nas 24 imagens
3. **Modo escuro ignorado** nas telas Add e Closet (visto em vídeo, 18/08)
4. **Artefato rosa** na tela Add (visto em vídeo, 18/08)
5. **Loading de ~30 s ao importar peça no iPhone 15** — reduzido o que era
   reproduzível no Mac (242 → 241 ms), mas **a causa dos 30 s continua sem
   prova**. Precisa de medição no aparelho, não de mais otimização no escuro
6. Primeiro teste de interface de verdade
7. `String Catalog` antes de abrir PT-BR
8. Apagar as branches remotas já mescladas

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
