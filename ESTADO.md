# ESTADO — DataDrobe

**Última atualização:** 25/08/2026, 22:10 em São Paulo

**Identidade atual:** `br.com.canario.ch3.app`; qualquer outro bundle citado
neste documento é histórico, não uma instrução de configuração.

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
| Dados e pipeline | editorial feminino recomposto; direção e catálogo candidato isolados | 170.813 artigos · 16.287 pares compactos · **14.678 produtos candidatos** |
| Banco | plano gratuito; retenção crua no piso seguro de 21 dias | **422.145.171 bytes / 500 MB (84,4%)** após toda a expansão |
| Rota paga de visão (Luna) | produção preservada; prompt expandido da 1.2 **retido** | 57/72 categoria · 57/72 cor (79,2%); holdout de 300 não executado |
| App na loja | **1.1 publicada; 1.2 build 1 em desenvolvimento** | código funcional pronto antes do pacote final do Figma |
| E-mail transacional | **Brevo SMTP ativo e validado de ponta a ponta** | Supabase → Brevo → Gmail: enviado, entregue e aberto |
| Autenticação no aparelho | **Apple, Google e e-mail validados**; Google nativo integrado | cliente iOS criado, Supabase configurado e build verde; falta repetir Google nativo no iPhone |
| Closet privado | dados e miniaturas sincronizados com RLS; originais permanecem locais | bucket privado · hash verificado · limite de 3 MB |
| Testes | **249 Swift** · portões Python ativos · 8 UI | Auth, Keychain, sync, compartilhamento, filtros e fluxo final de confirmação |

## 0. Trabalho ativo de 24/08 — conta, capacidade e 1.2

A 1.2 revoga somente a antiga regra de ausência de conta. A conta continua
opcional: Apple, Google ou e-mail; o app permanece utilizável como convidado.
Sessões ficam no Keychain, os dados estruturados do Closet e miniaturas reduzidas
sincronizam com RLS em bucket privado; os originais permanecem somente no aparelho.
Há recuperação de senha, logout e exclusão integral iniciada dentro do app.

A27 moveu `ultimo_avistamento_em`, `ofertavel` e `ultimo_snapshot_em` para
`estado_dos_produtos`, uma linha estreita, e já está em produção. A42 mantém
21 dias de snapshots crus sem apagar a série semanal histórica. Depois do
`VACUUM FULL` seguro, o banco caiu de 445.123.731 para 388.861.075 bytes; antes
da coleta internacional estava em 397.790.355 bytes (79,6%) e, depois dela e
do motor, em **404.343.955 bytes (80,9%)**, com 95.656.045 bytes livres.

A 1.2 também já contém compartilhamento e exportação por um único botão,
Universal Links autocontidos, importação por URL de produto, motivos visuais
de estampa, couro, similares relaxados com explicação, editorial feminino
reclassificável, detalhe clicável das fontes e busca/filtro local do Closet.
Em 24/08, o preenchimento da peça deixou de manter Clothing Details dentro da
sheet: o resultado agora abre em tela cheia, com Add to Closet no canto superior
esquerdo. A busca do Closet usa o drawer nativo recolhível; o canto que levava
ao Compare virou o menu de três pontos, e Compare passou para Weekly Trends.

As cinco marcas de direção internacional foram materializadas e coletadas:
Doen 672, Faithfull the Brand 690, Rouje 1.170, Staud 2.031 e With Jean 393.
Depois dos filtros de população, **3.768 produtos** ficaram em `direcao_intl`:
666, 617, 917, 1.282 e 286, respectivamente. O portão de produção contou zero
produto dessas marcas fora do segmento. Elas não entram no denominador
brasileiro e, com cinco fontes, continuam abaixo do mínimo de oito para índice.

Em 25/08, 12 marcas brasileiras adicionais entraram em
`catalogo_candidato_br`: Calvin Klein BR, Charry, Damyller, Dudalina, Iorane,
John John, Levi's BR, Lez a Lez, Maria Valentina, Osklen, Sacada e Scalon.
Foram 16.376 produtos crus; o recorte de população manteve **14.678** no
catálogo candidato, excluiu 1.698 masculinos/infantis/íntimos/praia e atribuiu
**zero** produto a outro segmento. Essas peças ampliam similares, mas não
alteram o painel brasileiro, índice, raridade ou z-score. O retry final da
Dudalina confirmou 552 visitados = 552 declarados e zero gravação nova.

