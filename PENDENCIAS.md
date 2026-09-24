# Pendências do DataDrobe 2.0

**Atualizado em 21/09/2026 às 07:30 BRT.** Esta lista substitui a triagem de
20/08, que ainda chamava de pendente telas e funções já entregues.

## Prioridade corrente — observação e liberação

1. A execução de 20/09 fechou verde. O evento de 21/09 não apareceu e não
   conta; acompanhar agora 22 a 26/09. Cada dia precisa fechar
   com pipeline verde, data pública comprovada e cota em até 85%. Um dia
   parcial, ausente ou inconclusivo não conta como observado.
2. Não disparar coletas manuais para “completar” um dia: a automação acompanha
   o evento `schedule` e o próprio pipeline decide publicação.
3. PRs #36 e #42 moveram o caminho inteiro para executores gerenciados,
   inclusive capacidade final e isolamento. O supervisor local está
   desabilitado, sem listener ou vigília de energia; scripts e logs foram
   preservados. **Não instalar nem reativar runner residencial.**
4. O app consumidor já está na `main`, mas a próxima versão pública será 2.0,
   não 1.2. Ela só sai depois de sete dias verdes, regressão visual no iPhone,
   redesenho final, logo nova e decisão entre Garbo/Filo. Só então gerar
   capturas, Archive, TestFlight e validar o binário distribuído.
5. A direção internacional continua manual. O GitHub não inventa uma agenda
   para ela. O catálogo candidato passou de segunda e quinta para **todo dia**
   em 23/09, porque o JP decidiu promovê-lo (ver a virada abaixo).

Janela acumulada: **2/7 marcos válidos**. Em 19/09, a baseline publicou a API
e mediu **365.534.005 bytes (73,1%)** depois da coleta isolada, saúde e motor.
Em 20/09, a run agendada `35504417793` publicou painel e eventos do próprio
dia; a verificação `35513837999` mediu **367.270.709 bytes (73,5%)**, ou
+1.736.704 bytes, e confirmou zero contaminação em `direcao_intl`. O cron de
21/09 não gerou run e não conta. Restam cinco ciclos válidos, de 22 a 26/09.

## Autonomia e segurança entregues em 21/09

- Pipeline, catálogo candidato, saúde, motor, publicação e sondas automáticas
  deixaram de depender do Mac pessoal.
- VTEX, Shopify, FFW e Google Trends foram provados em executores gerenciados,
  sem segredo e sem escrita, antes da virada.
- Animale integral ficou semanal porque não há `lastmod` incremental confiável;
  os dias pulados são declarados, nunca chamados de catálogo observado.
- GitHub executa a lógica Swift curta; scheme compartilhado e script protegido
  restauram build e os fluxos UI completos no Xcode Cloud.
- HTTPS é obrigatório no cliente; imports Deno e Actions estão fixados;
  Dependabot, alertas de vulnerabilidade e correções automáticas foram ligados.
- O gabarito de segurança tem 13 itens atendidos, 6 parciais e 1 não aplicável.
  Os parciais permanecem visíveis em `AUDITORIA_SEGURANCA_2026-09-21.md`.

## Pacote visual herdado — base atual, não fechamento da 2.0

Arquivo `EZ58SkSJRlcTLOC6NDgdGR`, uma página só. As telas finais, a hierarquia
do Market panel, Fill the info, busca, conta, ajustes, tendências, similares e
os consertos de menu/paleta foram incorporados ao código em 31/08. Em 21/09 o
JP decidiu que a próxima publicação será 2.0 e exigirá outro fechamento de
design, logo nova e nome novo. Portanto este pacote é a base funcional atual,
não o aceite visual da 2.0.

**Regras de desenho combinadas em 26/08, válidas para todas as telas:**

- **Human Interface Guidelines da Apple** são o padrão, não uma referência
  solta. Ícone sai do **SF Symbols**; onde ele não existe, improvisar mantendo
  a métrica e o peso da família.
- Molduras e cartões usam a sombra suave cinza-gelo do padrão Apple, e não
  retângulo chapado.
- O texto de privacidade do importador **fica**.
- O desenho do Davi é a base: melhorar formatação e conformidade sem
  descaracterizar o que ele fez.
- Imagens de peça nas telas do Figma são **exemplo** — o casaco de bandeiras
  não vai para o app. Todo campo de imagem mostra a peça que o usuário enviou.

