# Ordem proposta para a 1.3 — uma alternativa concreta à blueprint

**05/09/2026.** Este documento **não revoga** a `BLUEPRINT_DATADROBE_1_3.md`.
Ele propõe uma ordem diferente para os mesmos pacotes e diz o que custa trocar.
A decisão é do JP; enquanto ela não vier, a blueprint continua valendo.

A crítica sozinha não vale nada. Ou existe uma ordem alternativa executável,
com primeiro passo definido e portão de saída, ou a discordância era só opinião.

---

## 1. O desacordo, em uma frase

A blueprint retira riscos na ordem **arquitetura → fontes → utilidade**. Eu
retiraria na ordem **fontes → utilidade → arquitetura**, porque os dois
primeiros custam dias para responder e podem invalidar meses do terceiro — e o
terceiro custa meses e não invalida nenhum dos dois.

## 2. Os riscos, ordenados pelo que custa responder cada um

| # | Risco | Se for verdade, o que morre | Custo de responder |
|---|---|---|---|
| **R1** | Não existe fonte externa legalmente utilizável | O "radar" vira "laboratório de etiqueta interna". P3, P4, P5 e P6 mudam de forma | **~2 dias de leitura e classificação.** Nenhuma linha de código |
| **R2** | O time comercial da Azzas não usaria um radar quinzenal | O produto inteiro | **~1 semana**, com artefatos que já existem |
| **R3** | O modelo de evidências está errado de um jeito que exige migração | Retrabalho caro, mas o projeto sobrevive | Meses (é o P2/P3) |
| **R4** | A superfície pela qual o produto é julgado está errada | Credibilidade a cada apresentação | Dias — e **já aconteceu** em 05/09 |

A blueprint agenda R3 primeiro (P1/P2), R1 "em paralelo" (F1, que não começou) e
R2 por último (P6, sétimo de oito). R4 ela declara congelado.

**O que isso significa na prática:** hoje, 05/09, com ~11 mil linhas escritas, o
projeto ainda não sabe a resposta de R1 nem de R2 — as duas mais baratas e as
duas que mais mudam o desenho.

## 3. A ordem que eu proponho

### S0 — feito em 05/09

Os quatro pedidos da diretoria e o P1 executado. R4 endereçado; R3 com a
fundação provada em laboratório. **Não repetir: já está fechado.**

### S1 — F1 em papel. Dois dias. Zero código.

O inventário de acesso que a blueprint descreve (seção 10) e ninguém começou:
matriz de **desejo × método permitido × direitos de IA × exibição × retenção ×
cobertura × custo × responsável × próximo ato**.

Não é pesquisa aberta. É ler os termos das fontes que já estão em
`anexos/fontes_radar.csv` e responder, por escrito, uma pergunta por fonte:
*existe um método autorizado, hoje, sem contrato novo?*

**Portão de saída — um dos dois, e é preciso escrever qual:**

- **pelo menos uma** fonte externa com método autorizado documentado; ou
- um relatório dizendo que nenhuma existe, com o que faltaria em cada uma.

**Por que isto primeiro:** as lacunas estruturais 2, 3 e 4 da própria blueprint
(entidade canônica separada da observação, identidade lógica independente da
tentativa, vínculo por afirmação) são desenhadas *para* um corpus. Desenhá-las
sem saber se o corpus terá metadados de RSS, artigos licenciados ou nada é
projetar contra uma incógnita. Dois dias compram essa informação.

**Se o resultado for "nenhuma":** não é fracasso, é economia. O produto passa a
se chamar o que já é — *Etiqueta e varejo interno* — e P2/P3 encolhem para o que
um sensor interno sustenta. A blueprint já autoriza esse nome; ela só não
programou o momento de descobrir.

### S2 — a edição concierge. Uma semana. Quase zero código.

**Escrever UMA edição à mão**, com o material que já existe: o
`materializar_etiqueta_radar.py` produz o pacote factual da Etiqueta, e a
revisão cega dupla já tem HTML e consolidador. Ninguém precisa de pipeline para
escrever uma página.

Mostrar ao Pedro, à Lorena e ao Victor. Não perguntar se gostaram.

**Medir três coisas observáveis:**

1. alguém fez uma **pergunta de acompanhamento** sobre um número?
2. alguém **abriu a fonte** para conferir?
3. alguém **pediu a próxima edição** sem ser convidado?

**Portão de saída:** pelo menos um dos três, com pelo menos uma pessoa. Se
nenhum acontecer, o problema não é o pipeline — e construí-lo não conserta.