O editorial foi recomposto integralmente a partir de **170.813 artigos**:
86.087 classificados como femininos, 50.755 neutros e 33.971 masculinos
excluídos. Título + resumo agora produzem somente pares compactos em
`artigo_termos`; são 16.287 ligações em 7.587 artigos, ocupando 1,65 MB, sem
armazenar resumo ou texto integral. A troca atômica publicou 11.179 pontos BR e
5.764 internacionais. Na semana de 24/08, 28/46 termos BR e 22/47 internacionais
têm artigo qualificado. `floral` permanece zero nas duas pernas porque nenhum
artigo recente passou simultaneamente pelo matching e pelo contexto de roupa;
flores pessoais, unhas, casamento e calçados não são convertidos em roupa.

Em 25/08, A44 e A45 entraram em produção. A44 adiciona miniaturas privadas do
Closet com caminho pertencente ao `auth.uid`, limite de 3 MB e validação por hash;
isso permite restaurar as fotos reduzidas depois de reinstalar sem transformar o
banco em álbum de originais. A45 tornou a resolução de URL exata e indexada nos
segmentos brasileiro e candidato. O produto oficial “Vestido Pontas Estampado
Tomates” da Farm resolve com imagem, preço e termos `vestido` + `tomate_print`;
esses termos já devolvem similares de outras marcas sem chamada à Luna.

O pacote de QA de 25/08 também unificou o nome exibido no Closet, card social,
link e CSV, ignorando placeholders legados como “Replacing”; colocou a foto no
card social; preservou o estado ao voltar no fluxo de Add; terminou o fluxo na
confirmação com os atributos e Add to Closet; corrigiu teclado, alinhamento,
badges, texto de consentimento, cards do Closet, tradução residual de `camisa`,
comparação e evidência editorial na janela inteira. A Malwee foi recuperada no
endpoint VTEX público oficial e está pronta para a coleta isolada como catálogo
candidato, sem alterar a coorte medida.

A expansão e a primeira recomputação levaram o banco temporariamente a 97,15%.
A retenção no piso seguro removeu 93.587 snapshots fora da janela, compactou a
tabela e preservou todas as séries. Depois dos pares editoriais e do motor final,
o banco fechou em **422.145.171 bytes (84,4%)**, com 77.854.829 bytes livres.
O motor final provou idempotência: 106.298 produtos, 257.070 ligações e zero
produto, segmento ou ligação alterado na segunda publicação.

O único bloqueio de implementação antes do fechamento da release são as telas
finais do Figma. Apple, Google e e-mail foram validados no iPhone em 24/08. O
Google foi depois migrado do navegador hospedado pela Supabase para o SDK nativo
oficial: o cliente OAuth iOS, os dois públicos aceitos pelo Supabase e o esquema
de retorno estão configurados, e o build de simulador passou. Falta apenas
repetir esse provedor no iPhone para validar o novo caminho físico. O
SMTP gratuito está resolvido: a Brevo confirmou no pedido
**#5525910** que o relay transacional já estava habilitado, e um cadastro técnico
percorreu Supabase → Brevo → Gmail com eventos de envio, entrega e primeira
abertura. Os usuários temporários foram removidos depois da prova. Sem domínio
próprio autenticado, o remetente continua sendo reescrito para o subdomínio
gratuito da Brevo; isso afeta apresentação, não funcionamento. A lista exata e
atual está em `PENDENCIAS.md`.

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

### O que a coleta seguinte provou

Na publicação de 21/08, com 84.297 produtos, o motor alterou 327 segmentos,
inseriu 887 ligações e removeu 6. A reescrita total não voltou. O banco terminou
em 405.687.443 bytes (81,1% do limite decimal de 500 MB), abaixo dos 83,2%
medidos depois da emergência de 19/08 mesmo após duas novas coletas completas.

O retorno do motor traz três números que tornam uma regressão observável:

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