**As três telas do fluxo de importar estão implementadas:**

1. *Analyze an item* — finalizada com as três entradas.
2. *Confirm your item* — finalizada com seleção/recorte do alvo.
3. *Fill the info* — finalizada, incluindo:
   - **Cor passa a ter ordem de prioridade.** Os números 1, 2 e 3 sobre os
     círculos são posição, não contagem: 1 é a cor principal, 2 a secundária, 3
     a terciária. Nem toda peça chega a três. **O teto foi fixado em 3.** É o
     **único** campo com ordem; categoria, estampa, estilo e o
     resto seguem seleção simples, como hoje.
   - **É uma tela de scroll longo**, e o `intended price` desce para o fim
     dela. Ele sai da tela de entrada — decisão de produto tomada em 26/08.

O portão automatizado abriu Add, percorreu o fluxo e salvou sem repetir a antiga
tela Clothing Details. A última pendência desta frente é a regressão visual em
aparelho e a produção de capturas novas para a loja.

## Migrations aplicadas em 27/08 — conferidas em produção

**A48 e A49 estão no banco.** Aplicadas pelo conector do Supabase no projeto
`tbluoqpnjqsflfoclmms`, com verificação depois de cada uma:

| Conferido | Antes | Depois |
|---|---:|---:|
| `motivo_estampa` aprovados | 6 | **0** (6 reprovados) |
| `conversacional` aprovado | 1 | 1 |
| termos aprovados no total | 51 | 45 |
| ligações em `produto_termos` dos motivos | 212 | **212** (nada destruído) |
| coluna `cores_prioridade` | ausente | presente, com 2 `check` |
| `aplicar_mudancas_closet` carrega a ordem | não | **sim** |
| `similares_da_peca_amplo` cita `motivo_estampa` | sim | **não** |

E o motor continua de pé: `conversacional` devolve 24 peças (igual a antes),
`tomate_print` devolve 0 (aposentado, como planejado), o caso do vídeo
(`casaco_jaqueta` + `cinza`) devolve 24 e o motor amplo devolve 12 para
`vestido` + `floral`.

**Nota sobre o registro de migrations.** `supabase_migrations.schema_migrations`
tinha 72 linhas e parava na A34, enquanto o schema já continha o efeito da A35
até a A47 — sinal de que as intermediárias foram aplicadas pelo editor SQL, que
não registra. O registro não é fonte confiável de estado neste projeto; o schema
é. A48 e A49 ficaram registradas.

## A Luna subiu para a v11 em 27/08

