# Plano priorizado — feedback do JP, Davi, Bianca e teste externo

Data: **13/08/2026**. Este documento funde o placar anterior, a passagem do
Claude e toda a rodada de navegação do grupo. `CANARIO.md` continua sendo a lei
e `PENDENCIAS.md`, o placar curto.

## Decisões executivas

1. **Credibilidade vem antes de acabamento.** O app não atribui cor, tecido ou
   estética a uma mão/fundo quando não reconheceu nenhuma categoria de roupa.
2. **A v1 fica em inglês, uma língua por vez.** O caminho correto é String
   Catalog; trocar strings avulsas é apenas contenção até essa migração.
3. **iOS 26 usa navegação e Liquid Glass nativos.** A barra customizada fica
   apenas no fallback iOS 17–25. SF Pro já é a fonte do sistema quando nenhuma
   fonte customizada é declarada.
4. **Mudança estrutural de menu, fluxo e paleta passa por protótipo curto.** Há
   feedback conflitante sobre sidebar/esquerda e sheet/direita. Cinco pessoas
   executando tarefas num protótipo resolvem melhor que preferência individual.
5. **Marca reconhecida é contexto, não prova.** Um logotipo pode ajudar a achar
   o produto. Não prova modelo exato, fibra ou composição. Composição só vira
   fato quando vier da página/ficha do produto exato; caso contrário, `unknown`.
6. **Fontes internacionais adicionais ficam para depois da v1**, conforme
   decisão do JP nesta rodada. A coleta atual e a credibilidade temporal seguem
   prioritárias.

## Entregue neste primeiro pacote

- Tab Bar nativa no iOS 26 com Search semântico e minimização ao rolar; fallback
  existente preservado no iOS 17–25.
- Safe area passa a pertencer à TabView nativa; a barra deixa de cobrir o último
  card.
- Ações usam cor semântica do sistema em vez do azul escuro fixo no modo escuro.
- “no normal” virou “dentro do normal”.
- Acentos de apresentação corrigidos sem migrar ids históricos: Calça, Macacão,
  Geométrica e étnica, Algodão, Tricô e crochê, Romântico, Lilás e roxo e Maria
  Filó.
- Formulário condicionado à categoria: casaco/jaqueta não recebe cintura,
  silhueta ou comprimento de vestido; calça recebe cintura e silhueta; vestido
  recebe comprimento.
- Sem categoria reconhecida, a foto não pré-marca atributos. Isso fecha o caso
  da mão que virou “verde, romântico e algodão”.
- OCR local pode registrar texto de marca como contexto, sem outra API e sem
  enviar a foto para fora do aparelho.
- Teclado do preço pode ser dispensado por gesto e botão Done.
- Save usa gaveta/arquivo (`archivebox`).
- Produto explicitamente esgotado não entra na vitrine de similares.
- Feedback “None of these looks like my item” fica persistido localmente e pode
  ser revisto.
- Troca de foto saiu do card quando a peça já tem imagem e foi para o detalhe;
  o card conserva apenas Add photo para itens legados sem foto.
- Closet ganhou renomear e favoritar no menu de contexto; alvo do coração tem
  44×44 pt; card segue 250 pt de altura e limita a peça a 150 pt.
- Gráfico por fonte ganhou eixo de data, janelas 3M/6M/1Y e só compara semanas
  comuns, sem fabricar continuação para fonte ausente.
- Rótulos técnicos corrigidos nas telas de Trends, Search, relatório e Closet.

## P0 — corrigir antes de ampliar escopo

| id | Problema consolidado | Ação e aceite |
|---|---|---|
| P0.1 | App misto PT/EN, ortografia e hifens excessivos | Criar String Catalog, inglês como development language, varrer 100% das strings e revisar por humano. Zero tela bilíngue; nomes próprios e acentos corretos; datas no locale escolhido. Preferir frases diretas e pontuação natural, sem proibir hífen quando ele faz parte de uma palavra correta. |
| P0.2 | Foto sem roupa recebe atributos plausíveis | Manter portão de categoria já implementado; na rota Luna exigir `target_visibility`, categoria e confiança/calibração. Testes negativos com mão, ambiente, sapato e múltiplas peças. Nenhum atributo automático se o alvo for ausente/ambíguo. |
| P0.3 | Similares dispersos, links ruins e produtos esgotados | Auditar Hering, C&A, Farm, Zinzane, Cantão, Animale, PatBo e Dress To. Excluir esgotado já foi feito na apresentação; validar URL final e domínio, penalizar divergência de categoria/cor, diversificar por marca e não ordenar por maior desconto. Aceite cego: pelo menos 80% dos três primeiros julgados realmente similares e 100% dos links abrem produto comprável. |
| P0.4 | Google Trends/estado/frescor ainda causam desconfiança | Não transformar nulo em estável. Concluir NQ1/NQ18: mostrar fonte faltante e última tentativa, medir por que editorial BR não chega à mesma semana, construir série editorial a partir do banco e manter circuit breaker. “Sem direção confirmada” substitui “Sem estado” depois da migração de idioma. |
| P0.5 | Editorial tem falso positivo e exemplos antigos | Executar amostra cega de 100 matches; precisão ≥95% e recall ≥90%; reprocessar histórico somente depois. Preview de notícia deve mostrar veículo, data, manchete, imagem autorizada quando houver e trecho curto, nunca artigo incidental como Vini “camisa 7”. |
| P0.6 | Gráficos terminam em datas diferentes e não têm controle | Primeira correção entregue: janela e semanas comuns. Próximo: gesto de seleção/tooltip, data mais recente por fonte e teste de VoiceOver. Nunca preencher lacuna para fazer as linhas “chegarem juntas”. |