O pipeline completo de 21/08 terminou verde em 1h02: VTEX, Shopify, editorial,
Trends, saúde, motor e alerta. Antes do alerta existir, o pipeline falhou
**cinco execuções seguidas** (14 a 17/08) e ninguém soube.

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
**quatro faixas de preço truncadas em 2.500**. A investigação de 21/08 mostrou
que os 66.353 resultados nessas faixas são produtos indisponíveis ainda
indexados pela busca Legacy da VTEX. O coletor agora consulta a disponibilidade
quando preço não consegue mais particionar, exclui esse universo do catálogo
ofertável e registra a exclusão na saúde. A coleta completa terminou com 7.876
visitados e 7.876 declarados, sem truncamento.

### P17 em produção — presença, oferta e snapshot são sinais diferentes

Desde 21/08 o painel não chama mais o catálogo histórico acumulado de
"sortimento atual". `ultimo_avistamento_em` anda em toda visita real,
`ofertavel` exige variante/seller comprável e `ultimo_snapshot_em` continua
sendo só delta ou batimento. A série de varejo aceita cada confirmação por no
máximo sete dias; a raridade usa apenas ofertas recentes.

Medição da publicação atômica `a3480682-5e5f-4995-be20-b23336261144`:

| Medida | Antes | Depois da coleta completa e P17 |
|---|---:|---:|
| denominador chamado de sortimento | 74.937 históricos | **25.160 ofertas confirmadas** |
| produtos segmentados avistados em até 7 dias | 51.772 | **56.200** |
| produtos ofertáveis e recentes | não existia como sinal | **25.270** |
| estado atual sem sinal explícito de oferta | campo inexistente | **0** depois de reobservação |

A publicação terminou `success`: 84.297 produtos, 212.409 ligações, 200 células
de varejo recalculadas e materializações antigas removidas por anti-junção.

Isso corrige o significado do denominador, mas não inventa atributos que o
título não contém. A P18 materializa a cobertura de cada dimensão em toda célula
de varejo e exige pelo menos 30% antes de permitir linguagem confiante. Na
publicação final, 23 das 40 células passaram: todas as de categoria, cor e
tecido. As 17 de comprimento, estética, estampa, silhueta e cintura falharam
fechado. `liso` continua com 39 produtos e 0,155% do denominador, mas não pode
mais ser apresentado como tendência sustentada.

### Cobertura fechada e medida em 21/08

* **C&A:** 7.876 visitados = 7.876 declarados. Outros 66.353 resultados
  indisponíveis foram excluídos do universo ofertável e aparecem como sinal de
  saúde, não como catálogo perdido.
* **NV:** as categorias 2, 29 e 131 se sobrepõem; a união única é 563, e não a
  soma 1.329. A categoria antiga 138 foi removida. A coleta terminou 563 = 563,
  sem alerta.
* **Dress To:** segue com aviso explícito de categoria zero. É a única das 15
  marcas cuja contagem permanece incerta; a saúde continua observando-a.

O paginador agora registra 429, 500, resposta vazia e JSON inválido em vez de
encerrar silenciosamente. A workflow residencial aceita recuperação VTEX por
marca; na Farm ela recuperou 2.936 de 2.946 produtos, mas na NV confirmou que o
problema não era a origem da conexão.

### Publicação final da madrugada

O pipeline `32448665712` terminou verde em 52 minutos: VTEX, Shopify,
editorial, Trends, dois portões de saúde, motor e alerta. Nenhuma recuperação
foi necessária. A execução atômica
`19b92240-eb02-45a2-99ef-3b512258bc1e` publicou 84.298 produtos, 212.409
ligações e 193 células de varejo.

| Medida | Antes | Depois |
|---|---:|---:|
| produtos | 84.297 | **84.298** |
| avistados em até 7 dias | 56.200 | **56.201** |
| ofertas recentes | 25.270 | **25.240** |
| indisponíveis recentes | 30.930 | **30.961** |
| estado desconhecido recente | 0 | **0** |
| denominador semanal | 25.160 | **25.162** |

Os shares permaneceram estáveis: a maior variação entre as 40 células foi
`calca`, de 17,9134% para 17,9080% (**−0,0054 ponto percentual**). A mudança é
compatível com duas ofertas a mais no denominador, não com uma quebra de série.