**Por que isto antes de P2:** a blueprint reconhece que *"conversão, disposição
de pagar e diferenciação exigem validação própria; não são consequência
automática de um pipeline verde"*. Está certo. Mas então a validação precisa
acontecer antes do pipeline, não depois — senão a frase descreve um risco que o
plano assume inteiro.

### S3 — P2 e P3, com o escopo cortado pelo que S1 e S2 responderam

Aqui a blueprint volta a valer quase inteira. A diferença é que as decisões
estruturais passam a ser tomadas **sabendo** o formato do corpus e o que o
leitor pediu. Concretamente:

- se S1 devolveu "só interno", a separação entidade/observação encolhe: não há
  reobservação semanal de URL externa para modelar;
- se S2 mostrou que o leitor abre a fonte, a rastreabilidade sobe de prioridade;
  se mostrou que ninguém abre, ela continua obrigatória por regra, mas para de
  disputar espaço na tela.

### S4 — o app deixa de ser pacote e vira trilha contínua

A blueprint congela a 1.2 e trata a experiência como P5, dependente de P3/P4. O
05/09 mostrou o custo disso: **os quatro pedidos da diretoria eram todos de
interface, e nenhum deles existia no plano.** O produto é julgado pela
superfície a cada apresentação, e a superfície estava fora do roteiro.

Proposta: a interface deixa de ser um pacote com dependência e passa a ser uma
trilha que recebe correção sempre que houver evidência de uso. As telas do
radar continuam dependendo de P3 — isso não muda. O que muda é que consertar o
que já está na mão de alguém não precisa esperar o pacote 5 de 8.

---

## 4. Duas regras da blueprint que eu mudaria, e como

### 4.1 As 12 edições revisadas

A blueprint exige revisão integral das primeiras 12 edições publicáveis e ela
mesma corrige a conta: em cadência quinzenal, isso é **~24 semanas**, não quatro.
A honestidade está certa; a regra, aplicada a todo mundo, não fecha dentro do
horizonte deste projeto.

**Não proponho enfraquecer o portão. Proponho separar o público:**

- **piloto com 3 a 5 leitores conhecidos:** revisão integral das primeiras
  **4** edições, com erro crítico zero. Quem lê sabe que é piloto;
- **publicação para cliente pagante:** as 12 edições integrais continuam
  exigidas, sem exceção.

A regra não estava errada — estava aplicada ao público errado. Um piloto com
três pessoas que sabem que é piloto não carrega o mesmo risco de uma assinatura
comercial, e tratar os dois igual é o que torna o portão inalcançável.

### 4.2 As emendas que faltam contra o §34

A blueprint introduz **conversa com LLM**, **painel de creators** e
**plataformas sociais**. O §34 do `CANARIO.md` proíbe explicitamente
Instagram/TikTok, e o protocolo §3 exige entrada no changelog para toda
mudança. A51 e A52 estão registradas; estas três superfícies, não.

**Duas saídas, e é preciso escolher uma:**

- registrar as emendas (o que torna o escopo real e auditável); ou
- tirá-las da 1.3 (o que reduz o escopo ao que já está autorizado).

O que não dá é continuar como está: um plano que constrói o que a constituição
do projeto proíbe, sem a emenda que o §3 exige. É exatamente o tipo de
divergência silenciosa entre regra escrita e código que o próprio projeto já
pagou caro para descobrir — `papel = grupo` é a mesma doença em outro lugar.

---

## 5. O que custa trocar de ordem

**Nada do que já foi construído é jogado fora.** A51, A52, o Scout, o
materializador, a revisão cega e o P1 continuam válidos e continuam sendo a
fundação. A troca é de **sequência**, não de arquitetura.

| O que muda | Custo |
|---|---|
| P2 espera ~1,5 semana | Duas semanas de calendário, nenhuma linha descartada |
| F1 sai de "paralelo" e vira bloqueante de P3 | Pode adiar P3; pode também economizá-lo inteiro |
| A edição concierge consome uma semana de trabalho humano | É a semana mais barata do projeto para descobrir se ele interessa a alguém |

**O que custa NÃO trocar:** continuar construindo P2 e P3 sem saber R1 e R2. Se
R1 voltar negativo depois de P2, boa parte de P2 terá sido desenhada para um
corpus que não existe. Se R2 voltar negativo depois de P5, o projeto inteiro terá
sido construído para um leitor que não queria.

---

## 6. O primeiro passo, se você aprovar

Um só, e não depende de mim: **abrir a matriz de acesso da F1** e responder, por
fonte, "existe método autorizado hoje?". As sete fontes não internas já estão
listadas com o que falta em cada uma, em `EXECUCAO_1_3.md` seção F1.

Dois dias. Nenhuma linha de código. E é a informação mais barata que este
projeto pode comprar agora.