## P1 — fluxo e telas que vendem a proposta

| id | Problema consolidado | Ação e aceite |
|---|---|---|
| P1.1 | Fluxo Add não comunica mudança e “formulário → análise → guardar” é confuso | Prototipar: Home → captura/instruções → analysing progress → confirmação da peça/atributos → relatório → Save to Closet. A pessoa precisa dizer em teste que percebeu cada mudança de estado. Botão principal sempre descreve o próximo passo. |
| P1.2 | Formulário parece tela nativa genérica e não há instruções | Aplicar design do app sobre controles nativos, manter Dynamic Type/44 pt e teclado corrigido. Tela de instruções: uma peça por foto, bom contraste, peça inteira, evitar conjunto; explicar que confirmação humana prevalece. |
| P1.3 | Clothing DNA/relatório e detalhe não têm design final | Reconciliar Figma com os dados reais: foto, nome/categoria, leitura combinada, histórico, similares e fontes. Métrica técnica e metodologia entram por `info`, sem remover auditabilidade. “Clothing DNA” só fica se o conteúdo justificar o nome; não prometer medida física nem composição visual. |
| P1.4 | Analytics e Search parecem produtos separados | Transformar Trends na casa principal: “This week in fashion”, busca fixa, filtros por categoria/estado/recência, feed em alta/dentro do normal/em queda, toque para relatório. Search nativo pode ser aba semântica que filtra o mesmo modelo, não outro banco de resultados. |
| P1.5 | Menu/sidebar/paleta têm feedback conflitante | Protótipo A: ellipsis esquerdo + sidebar atual. Protótipo B: menu direito + sheet de configurações inspirado em apps iOS. Testar descoberta de Favorites, Privacy e Settings com cinco pessoas. Paleta recebe duas variantes com contraste WCAG/Apple verificado; não trocar pelo voto isolado de uma pessoa. |
| P1.6 | Compare está mal localizado | Testar Compare como ação no Closet (toolbar e seleção de duas peças) e como menu contextual. Aceite: três pessoas encontram sem instrução. Não voltar a termos soltos sem objeto. |
| P1.7 | Botões/touch targets e SF Pro | Auditoria de acessibilidade: mínimo interno de 44×44 pt, controles nativos quando equivalentes, Dynamic Type, VoiceOver, Reduce Transparency e contraste claro/escuro. SF Pro é obtida por `.system`; pesos seguem hierarquia, não arquivos de fonte incorporados. |
| P1.8 | Tab Bar não se comportava como Apple Music | Implementação nativa entregue no iOS 26 com `.tabBarMinimizeBehavior(.onScrollDown)`. Testar re-seleção da aba: voltar ao topo/ativar busca conforme convenção nativa. |

## P1 — Closet e imagem limpa

| id | Problema consolidado | Ação e aceite |
|---|---|---|
| P1.9 | Card do Closet, coração e troca de foto | Medidas do Figma aplicadas como limite responsivo; coração 44 pt sem cobrir a área útil; troca de foto movida ao detalhe. Conferir em iPhones compactos e Max. |
| P1.10 | Context menu pobre | Renomear e favoritar entregues. Próximos: ShareLink e Replace photo no detalhe. Drag/reorder exige campo de ordem local e teste de migração; fazer depois do fluxo principal. |
| P1.11 | Home/Closet precisam apenas da peça, sem fundo | Manter recorte Vision local A19 com fallback seguro. Rodar ensaio de 24 fotos reais (produto isolado, cabide, modelo e conjunto); medir sucesso e oferecer recorte/troca manual. Não remover partes da roupa para “limpar” a qualquer custo. |
| P1.12 | Imagens remotas com fundo/texto | Escolher primeiro a melhor URL autorizada da própria loja. Segmentação somente em memória e medida em latência/qualidade; hotlink não pode virar cópia permanente. |

## P1 — visão, marca e composição

### Matriz de opções

