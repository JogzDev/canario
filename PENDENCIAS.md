# Pendências do DataDrobe 1.2

**Atualizado em 26/08/2026 às 15:20 BRT.** Esta lista substitui a triagem de
20/08, que ainda chamava de pendente telas e funções já entregues.

## Bloqueio externo — depende do Figma

1. **Pacote visual do Figma.** Aplicar as novas telas e os assets finais. A
   hierarquia do Market panel e a redução de texto em “Which item” ficam nesta
   etapa para não desenhar duas vezes a mesma interface.

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
- **Strings novas ainda não estão no String Catalog.** `SWIFT_EMIT_LOC_STRINGS`
  está ligado, então elas entram sozinhas no próximo build feito pelo Xcode
  (não pelo `xcodebuild` em DerivedData temporário). Acontece naturalmente ao
  gerar o Archive.

## Trabalho local do JP ainda não commitado

- `app/Canario/Localizable.xcstrings` tem **219 chaves** na cópia local e **145**
  no repositório. `FICHA_APP_STORE_1.1.md`, `POLITICA_PUBLICA_1.1.md`,
  `SONDA_CANDIDATAS.md` e `capturas_1.1/` também estão só na máquina. Nenhum
  deles entrou em commit de agente, de propósito; decidir o que versionar é seu.

## Fechamento de release — depois do Figma

- **Já validados fisicamente em 26/08:** instalação limpa, login e relogin com o
  SDK Google nativo, câmera e fototeca. O artefato rosa, a demora de ~30 s e a
  repetição indevida do consentimento também não voltaram a ocorrer.
- Rodar os quatro aceites físicos ainda pendentes: offline, Universal Links,
  Dynamic Type e VoiceOver. O app é deliberadamente light-only
  (`.preferredColorScheme(.light)`), portanto modo escuro não é caso suportado.
- Rodar a regressão visual no iPhone e a suíte completa.
- Gerar Archive Release 1.2, validar assinatura/entitlements, enviar ao
  TestFlight e repetir os fluxos críticos no binário distribuído.
- Atualizar capturas e metadata da App Store com as telas finais; só então
  submeter a 1.2 para revisão.

## Para a virada de temporada — não mexer antes da 1.2

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
  de virada com recomputação.
- **Promover as 13 candidatas ao painel medido.** Elas já entregam o benefício
  visível (similares com foto, preço e marca) de dentro de
  `catalogo_candidato_br`, sem tocar em índice, raridade ou z-score. Promovê-las
  exige virada explícita, recomputação e folga de banco — nesta ordem.
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

## Entregue na 1.2 antes do Figma

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