Decisão do JP, depois de reabrir o caso: ele aceita os 79,2% do vocabulário
ampliado (*"0,8% é muito pouco pra reprovar algo que claramente funciona, e é a
minha escolha final"*) e exigiu que as melhorias da v9, da v10 e da v11
estivessem **todas** na versão final. Isso descartou a saída cirúrgica de
implantar só a remoção sobre a v9.

O que a produção ganhou, além da remoção do `print_motifs`:

- o termo **`conversacional`** — sem ele, a Luna nunca conseguiria pré-marcar
  *Illustrated prints*, e a A48 ficaria pela metade para sempre;
- **cintura média e baixa** — a v9 só sabia devolver `cintura_alta`, ou seja,
  dois dos três valores eram letra morta.

Antes de subir, cada comportamento da v9 foi conferido no código implantado:
modelo, `max_output_tokens`, `reasoning.effort`, limite de imagem, rate limit
por origem e global, consentimento, `verify_jwt = false` e a ordenação de cor
por área visível. Nenhum se perdeu. Sonda de contrato depois do deploy:
`invalid_image` / HTTP 400.

**Nada mais depende do JP nesta frente.** As três coisas que estavam na mão
dele — A48, A49 e o redeploy — estão feitas.

## Operacional — aberto agora

- **Amaro e PatBô: RESOLVIDO em 26/08, e a causa era transitória.** As duas
  voltaram a coletar normalmente **na mesma máquina que falhava** (o i7,
  `10-46-53-103`): Amaro 256 visitados em 10 s, PatBô 7.470 em 134 s, sem erro.
  O banco confirma que o dado bom sobrescreveu o zero de hoje, então sobrou
  25/08 como zero isolado e o contador de dias seguidos está em **zero**.
  Antes disso, três hipóteses caíram por medição: **não era IP** (a mesma rede
  responde 200), **não era ritmo** (10 páginas seguidas a 1 req/s sem 429) e
  **não era a máquina** (a mesma coletou tudo). Foi recusa transitória do lado
  da Shopify, atravessando duas janelas de coleta. `SAUDE.md` no repositório
  ainda mostra "2º dia" porque é gerado pelo pipeline; refaz sozinho amanhã.

- **O grupo de concorrência `canario-dados` já travou uma vez.** Em 26/08 três
  execuções de coleta ficaram presas atrás de um run que o GitHub listava como
  `queued` e recusava cancelar dizendo ora "completed", ora "não enfileirado".
  Dez workflows compartilham esse grupo — coletas, motor, centroides e as duas
  de Luna; `testes.yml` não, e por isso o CI passava enquanto nada coletava.
  Destravou sozinho. Dois runs antigos continuam aparecendo como `queued` pela
  API, embora a própria API recuse cancelá-los como `completed`; runs posteriores
  passaram normalmente. São registros fantasmas, não trabalho em execução. Se
  voltarem a bloquear o grupo, a saída conhecida é cancelar pela interface web.

## Acabamento adiado conscientemente

- **O card social renderiza 1080×1350 na main thread.** `CartaoCompartilhavel.imagem`
  é `@MainActor`. Dá para tirar de lá, mas o ganho são 1–3 quadros numa ação que
  já mostra "Preparing export…", e mover desenho de texto para fora da main
  thread traz risco pequeno de crash. Adiado para depois da submissão, não
  esquecido.
- **"Continua perguntando toda vez" (análise na nuvem) não foi reproduzido.** A
  persistência funciona isolada — grava, relê numa instância nova e devolve o
  valor certo — e só existe um ponto no app que dispara a pergunta, e ele
  consulta a preferência antes. O que foi corrigido é o defeito **provável de
  causar o relato**: os Ajustes tinham um interruptor de dois estados que
  mapeava `perguntar` para "nuvem ligada", então a tela afirmava uma coisa e o
  fluxo fazia outra. Agora são três opções explícitas. **Se voltar a acontecer**,
  olhar o que os Ajustes mostram: "Always use the cloud" e mesmo assim
  perguntando é bug reproduzível; "Ask me the first time" significa que a escolha
  não está sendo gravada.
- **Strings novas fora do String Catalog — resolvido.** O catálogo versionado
  passou de 145 para **216 chaves** ao entrar o visual novo. Cuidado que
  permanece: o Xcode **poda** do catálogo toda string que a interface deixa de
  citar, e num redesenho isso apaga também as que voltarão. Foram 25 podadas de
  uma vez em 26/08, das quais 10 o código ainda usava. Ao aplicar cada tela do
  Figma, conferir o diff do `Localizable.xcstrings` além do `.swift`.

## Trabalho local do JP ainda não commitado

- `app/Canario/Localizable.xcstrings` **deixou de ter conteúdo próprio**: as 9
  chaves que só existiam na cópia local são textos que o visual novo tirou da
  interface. Depois do merge do PR #19, `git checkout --
  app/Canario/Localizable.xcstrings` descarta a cópia sem perder nada.
- `POLITICA_PUBLICA_1.1.md`, `SONDA_CANDIDATAS.md` e `capturas_1.1/` continuam
  só na máquina. Nenhum foi apagado ou alterado por este corte.

## Histórico do candidato 1.2 — substituído pelo plano da 2.0

- **Já validados fisicamente em 26/08:** instalação limpa, login e relogin com o
  SDK Google nativo, câmera e fototeca — e também **offline, Universal Links,
  Dynamic Type e VoiceOver**, os quatro que faltavam, confirmados pelo JP. O
  artefato rosa, a demora de ~30 s e a repetição indevida do consentimento
  também não voltaram a ocorrer. **Nenhum aceite físico segue pendente.** O app
  é deliberadamente light-only (`.preferredColorScheme(.light)`), portanto modo
  escuro não é caso suportado.
- **Suíte automatizada repetida:** 281 Swift, 32 portões Python, build iOS e
  sete fluxos UI verdes.
- **Archive Release 1.2 (1) gerado, enviado à Apple em 31/08 e preservado no
  Organizer.** Ele antecede A57/A58 e está substituído. A exportação diagnóstica
  de 20/09 provou conta, assinatura de distribuição e perfil com Sign in with
  Apple e Associated Domains. Não existe candidato atual para publicação; o
  próximo será 2.0 depois dos sete marcos, redesenho, logo e nome.
- Rodar a regressão visual no iPhone; é o aceite que precisa ser repetido porque
  as telas mudaram.
- Depois da exportação verde, enviar ao TestFlight e repetir os fluxos críticos
  no binário distribuído.
- Atualizar capturas e metadata da App Store com as telas finais; só então
  submeter a 2.0 para revisão.

## Fila do depois — decidido, sem prazo

- **Calibrar o motor de similares.** Pedido do JP em 27/08. O que já está
  medido e aponta para onde mexer:
  - **A cobertura por dimensão é o gargalo, não a regra.** Medido em 26/08:
    categoria 97,4%, cor 38,5%, tecido 33,6% — e depois disso despenca, com
    estampa em 5,4% e cintura em 4,6%. Exigir 70% dos atributos quando duas
    das cinco dimensões quase não existem no painel é zero garantido.
  - **A escada de relaxamento vale mais que qualquer ajuste de peso.** Na
    medição da polo: 4 de 5 atributos devolveu **0** similares; tirar um
    único atributo da dimensão mais rala devolveu **13 peças em 4 marcas**.
  - **Duas cores da mesma dimensão colapsam o conjunto.** `vestido + preto`
    dá 202, `vestido + branco&cru` dá 153, e as três juntas dão **12** —
    porque título de produto quase nunca lista duas cores. Dentro da mesma
    dimensão os termos deveriam competir (OR), não se exigir (AND).
  - **A A49 abre um caminho novo, e assimétrico.** A peça do usuário agora
    sabe qual é a cor principal; o produto do painel não sabe, porque a cor
    dele sai do título e título não diz proporção. Dá para exigir que a cor
    **principal** da peça case, em vez de aceitar qualquer coincidência de
    cor — é o que evita uma busca por verde devolver uma peça 80% rosa com um
    detalhe verde.
  - **O maior buraco isolado:** 4.509 produtos dizem "estampado" no título e
    só 1.100 receberam algum termo de `estampa`. São ~3.400 peças que o
    painel declara estampadas e o motor não consegue casar.

## Virada metodológica e de temporada — ainda não executada

- **`papel = grupo` conta como mercado externo, e não deveria.** A
  [`CANARIO.md`](CANARIO.md) diz, na linha 145, que Farm, Animale, Maria Filó e
  NV são autobenchmark e *"nunca contam como 'mercado externo' nos índices"*.
  Mas `computar_serie_varejo` monta a população só com
  `where p.segmento is not null` — não há join com `marcas` nem filtro por
  `papel`. Só a **contagem** de marcas do portão de cobertura exclui o grupo.
  Então os produtos dessas quatro marcas entram no denominador e em todo share
  de `feminino_casual_br`. Isso é divergência entre a regra escrita e o código,
  medida em 26/08, e vale independentemente de qualquer marca nova.
  **Não corrigir agora:** o conserto muda todo share histórico, que é operação
  de virada com recomputação. **Decidido pelo JP em 23/09: vai junto com a
  promoção das candidatas**, porque as duas mexem no denominador e juntas a
  série quebra uma vez só.
- **Promover as 13 candidatas ao painel medido — decidido pelo JP em 23/09:
  "o mais cedo possível".** Elas já entregam o benefício visível (similares
  com foto, preço e marca) de dentro de `catalogo_candidato_br`, sem tocar em
  índice, raridade ou z-score. O caminho, nesta ordem:
  1. Coleta diária desde 24/09, ainda como candidatas. A trava de publicação
     (A60) exige toda marca do painel vista todo dia; promover antes congelaria
     o painel, como a Animale semanal em 22/09.
  2. Quatorze dias de histórico diário, para a curva e a série não receberem
     marca com janela vazia. De 03 a 14/09 a coleta delas falhou quatro vezes
     seguidas (banco a 96,9%), e só a de 21/09 passou.
  3. A virada por volta de 08/10: segmento trocado, `papel = grupo` fora do
     mercado externo, recomputação e quebra declarada, sem eventos falsos
     (o mesmo cuidado da A61).
  **Banco:** 73,5% em 23/09, mas baixo por acaso, porque faltam as fotos de
  03 a 17/09. Com a retenção de 21 dias cheia de novo, o feminino volta a uns
  79%; com as 13 diárias, uns 81% do banco, perto dos 85% do dia verde.
  Medir nos três primeiros ciclos e parar a coleta diária se a projeção passar
  de 85%. Marca nova (Loja 3, Mondepars, Carmim) custa bytes de verdade e não
  cabe antes de liberar espaço; `series_semanais` (1,4 KB por linha) é o
  primeiro lugar a olhar.
- **Suéter/quarter zip cai em duas categorias diferentes.** Medido em 26/08:
  1.281 títulos dizem suéter/pullover e eles se dividem em **819 dentro de
  `casaco_jaqueta` e 361 dentro de `blusa_top`** — a mesma peça em duas
  categorias conforme a palavra que a loja usou. A causa é o vocabulário:
  `casaco_jaqueta` casa `cardigan` mas não casa `suéter`, `pullover` nem
  `blusão`. Categoria isolada para quarter zip **não se sustenta** — existem 2
  no painel inteiro, contra o mínimo de 30 do §8. O conserto é acrescentar essas
  palavras a `casaco_jaqueta` e renomear o rótulo para algo como
  "Coats, jackets & knitwear". **Não antes da 1.2:** move ~500 produtos entre
  categorias e exige republicação do motor.
- **Categoria não está sendo exclusiva, e o §11 diz que deveria.** Medido em
  26/08: **7,85% do painel (5.884 produtos) carrega duas ou três categorias** ao
  mesmo tempo, e cada um conta nos dois shares. Isso existe hoje,
  independentemente do suéter — e é por isso que a correção acima não pode ir
  sozinha: adicionar vocabulário sem regra de precedência aumentaria a marcação
  dupla em vez de reduzi-la. As duas coisas viram um passe só na virada.
- **Corrigir o viés de composição antes de crescer.** C&A é ~53% do painel, e
  hoje o share é calculado por SKU, então a maior marca domina por volume. Média
  entre marcas com peso por papel resolve isso melhor do que adicionar marcas.

## Validações posteriores, não bloqueadoras da implementação

- **Calibração Luna somente com amostra nova.** A taxonomia expandida da 1.2
  deu 57/72 em categoria e cor (79,2%) nas mesmas 24 imagens. O conjunto não
  será repetido nem usado para perseguir décimos: cinco casos difíceis ficam
  registrados como erro conhecido. Um futuro holdout usa imagens novas e
  orçamento explícito. Isso não bloqueia o Figma nem os fluxos manuais.
- **Cold launch, artefato rosa, demora e consentimento: RESOLVIDOS.** O JP
  revalidou no iPhone em 26/08 que o artefato não existe mais, a espera de ~30 s
  acabou e a autorização de análise não volta a aparecer indevidamente.
- **Floral recente é zero verdadeiro.** A recomputação leu 170.813 artigos e
  persistiu 16.287 pares de título+resumo. Na semana atual, 28/46 termos BR e
  22/47 internacionais têm cobertura; `floral` não tem matéria que também
  declare contexto de roupa. Flores pessoais, unhas, casamento e calçados
  continuam excluídos. A próxima expansão de fonte deve ser guiada por recall
  feminino medido, nunca pela necessidade de fabricar um número para essa tela.
- **Malwee recuperada e coletada.** O domínio oficial abriu no VTEX público,
  com cerca de 14.450 produtos brutos e `robots.txt` respeitado. O recorte
  elegível fechou em 3.082 visitados = 3.082 declarados; o retry alterou somente
  duas linhas. Ela está em `catalogo_candidato_br`, portanto amplia similares
  sem mudar a coorte medida. Depois da recuperação de 26/08 o banco está em
  81,5%, e o portão continua bloqueando expansão que leve a margem a zona
  insegura.

## Entregue no código atual antes do próximo redesenho

- Apple, Google e e-mail/senha validados fisicamente no iPhone pelo JP em 24/08.
  O fluxo Google hospedado foi depois substituído pelo SDK oficial nativo para
  não expor o domínio interno da Supabase; integração e build estão verdes.
- E-mail transacional gratuito validado de ponta a ponta em 24/08: Supabase →
  Brevo → Gmail, com envio, entrega e primeira abertura registrados. O chamado
  **#5525910** recebeu a confirmação e foi respondido como resolvido; usuários
  técnicos de teste foram apagados.
- Login opcional com Apple, Google e e-mail/senha; recuperação, logout, exclusão,
  Keychain, RLS e sincronização offline-first do Closet. Miniaturas reduzidas
  sincronizam em bucket privado com hash; a foto original permanece local.
- Banco estabilizado no plano gratuito: estado volátil em tabela estreita,
  retenção segura de snapshots e recuperação do inchaço sem apagar séries.
- Um botão de compartilhar com bottom sheet, links autocontidos, Universal Link,
  fallback da App Store, card social e CSV de uma peça, seleção ou Closet inteiro,
  com opção de incluir leitura de mercado e sua data. Card social inclui a foto;
  card, link e planilha usam o mesmo nome canônico e não expõem placeholders
  legados como “Replacing”.
- Nome visível/editável, busca e filtro local do Closet por favorito e atributos.
- Depois de Fill the Info, a confirmação final abre como página, reúne nome,
  atributos e Add to Closet, sem repetir Clothing Details. Voltar preserva foto
  e análise, sem nova chamada à visão quando nada mudou. A busca do Closet é
  o drawer recolhível nativo, o canto esquerdo virou menu de três pontos e o
  Compare passou para Weekly Trends.
- Similares com foto no alto do relatório, polo como camisa, relaxamento declarado
  por cobertura e fallback sem abandonar categoria nem motivo de estampa.
- O backend de importação por URL foi entregue e provado com Farm/tomate, mas a
  porta saiu da interface em 26/08 a pedido do JP. Portanto **não é uma
  funcionalidade disponível da 1.2**; recolocá-la exige reconstruir o cartão,
  embora o RPC continue pronto. Motivos visuais de frutas e couro permanecem.
- Editorial refiltrado para feminino sem apagar o arquivo, fontes clicáveis,
  contagens cruas e zero honesto no lugar do “−100%” enganoso.
- Editorial dos atributos acessível a partir da peça salva.
- Painel `direcao_intl` isolado com Doen, Rouje, Staud, Faithfull the Brand e
  With Jean: 4.956 itens visitados, 3.768 produtos elegíveis e zero produto das
  cinco marcas fora do segmento, comprovados pelo portão de produção.
- 257 testes Swift, 30 portões Python e oito fluxos de UI (incluindo o filtro do
  Closet e a confirmação final) verdes no ambiente local; build de simulador
  verde.
- Travamento do Closet resolvido na causa: rótulos e filtro saíram do `body`
  para `CanarioLogica`. Medido em 200 peças e 212 termos, vinte passagens do
  `body` caíram de **3,215 s para 0,023 s** (142×), e o orçamento virou portão.
  Weekly Trends e a lista de favoritos tinham o mesmo padrão e foram corrigidos
  junto. A espera da análise remota avisa depois de 8 s em vez de repetir
  "usually takes a few seconds" até o teto de 30 s.
- Botão Add centralizado por geometria: quadro, manequim, disco e `+` em
  x = 50,000, conferido a cada push por `teste_experiencia_app.py`.
- Privacidade declarada reconciliada com o binário e coberta por portão novo
  (`teste_privacidade_declarada.py`); `excluir-conta` passa a purgar as
  miniaturas antes de apagar o usuário.
- Pacote de 26 reclamações e quatro ressalvas fechado no código: consentimento
  de visão persistente, teclado e Add alinhado, sete badges, cards do Closet,
  evidência editorial da janela, comparação com cobertura real, tradução
  residual, taxonomia sem duplicidade de knit, animal print destacado e URL de
  produto com imagem carregada sem bloquear a interface.
- Editorial recomposto em produção: 11.184 pontos BR e 5.955 internacionais;
  filtro masculino aplicado ao arquivo inteiro. Foram classificados 86.095
  artigos femininos, 50.755 neutros e 33.976 masculinos. Motor publicado com
  109.543 produtos e 266.623 ligações.
- Catálogo candidato brasileiro com as 12 marcas anteriores mais 3.082 produtos
  elegíveis da Malwee; a prova de isolamento em produção fecha esta entrega.
- Banco no plano gratuito em **407.342.227 / 500.000.000 bytes (81,5%)**, com
  92.657.773 bytes livres, zero tuplas mortas e séries históricas preservadas
  (28.069 pontos, 2009–2026). Isso equivale a aproximadamente 388,5 MiB usados;
  “388 MB / 500 MB” misturava unidades e foi aposentado.
- `excluir-conta` publicada (versão 2) e provada em produção com conta técnica
  descartável: a função respondeu `miniaturas_removidas: 1` e o banco confirmou
  usuário, identidade e objeto zerados, sem tocar nos dados reais.