Depois da recuperação pontual de 21/08, o denominador foi de 25.162 para
**25.176**. `calca` ficou em **17,9099%**, movimento de +0,0019 ponto contra a
publicação anterior. As 40 células continuam materializadas; 23 passam o portão
de observabilidade e 17 são corretamente silenciadas. `liso`, o caso que
originou a auditoria, tem 39 peças e 11 marcas, mas apenas 6,4029% de cobertura
da dimensão estampa: `suficiente=false`, portanto não volta a aparecer como
tendência confiante.

A P19 também apertou os similares: agora exigem `ofertavel = true` e
avistamento nos últimos sete dias. O antigo corte por snapshot de 14 dias saiu;
produto sem confirmação recente não é mais oferecido como link vivo.

## 3. Rota paga de visão (Luna)

**De pé e com credenciais cadastradas**, medido em 19/08:

```bash
python3 ferramentas/testar_edge_luna.py --so-contrato   # custo zero
```

Responde `invalid_image`, que significa "subo e tenho `OPENAI_API_KEY` e
`AI_RATE_LIMIT_SALT`". Entre 14 e 18/08 ela respondeu `BOOT_ERROR` por quatro
dias sem ninguém perceber; agora a workflow `sonda-edge-luna.yml` pergunta isso
ao servidor uma vez por dia.

### O portão humano está alinhado com a v7 — e ABRIU

`anexos/portao_luna_24.json` consolida três execuções do mesmo prompt, nas mesmas
24 imagens e com o segmentador usado pelo app. Uma rodada isolada fechou por uma
imagem; as duas seguintes abriram. Somar apenas rodadas com o mesmo SHA removeu
essa decisão por sorteio:

| medida | acertos consolidados | resultado | mínimo |
|---|---:|---:|---:|
| categoria | 59/72 | **81,9%** | 80% |
| cor primária | 60/72 | **83,3%** | 80% |
| clareza do alvo | 58/72 | 80,6% | — |

`passed: true`, prompt `alvo-estrutura-v7`, SHA
`45f9ce7e00c66499847aa2dcf1effb1de347826f4ffa4ae76871b55c2b94dc4f`.
O relatório completo, incluindo intervalos de confiança e as falhas estáveis,
está em `anexos/avaliacao_luna/relatorio-20-08-v7.md`. O gasto já realizado nas
quatro rodadas iniciais foi US$ 0,071.

Uma tentativa posterior de validar o vocabulário ampliado da 1.2 nas mesmas 24
imagens fechou em 57/72 para categoria e cor (79,2%). Ela **não substituiu a v7
de produção**. Duas repetições foram interrompidas em 24/08 quando ficou claro
que otimizar décimos sobre as mesmas imagens seria overfitting e gasto sem valor
para o uso real. Regra vigente: essas cinco imagens difíceis permanecem como
erro conhecido; não se compra outra rodada nesse conjunto. Qualquer calibração
futura usa imagens novas/holdout e orçamento explícito.

A Edge Function e o avaliador usam essa mesma v7. Os testes de contrato,
consolidação e hash passaram em 21/08, e a sonda diária confirma que credenciais
e rota continuam disponíveis. A análise remota permanece habilitada na 1.1,
sempre depois do consentimento separado e com correção humana obrigatória.

### Meta de produto ≠ portão técnico

O portão técnico é 80%. A meta aspiracional de produto continua em 90%; abrir o
portão não apaga essa distância nem transforma sugestões em verdade automática.
Luna entra na 1.1 com confirmação humana; não estava ativa na 1.0 publicada.

## 4. App e loja

* Bundle: **`br.com.canario.ch3.app`** — este, e não `com.canario.app`
* Loja: **1.1 publicada**
* Repositório: **1.2 build 1 em desenvolvimento** no PR #16
* TestFlight: upload aceito pela Apple às 09:18 de 21/08; pacote em processamento
* App Review: **não enviado**
* Time: `67AYPRFZH8`
* Alvo mínimo: iOS 17