| rota | custo/privacidade | capacidade real | decisão |
|---|---|---|---|
| OCR + Vision local já existente | sem custo de API; foto não sai do iPhone | texto de marca/título e máscara; não reconhece todo logotipo estilizado | **Baseline obrigatório**, já iniciado |
| OpenAI Luna | paga por uso; envio já autorizado por A15, via Edge Function | categoria, cor, estrutura e texto controlado | **Rota principal após portão 24→300** |
| Google Cloud Vision Logo/Label/Web Detection | primeira faixa mensal gratuita por feature, mas exige billing e envia imagem ao Google | logo popular, rótulos gerais e entidades/web; não garante SKU nem composição | **Experimento pareado, fora do runtime por enquanto** |
| SerpApi/SearchAPI/Oxylabs/Scrapingdog | wrappers comerciais de busca/scraping; retenção e termos variam | podem reproduzir resultados tipo Lens | **Não usar no runtime de fotos privadas antes de prova jurídica, privacidade e ganho medido** |

### Avaliação que decide, sem opinião

1. Conjunto de pelo menos 100 fotos com marca/modelo conhecidos, incluindo
   logotipo ausente, parcial e falso amigo.
2. Braço A: Luna com imagem. Braço B: OCR local + Luna. Braço C: Cloud Vision
   Logo/Web + Luna, sempre com as mesmas imagens e prompt.
3. Medir categoria, cor, marca, produto exato e taxa de abstenção. Composição é
   avaliada separadamente e só conta quando existe ficha oficial do produto.
4. Adotar enriquecimento apenas se melhorar o holdout com significância prática
   e sem piorar privacidade/latência. Cloud Vision nunca recebe chave no app;
   passaria por backend e exigiria disclosure próprio.

O half-zip Patagonia ilustra o limite: ler “Patagonia” e “casaco” estreita a
busca, mas existem muitos half-zips da marca com composições diferentes. Sem
SKU/página oficial, o relatório deve dizer que o material não foi confirmado.

## P2 — curadoria depois dos bloqueadores

| id | Problema consolidado | Ação e aceite |
|---|---|---|
| P2.1 | `blusa_top`, camiseta e taxonomia pouco refinada | Construir matriz de confusão humana+Luna e volumes. Candidatos: camisa (construção de camisaria), camiseta (malha, formato T/pull-on), blusa (superior não camiseta) e top (definição visual a provar). Só separar com concordância, série e migração; não criar classe porque o nome agrada. |
| P2.2 | Categorias adicionais como cintura alta | Cintura alta já existe; o problema era aparecer sem pertinência. Auditar cintura baixa, camiseta e outros candidatos pelo teste triplo do §10. Campos dependem da categoria. |
| P2.3 | Mais marcas e mais curadoria | Expandir somente com teste de acesso, termos/robots, estabilidade por sete dias, papel/fatia e ganho de cobertura. Fontes internacionais novas foram adiadas pelo JP para depois da v1. Corrigir curadoria das nove atuais antes de aumentar o contador. |
| P2.4 | “Se usam menos calça, o que usam mais?” | Criar módulo de substituição por co-movimento entre categorias, mesma janela e fontes comparáveis. Mostrar “subiu enquanto calça caiu”, nunca causalidade ou troca de consumo sem dado. Exige cobertura temporal suficiente. |
| P2.5 | Notícias precisam parecer notícias | Card com hierarquia editorial, veículo, data, imagem/licença e preview; inspiração em apps de notícia, mas conteúdo e link continuam na origem. |
| P2.6 | Exportar/compartilhar | Reproduzir erro de exportação, adicionar ShareLink ao detalhe e snapshot somente dos fatos exibidos. Nunca exportar resposta bruta da IA como relatório final. |

## Itens deliberadamente não feitos agora

- **Trocar menu/paleta por preferência isolada:** seria retrabalho diante de
  feedback conflitante. Vai para o protótipo comparativo.
- **Adivinhar composição pela foto ou pelo logo:** prejudicial à confiança.
- **Preencher pontos ausentes no gráfico:** faria fontes incompletas parecerem
  atualizadas.
- **Adicionar categorias sem série e acordo humano:** fragmentaria cobertura e
  poderia piorar a leitura.
- **Integrar um scraper de Google Lens com fotos privadas:** risco de termos,
  retenção e operação sem ganho ainda demonstrado.
- **Novas fontes internacionais nesta fase:** adiadas pelo JP; a matriz existente
  permanece como pesquisa para v1.1.

## Ordem das próximas entregas

1. Finalizar String Catalog inglês, acessibilidade e auditoria dark mode.
2. Validar/limpar similares e links; melhorar ranking por similaridade real.
3. Repetir as 24 da Luna com o prompt/gabarito v3; abrir 300 somente com ≥20/24
   em categoria e cor primária.
4. Protótipo de uma semana para fluxo Add, Trends/Search, menu e paleta.
5. Implementar as telas aprovadas e o relatório final.
6. Fechar frescor editorial/Trends e então expandir curadoria/marcas.

## Prova desta etapa

- `swift test`: **142 testes, 0 falhas**, incluindo OCR local de marca,
  formulário condicionado, rejeição de similares e produto esgotado.
- `xcodebuild` completo no simulador iOS 26.2: **BUILD SUCCEEDED**.
- Device do JP: abertura muito mais rápida; leve gargalo apenas no primeiro
  cold launch, demais aberturas consideradas adequadas. Performance deixa de
  bloquear produto, mas cold launch continua instrumentável.