O Archive Release foi criado, validado, exportado e preservado no Organizer em
`~/Library/Developer/Xcode/Archives/2026-08-21/DataDrobe 1.1 (2) 09.15.xcarchive`.
O binário empacotado foi conferido: DataDrobe, bundle e versão corretos, Luna
`YES`, configuração do Supabase presente, `PrivacyInfo.xcprivacy` incluído e
assinatura válida. O App Store Connect aceitou o upload sem warning de pacote.

A identidade é conferida no CI a cada push por
`coletor/teste_identidade_do_app.py`, que exige que gerador, `project.pbxproj`,
`Info.plist` e os guias digam a mesma coisa. Isso existe porque bundle e versão
já divergiram **três vezes** sem ninguém ver.

**Adicionar uma tela:** crie o `.swift` e rode `python3 app/gerar_projeto.py`.

O manifesto `PrivacyInfo.xcprivacy` declara `NSPrivacyCollectedDataTypePhotosorVideos`.
Na 1.0 nenhuma foto saía do aparelho; no candidato 1.1 o `Config.xcconfig` local
liga `REMOTE_ANALYSIS_ENABLED = YES`. Depois de a pessoa confirmar a peça, um
alerta separado explica que somente a cópia reduzida e sem metadados segue via
Supabase para OpenAI, que o app não a armazena e que logs de abuso podem durar
até 30 dias. Recusar mantém o caminho manual. Tela Privacy, alerta, manifesto e
`FICHA_APP_STORE_1.1.md` dizem a mesma coisa.

O String Catalog inicial contém 150 chaves extraídas do app. Ainda não há
tradução PT-BR — a A16 mantém a interface pública em inglês —, mas telas novas
entram agora por uma infraestrutura única em vez de espalhar mais strings sem
catálogo.

## 5. Testes

* **239** testes Swift de lógica pura — rodam em macOS sem simulador (`cd app && swift test`)
* **27** suítes Python — rodam a cada push
* **7** testes de interface no alvo `CanarioUITests`; cinco rotas offline rodam no CI

O gerador é dono do alvo de UI test e o CI o executa num iPhone 17 simulado.
Isso protege os caminhos estruturais enquanto as telas novas chegam sem
transformar o `project.pbxproj` em edição manual recorrente.

---

## O que está aberto

### Só o JP pode fazer

1. Aceite manual em aparelho: instalação limpa, câmera, fototeca, offline,
   links, modo escuro, Dynamic Type, VoiceOver
2. Decidir o número que separa "cobertura aceitável" de "dia inútil"

### Decisões de produto, sem prazo

Taxonomia `blusa_top` · fluxo semanal unificado de Trends e Search · curadoria
visual dos similares. Nenhuma é dívida técnica; são escopos não decididos, e só
entram na fila quando forem decididos.

### Técnico, em ordem de valor

1. **Alerta de "o pipeline nem começou"** — o alerta de falha existe desde
   19/08 (abre uma issue, agrupa noites seguidas, fecha sozinha no verde), mas
   ele roda no mesmo Mac que executa a coleta. Se a máquina estiver parada,
   ninguém é avisado. O certo seria um runner independente: medido em 19/08,
   `ubuntu-latest` **falha antes de começar** nesta conta, por bloqueio de
   billing. Sem gastar, a saída é algo fora do GitHub
2. **Artefato de cor na tela Add** — o feixe do topo deixou de pintar oliva
   sobre o fundo escuro em 19/08, mas o relato original era de algo **rosa**, e
   isso eu não consegui reproduzir: só há runtime iOS 26.2 nesta máquina, e o
   iPhone 15 com 18.7 usa o caminho de compatibilidade. Pode ter sido o mesmo
   defeito visto noutro renderizador, pode ser outro. Precisa de uma foto
3. **Loading de ~30 s ao importar peça no iPhone 15** — reduzido o que era
   reproduzível no Mac (242 → 241 ms), mas **a causa dos 30 s continua sem
   prova**. Precisa de medição no aparelho, não de mais otimização no escuro
4. Apagar as branches remotas já mescladas

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
| [`FICHA_APP_STORE_1.1.md`](FICHA_APP_STORE_1.1.md) | metadados do próximo beta |
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
