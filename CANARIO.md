# CANÁRIO — Documento Base do Projeto

**Versão:** 1.0 | **Data:** 23/07/2026 | **Autores:** João Pedro (JP), Davi e Bianca, com consultoria de pesquisa e estruturação via Claude
**Status:** especificação ativa. Este documento é a fonte da verdade do projeto. O agente (Claude Code) trata tudo aqui como lei; o que não estiver aqui, pergunta antes de assumir.
**Codinome:** "Canário" é provisório. Usar sempre como token isolado (nome do projeto, do diretório, do target, bundle id `br.com.canario.ch3.app`), nunca embutido em frases de texto de interface, para que a troca pelo nome definitivo seja uma operação única de find-and-replace.

---

## PARTE 0 — LEIA PRIMEIRO

### 1. Regras invioláveis

Estas regras vencem qualquer outra instrução, inclusive futuras, salvo revogação explícita registrada no changelog.

1. **Nunca prever vendas.** Nenhum número, frase, score ou texto de interface pode afirmar ou sugerir quanto uma peça vai vender, probabilidade ou chance de sucesso, nem recomendar volume ou quantidade a produzir.
2. **Nunca inventar dado.** Lacuna vira nulo declarado na tela ("sem dado para este recorte"), nunca valor plausível. Todo dado fictício usado em desenvolvimento deve estar visualmente marcado como fictício na interface e listado no arquivo `DADOS_FICTICIOS.md` na raiz do repositório.
3. **Toda afirmação é rastreável.** Cada número exibido carrega link da página de origem e timestamp de coleta, acessíveis pelo usuário.
4. **O motor só usa taxonomia aprovada.** Linhas com `status` diferente de `aprovado` no arquivo de taxonomia não entram em coleta, índice ou tela.
5. **Painel congelado, usuário não escolhe marcas.** A composição do painel de medição só muda na virada de temporada. Painel instável corrompe o z-score.
6. **Cobertura mínima ou silêncio honesto.** Célula (termo x segmento x semana) abaixo dos mínimos exibe "cobertura insuficiente", nunca um número.
7. **Etiqueta de coleta.** ~~Máximo 1 requisição por segundo por domínio~~ **Máximo 1 requisição por segundo GLOBAL, marcas em série, nunca em paralelo** `[EMENDA ADITIVA 24/07/2026: o teto de requisições é por IP, não por domínio, e todo o painel de varejo está atrás da mesma infraestrutura compartilhada da VTEX — vários domínios em paralelo chegam lá como um cliente só e tomam 429. No ritmo global, dezenas de milhares de produtos paginam em bem menos que a janela da madrugada; não há pressão de cronograma que justifique paralelismo. A regra original valia por domínio; agora vale para a soma.]`, coleta de madrugada (horário de Brasília), cache agressivo, só páginas públicas, robots.txt respeitado, User-Agent identificável (`CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)`). Nunca burlar autenticação ou proteção anti-bot.
8. ~~**A foto da peça nunca sai do dispositivo.** Processamento de imagem on-device. Nuvem só como opt-in explícito e está fora da v1.~~ `[REVOGADO em 10/08/2026 por A15: a foto escolhida pelo usuário poderá ser enviada à API da OpenAI para pré-preencher os atributos. O envio precisa ser declarado antes da ação; OCR, cor local e formulário manual permanecem como fallback. Retenção zero não pode mais ser prometida.]`
9. **Segredos nunca no repositório.** Chaves e tokens vivem em GitHub Secrets (coletores) e na configuração local (app). Commit com segredo é incidente: rotacionar a chave imediatamente.
10. **Servidor calcula, app consulta, ~~câmera fica local~~.** O app nunca coleta nem computa índice; ele lê séries prontas. `[REVOGADO PARCIALMENTE em 10/08/2026 por A15: índices e métricas continuam exclusivamente no servidor do Canário; a imagem passa por uma Supabase Edge Function que guarda a chave e chama a OpenAI. A chave nunca entra no app.]`
11. **Decisão revogada nunca é apagada.** Recebe a marca `[REVOGADO em data: motivo, substituída por X]` e permanece no documento, para o agente não ressuscitar ideias enterradas.
12. **Conflito ou ambiguidade: parar e perguntar.** Nunca resolver contradição em silêncio.
13. **Nenhum serviço pago.** Nada de assinar, instalar ou configurar serviço com custo sem autorização explícita do JP por escrito.

### 2. Tarefa zero do agente

Antes de escrever qualquer linha de código: ler este documento inteiro e os anexos, e gerar o arquivo `AUDITORIA_INICIAL.md` listando (a) ambiguidades, (b) contradições entre seções, (c) decisões que o documento exige mas não fornece, (d) perguntas. Aguardar as respostas do JP antes de iniciar a Fase 1. Se a lista voltar vazia, declarar isso explicitamente.

### 3. Protocolo de mudança e revogação

O documento evolui por edições **aditivas** ou **revogatórias**, inclusive emergenciais (por exemplo, um pivô durante a incorporação do design).

- Toda mudança entra no changelog (seção final) com data e classificação `ADITIVA` ou `REVOGATÓRIA`.
- Revogação nunca deleta o texto original: aplica a marca da regra 11.
- Antes de incorporar qualquer pivô, o agente cria um checkpoint no git (tag `pre-mudanca-AAAAMMDD`) e apresenta um resumo de impacto: quais módulos a mudança toca, o que quebra, o que precisa ser refeito. Só executa após aprovação do JP.
- Conflito entre uma mudança nova e uma regra inviolável: parar e perguntar.

### 4. Regras de engajamento do agente

- Commits pequenos, frequentes e com mensagem descritiva em português.
- Não refatorar código que funciona sem pedido explícito.
- Perguntar antes de qualquer operação destrutiva (drop de tabela, força de push, deleção de dados coletados, reset de branch).
- O acesso ao computador do JP é total, mas o escopo é este projeto. Não tocar em arquivos, contas ou configurações fora do repositório e das contas do projeto.
- Preferir sempre a solução mais simples que cumpre o critério de aceitação. Este documento já contém decisões suficientes; sofisticação extra sem pedido é desvio.
- Ao final de cada fase (seção 33), gerar um resumo em português simples do que foi feito, do que ficou pendente e de como o JP pode verificar com os próprios olhos.

---

## PARTE 1 — O PRODUTO

### 5. Missão

O Canário mede o mercado de moda brasileiro e entrega evidência organizada, rastreável e imediata para quem decide coleção, compra e reposição. Ele informa a decisão; nunca decide, nunca prevê.

### 6. O que o produto não é (Won't Have permanente)

- Nenhum algoritmo de previsão de vendas. `[Decisão de origem do time, reafirmada múltiplas vezes]`
- Nenhuma probabilidade, score ou "chance de sucesso" de peça.
- Nenhuma recomendação de volume ou quantidade a produzir.
- Nenhum veredito absoluto sobre peça ("vai vender bem", "não vai vender").

**Substitutos aprovados** (o que o app entrega no lugar): ranking relativo entre as peças do próprio usuário; composição de grade de tamanhos (redistribuição, soma zero, nunca volume); análogos descritivos ("as 3 peças mais parecidas e o desfecho delas"); frases condicionais a partir de contexto opcional ("seu preço-alvo está no percentil 78 dos similares"); percentil de preço; índice de aquecimento de atributo com fórmula pública.

**Lista negra de vocabulário** em qualquer texto de interface, template ou relatório: prever, previsão, vender, venda futura, sucesso, chance, probabilidade, potencial de venda, recomendamos produzir, deve produzir, vai vender. O agente deve implementar um teste automatizado que varre os textos da interface contra esta lista.

### 7. Personas e usuário primário

- **Usuário primário:** Grupo Azzas 2154 e suas marcas, principalmente femininas (cliente-modelo: Maria Filó; referência de processo: Farm). Dentro da empresa, o alvo é o time **comercial**, que trabalha com dado e age depois do estilo. O time de estilo é resistente a informação externa (subjetivo, movido a desejo e DNA de marca) e não é alvo da v1. Contatos: Pedro Moreira, Lorena, Victor Lemos.
- **Persona secundária:** o empreendedor pequeno de moda, que toma as mesmas decisões sem ter time de dados, WGSN ou algoritmo interno. É o canal de validação mais rápido do projeto.
- Em conflito de design entre as duas personas, otimizar para o usuário primário.

### 8. Recorte da v1 e cobertura declarada

- O app é **unissex e multissegmento por arquitetura**: qualquer segmento novo é apenas uma lista de marcas nova no painel.
- A **v1 é profunda em um segmento só: moda feminina casual/social brasileira**, faixa de preço mid-market (o mundo da Maria Filó).
- **Mínimos de cobertura por segmento:** pelo menos 8 marcas ativas coletando e pelo menos 30 peças na célula (termo x segmento) na semana. Abaixo disso, a interface exibe "cobertura insuficiente neste segmento" e oferece apenas o que existe com honestidade (similares encontrados, faixa de preço), sem índice e sem estado.
- **Mínimo de tempo por série:** nenhuma série exibe z-score com menos de 8 semanas de história. O índice composto só combina as fontes (pernas) que atingiram o mínimo, e a interface declara quais pernas sustentam cada número ("baseado em: busca + editorial"). Consequência esperada: no início, busca (5 anos de história via Trends) e editorial (backfill de arquivo) ficam ativas antes da perna de varejo, que nasce do zero.

### 9. Critério de sucesso do projeto

1. Um varejista de moda (cliente-modelo ou não) confirmar que usaria o app em um momento real de decisão da marca dele.
2. Achados verificáveis: o usuário clica na origem, confere por conta própria, e o dado está certo.
3. Autossuficiência: coletores rodando sozinhos, sem intervenção manual recorrente do time.
4. A demo roda com dado real coletado pelo próprio sistema, nunca com dado semente.

Quando o agente precisar escolher entre alternativas, otimiza para estes quatro pontos, nessa ordem.

### 10. Marcos de demo (alvos de otimização)

A apresentação (Mostra) deve ser capaz de computar, com dado real:

1. **Curva de tamanhos do efeito Ozempic:** a quebra de grade pendendo à esquerda (PP/P esgotando, G sobrando), medida semana a semana no painel, por categoria. É a dor que o cliente relatou em entrevista, devolvida quantificada.
2. **Divergência oferta x demanda:** quanto as marcas do painel reduzem a oferta de um atributo fora de estação versus quanto a busca por ele realmente cai.
3. **Consulta ao vivo "verde e lilás no masculino":** funciona como demonstração de honestidade do sistema: as pernas de busca e editorial respondem (o tema está documentado na imprensa de moda), e a perna de varejo exibe "cobertura insuficiente" porque o segmento masculino não está no painel v1. O app mostrando o próprio limite é parte do pitch. `[REVISADO em 28/07/2026, decisão do JP: o marco 3 passa a ser DUAS consultas ao vivo. Primeiro a feminina ("verde e lilás"), com todas as pernas ativas, mostrando a capacidade cheia; depois a masculina, em que o app declara o próprio limite de forma inequívoca. Motivo: o` termo_busca `de` verde `e` lilas_roxo `é` vestido verde `/` vestido lilas`, ancorado em moda feminina — a perna de busca também não responde à pergunta do masculino, e a demo mostraria duas pernas vazias, o que lê como defeito e não como honestidade. Proposta do agente, aguardando o JP: fazer DUAS consultas ao vivo em vez de uma — primeiro a feminina ("verde e lilás", com todas as pernas ativas), mostrando a capacidade cheia; depois a masculina, em que o app declara o próprio limite de forma inequívoca. Preserva a demonstração de honestidade, que era o ponto do marco, e ainda mostra o produto funcionando. A alternativa (variantes masculinas na taxonomia) contradiz o recorte da v1 de §8.]`
4. **Roteiro:** o cliente (por exemplo, Lorena) digita a busca ao vivo. Nada de exemplo pré-cozido. Narrativa ancorada no calendário real da coleção Alto Verão 28 da Farm: desenvolvimento de estampa iniciando 07/ago/26, aprovação de visual 19/jan/27, provão 16/mar/27, mostruário a partir de 05/fev/27, venda atacado 25/jun/27, lançamento 06/out/27, lead time total 341 dias. O app entra na janela do comercial: entre aprovação de visual, provão e mostruário.

Consequência do calendário: o ciclo completo da AV28 não fecha dentro do Academy. A validação do índice é **retroativa** (seção 31), e a AV28 serve como acompanhamento ao vivo, não como prova.

---

## PARTE 2 — DADOS E CONHECIMENTO

### 11. Taxonomia (o vocabulário comum do sistema)

A taxonomia é uma ~~**lista fechada de 35 termos** organizados em 6 dimensões~~ **lista fechada de 41 termos organizados em 8 dimensões** `[REVISADO em 28/07/2026: 35→41 termos e 6→8 dimensões. C2 (23/07) dividiu `modelagem` em `comprimento` e `silhueta` sem mexer na contagem; a revisão de 28/07 acrescentou `macacao`, `xadrez`, `cintura_alta` (em dimensão `cintura` própria), `cinza`, `amarelo_laranja` e o residual `outras_cores`. Nenhum id original foi alterado ou removido.]`. Ela é o contrato entre a foto, a busca, o Trends, o coletor e o motor. Vive no arquivo `anexos/taxonomia.csv`, versionado no repositório.

**Regras:**
- **Teste triplo de admissão:** um termo só existe se for (a) visível numa foto de produto, (b) buscável com volume detectável no Google Trends Brasil, (c) escrito em títulos/descrições de produto nos sites do painel. Falhou em um, não entra.
- **Exclusividade intra-dimensão:** dentro da mesma dimensão, os termos são mutuamente exclusivos na medida do possível (uma peça é midi OU longa).
- **Categoria é filtro, não sinal.** "Vestido em alta" não significa nada; "floral em alta dentro de vestidos" significa.
- **Campos por termo:** `id` (estável, nunca muda), `rotulo` (exibição), `dimensao`, `sinonimos` (separados por `|`; é aqui que "floral" e "estampa floral" viram a mesma coisa), `termo_busca` (query exata do Trends), `palavras_pt` e `palavras_en` (matching em título/texto; PT e EN porque a mídia BR usa inglês solto e os veículos internacionais são monitorados), `exemplo` (descrição curta de referência), `status` (`proposto` | `aprovado` | `reprovado`).
- **Fluxo de aprovação:** o agente propõe preenchimentos e novos sinônimos sempre com `status=proposto`. Só o JP muda status para `aprovado`. O motor ignora tudo que não for `aprovado` (regra inviolável 4).
- **Contagem única:** em texto editorial, um artigo conta no máximo uma vez por termo, mesmo que várias palavras-chave do termo apareçam ("manga bufante" e "puff sleeve" no mesmo artigo = 1).
- **Tradução string → atributos:** a barra de busca do app nunca vira filtro de texto cru. A string do usuário é traduzida para termos da taxonomia via rótulos e sinônimos; o que não casar com a taxonomia gera resposta honesta ("não acompanho este termo ainda") com sugestão dos termos próximos.

### 12. Fontes: medição versus direção

| Fonte | Tipo | Papel | História no dia 1 | Status |
|---|---|---|---|---|
| Coletor de varejo próprio (painel de marcas) | Medição | Grade, reposição, remarcação, preço, composição, novidades | Zero (nasce do zero; urgência máxima) | Pilar |
| Google Trends BR | Medição de demanda de busca | Aquecimento por termo, sazonalidade | 5 anos via backfill | Pilar |
| Veículos editoriais via RSS/feed | Direção | Share of voice editorial por termo | Anos, via backfill de arquivo | Pilar |
| Lyst (conteúdo público de tendência) | Direção com base em comportamento | Tendência macro global | Conforme publicação | Slot próprio; público global de luxo/streetwear, serve a macro, não calibra mid-market BR |
| Referências internas (planilha do cliente) | Medição interna opcional | Análogos, baseline, autocalibração | Depende do cliente | Opcional, local no dispositivo |

**Fora da v1, com motivo registrado (não ressuscitar):**
- Mercado Livre `[REVOGADO: representatividade; o público de moda do ML não é o do segmento-alvo]`.
- Shein, Zara, Renner e Nike por coleta direta `[REVOGADO: hostilidade anti-bot; entram apenas indiretamente via multimarca, se o multimarca passar no teste]`.
- Instagram `[REVOGADO para v1: exigiria app review da Meta, processo de semanas que o time decidiu não fazer; o sinal de influenciador chega de segunda mão pela cobertura editorial, com perda de resolução assumida]`.
- TikTok `[REVOGado para v1: Research API é acadêmica e proíbe uso comercial; Creative Center não tem API; entrada manual rejeitada pelo time em nome da autossuficiência]`.
- Automação de Instagram via plataforma de terceiros com credenciais (base44 ou similar) `[REVOGADO: risco de segurança e de conta; nunca entregar senha nem desligar segundo fator]`.
- Pantone / cor do ano `[REVOGADO como fonte: opinião editorial; cor é medida por dominância de sortimento e velocidade de esgotamento no painel]`.

### 13. Painel de marcas (medição)

Vive em `anexos/painel_marcas.csv`. Regras:

- **Composição inicial (v0):** a do anexo. **Composição final:** quem passar no teste dos 30 segundos (seção 17). Alvo: 15 a 25 marcas no segmento v1.
- **Papéis:** `nucleo` (concorrentes diretos), `adjacente` (um degrau de preço acima/abaixo), `ancora` (volume/massa), `multimarca`, `grupo` (marcas do próprio Azzas), `direcao`.
- ~~**Multimarca é multiplicador com ressalva:** a ruptura num multimarca fala da compra daquele lojista, não da demanda total da marca. Vale como comparação relativa entre marcas dentro da mesma vitrine (mesmo público, mesmo tráfego). Etiquetar os dados com origem multimarca e nunca misturar com leitura de site próprio sem distinção.~~ `[REVOGADO PARA A v1 em 24/07/2026: nenhum dos 4 multimarcas passou no teste dos 30 segundos — Dafiti e Shop2gether não expõem catálogo nos caminhos testados, Iguatemi 365 não resolve no `.com.br`, Centauro dá 403. O multiplicador de cobertura por multimarca não existe na v1 e a ressalva de leitura relativa dentro da mesma vitrine perde o objeto até segunda ordem. Reversível: se o pente fino (§36.7 / instruções de 24/07) recuperar algum multimarca, esta revogação cai com nova entrada no changelog.]`
- **Marcas do grupo Azzas** (Farm, Animale, Maria Filó, Fábula, NV, Foxton) entram com papel `grupo`: são autobenchmark para o cliente, nunca contam como "mercado externo" nos índices.
- **Painel de direção** (Misci, Zimmermann, Ganni, Réalisation Par, Sézane, Dôen, calendários de passarela): sem bot de estoque. O sinal é frequência de atributo no que publicam. Estoque de grife é escassez deliberada, não demanda.
- Cada marca tem uma linha de justificativa escrita (coluna própria). É a resposta pronta para "por que essas marcas?".
- Congelamento por temporada (regra inviolável 5). Marca nova entra com história zero e fica fora das comparações até acumular o mínimo de semanas.

### 14. Veículos editoriais

Vivem em `anexos/veiculos.csv`. Critérios de permanência: publica no mínimo semanalmente, fala de produto e tendência (não só celebridade), tem arquivo com profundidade. Regra do time: **somente veículos famosos e confiáveis de moda**; a lista pode crescer, não encolher, e adições passam pelo JP. Viés a declarar nos insumos do relatório: veículo de moda vive de publicidade de marca, então o sinal editorial carrega inclinação comercial. Editorial é sempre **direção**, nunca medição.

### 15. Sazonalidade e calendário

- O motor **nunca armazena estação**; armazena semana e mês. Estação é etiqueta de exibição configurável por ~~conta~~ **ajuste local do dispositivo** `[ADITIVA 23/07/2026 por C1: "conta" não existe na v1 (§34 proíbe login), então lê-se "ajuste local do dispositivo" em toda a v1]`: preset `PV/OI` (primavera-verão / outono-inverno) e preset `Azzas` (verão, alto verão, inverno, alto inverno). O mapeamento oficial de meses para as sub-coleções do Azzas é pergunta aberta ao cliente (seção 36); até lá, usar aproximação declarada como aproximação.
- **Sazonalidade vem do Trends** (que tem 5 anos de história), nunca do bot de varejo (que nasce sem passado).
- **Oferta e demanda são medidas separadas:** oferta = presença do atributo no sortimento do painel; demanda = busca no Trends. A divergência entre as duas curvas é um insight de primeira classe, não um erro.

---

## PARTE 3 — COLETA

### 16. Prioridade física

Dado de ruptura não tem passado recuperável. Cada dia sem coletar é história perdida para sempre. Os coletores entram no ar antes de qualquer tela, e permanecem no ar mesmo durante refatorações (nunca derrubar a coleta para "arrumar depois").

### 17. Coletor de varejo

**Passo 1, teste dos 30 segundos (automatizável):** para cada domínio candidato do painel, testar:
- VTEX: `GET https://dominio/api/catalog_system/pub/products/search/vestido` (esperado: JSON com produtos e SKUs).
- Shopify: `GET https://dominio/products.json` (esperado: JSON com products).
Gravar em `painel_marcas.csv` a coluna `status_teste` (`vtex` | `shopify` | `falhou` | `pendente`) com data. Quem falhar fica fora da coleta v1 (sem headless browser, sem burlar proteção: regra inviolável 7).

**Passo 2, coleta diária** (madrugada BRT; atenção ao UTC do agendador): para cada marca aprovada, varrer o catálogo do segmento v1 e gravar snapshot por produto:
- Identificação: id externo, marca, URL, título, descrição, categoria do site, URL da imagem principal.
- Comercial: preço original, preço atual, composição do tecido quando publicada (capturar desde o primeiro respiro: barato de coletar agora, impossível de recuperar depois).
- Grade: disponibilidade por tamanho, por SKU. Quantidades expostas são referenciais; o que importa é disponível/indisponível.
- Derivados computados pelo motor, não pelo coletor: primeiro avistamento, eventos de reposição (indisponível → disponível persistente por 2+ snapshots, o debounce), eventos de remarcação (queda de preço, profundidade), saída de linha (produto some por N dias).
- Imagens: v1 armazena apenas a URL. Download em massa para o dataset de visão só quando a fase de visão começar, para não estourar armazenamento.

### 18. Coletor editorial

**Descoberta de feed por domínio, nesta ordem:** (1) tentar `/feed`, `/rss`, `/feed.xml`, `/rss.xml`, `/atom.xml`, `/index.xml`; (2) baixar a home e procurar `<link rel="alternate" type="application/rss+xml">` ou `atom+xml`; (3) testar `/wp-json/wp/v2/posts?per_page=10` (WordPress); (4) validar que cada item tem título, link e data (sem data, item inútil para série temporal). Consultar diretórios públicos de feeds (por exemplo, Feedspot) antes de adivinhar caminhos. Gravar em `veiculos.csv` a coluna `status_feed` com o método que funcionou e a data do item mais antigo acessível.

**Backfill:** onde houver `wp-json`, paginar com filtro de data e baixar o arquivo histórico (anos). É o que dá passado à perna editorial no dia 1.

**Coleta recorrente:** itens novos de cada veículo; casar título + resumo contra `palavras_pt` e `palavras_en` da taxonomia aprovada; gravar uma linha por (veículo, artigo, termo), com contagem única por termo por artigo.

**Proibição:** não armazenar o texto integral dos artigos (obra protegida e peso inútil). O texto pode ser processado em memória para contagem; persiste apenas título, link, data, veículo e contagens.

**Cadência de leitura:** a perna editorial trabalha em **janela móvel de 4 semanas** (volume editorial é baixo; semana crua é ruído). A perna de varejo trabalha em semana. São cadências diferentes no mesmo motor; não uniformizar.

### 19. Coletor de busca (Google Trends)

- **Caminho oficial:** candidatar o projeto ao alpha da API oficial do Google Trends (existe desde jul/2025, acesso por aplicação). Tarefa humana: o JP submete o formulário; o agente prepara o texto do caso de uso.
- **Enquanto o alpha não sai:** `pytrends` (não oficial, instável) com cache agressivo, retry com backoff exponencial e cadência semanal. Se quebrar de vez, último recurso: exportação manual de CSV do site do Trends, com o agente gerando a lista exata de consultas a fazer.
- **Backfill:** 5 anos por `termo_busca`, geo BR, na primeira execução.
- **Regra:** só consultar termos vindos da coluna `termo_busca` de linhas aprovadas da taxonomia. Guardar a série bruta com os metadados da consulta (intervalo, geo, data da coleta), porque valores do Trends são relativos à consulta; manter intervalo e âncora consistentes entre coletas.

### 20. Relatório de saúde diário (requisito de primeira classe)

O conjunto de coletores **não é considerado pronto** enquanto não gerar, todo dia:
- Itens coletados por fonte e por marca/veículo.
- Percentual de campos extraídos com sucesso (varejo: tamanho, preço, composição; editorial: título, data).
- Alerta quando qualquer fonte cair mais de 70% em relação à média dos 7 dias anteriores, e alerta imediato quando uma marca render zero.
O resultado é gravado no banco e num arquivo `SAUDE.md` commitado no repositório. Efeito colateral desejado: o commit diário mantém o repositório ativo e evita a desativação automática de workflows agendados por inatividade. Motivo de existência: coletor não quebra com erro na tela, quebra em silêncio, e a plataforma de agendamento não notifica falha.

---

## PARTE 4 — MOTOR

### 21. Séries e z-scores

- Unidade básica: série semanal por (termo, segmento, fonte). Varejo agrega os snapshots diários em métricas semanais; editorial usa janela móvel de 4 semanas; busca é semanal.
- **Z-score contra a própria história:** cada série é normalizada contra sua média e desvio numa janela móvel de 12 semanas. Mede-se mudança em relação ao próprio normal, não tamanho absoluto (é isso que neutraliza os clássicos e torna fontes comparáveis).
- **Mínimos:** nada de z-score com menos de 8 semanas de história (seção 8). O índice composto combina apenas pernas ativas e declara quais são.

### 22. Índices e estados

- **Índice do atributo** = média ponderada dos z-scores das fontes ativas. Pesos iguais na v1, declarados por escrito, fixados ANTES de olhar resultados (proteção contra curve fitting retórico).
- **Índice do cluster** (conjunto de atributos de uma peça) = média dos índices dos atributos ponderada por raridade: atributos raros no painel pesam mais (lógica IDF); "vestido" pesa pouco, "floral" pesa muito.
- **Estados semanais, sem duração no título:** `em alta` (índice ≥ +1 desvio por 2 semanas consecutivas E pelo menos 2 fontes concordando), `em queda` (espelho), `pico` (z de editorial ≥ +2,5 numa semana com as demais fontes neutras; evento pontual, morre rápido), `estável` (resto). Uma semana isolada nunca muda estado: é a regra anti-ruído.
- Limiares são chutes iniciais documentados; quem os corrige é o termômetro (seção 31), nunca ajuste ad hoc para "ficar bonito".

### 23. Leitura do sinal de varejo

- **Esgotado não é sucesso; é esgotado.** Não vemos profundidade de estoque. Usar dinâmica (velocidade de quebra, percentual da grade ao longo do tempo), nunca a foto de um dia.
- **Reposição vale mais que ruptura:** indisponível → disponível persistente por 2+ snapshots (debounce). É a marca votando com o próprio dinheiro.
- **Matriz preço x grade (4 leituras):** preço cheio + grade quebrando rápido = campeã (reposição posterior confirma); preço cheio + grade intacta por muito tempo = continuativo saudável OU peça parada (o flag desambigua); remarcada + grade quebrada = fim de ciclo normal; remarcada + grade cheia = encalhe (o fracasso mais claro que o método enxerga).
- **Flag continuativo x coleção:** heurísticas de classificação: reaparece entre temporadas, idade longa no ar, reposição frequente, categoria de básicos. Clássicos (camiseta lisa preta/branca, jeans básico) ficam fora dos rankings de ruptura e ganham leitura própria (preço e densidade de oferta, não aquecimento). O z-score já os neutraliza matematicamente (série chapada, desvio ~0); o flag torna isso visível e filtrável.
- **Novidades por cluster:** SKUs novos por atributo por semana = sinal de aposta da indústria (oferta antecedendo demanda).

### 24. Curva de tamanhos

Velocidade relativa de esgotamento por tamanho dentro do cluster no painel ("P esgota 1,9x mais rápido que G"), com o formato da quebra (à esquerda: PP/P; à direita: G/GG). Apresentação: curva observada do mercado ao lado de referência, em linguagem condicional. Ressalva obrigatória nos insumos: o público da marca do usuário não é o público médio do painel (modelagem e cliente próprios); é referência de mercado, não prescrição. Recomendação de composição de grade é permitida (soma zero); recomendação de volume, nunca (regra inviolável 1).

### 25. Cor

Cor é medida, não opinada: dominância no sortimento do painel (share de SKUs por família de cor dentro da categoria) e velocidade de esgotamento por cor. Pantone/cor do ano ficam fora (seção 12).

---

## PARTE 5 — O APP

### 26. Stack e alvo

SwiftUI, iOS 17 como mínimo, iPhone primeiro. ~~Idioma da interface: PT-BR apenas na v1.~~ `[REVOGADO em 10/08/2026 por A16, decisão do JP: a interface da v1 será em inglês. Nome definitivo segue aberto; candidatos atuais: Label/Labl e Stitched.]` Gráficos com Swift Charts. Dependências de terceiros: mínimas e justificadas uma a uma. Coletores em Python 3.11+ na pasta `/coletor` do mesmo repositório. Distribuição: TestFlight interno (time) e depois externo (Pedro, Lorena, Victor); ~~App Store não é obrigação do projeto~~ `[REVOGADO em 23/07/2026 por A6: publicação na App Store passa a ser requisito com data. O app precisa estar publicado em 24/08/2026, dia do Demo Day. Feature freeze 10/08, submissão até 13/08 para caber uma rejeição e uma ressubmissão. TestFlight continua sendo o canal das reuniões de progresso, que nunca esperam o review.]`

### 27. Estrutura em 3 abas

- **Analisar:** entrada por busca textual (principal) ou upload de foto (opcional). Três campos de contexto opcionais que nunca bloqueiam: preço-alvo (gera percentil contra similares), canal (varejo/atacado), janela de entrada em loja (gera leitura sazonal). Saída: o relatório da peça (seção 29).
- **Explorar:** valor de esforço zero na abertura. Blocos: ruptura da semana (clusters e marcas com mais quebra, excluindo continuativos), reposições da semana (destaque editorial: é o sinal mais forte), novidades por cluster, e o digest do que mudou. Filtros por segmento.
- **Comparar:** o usuário seleciona 2 a 6 peças analisadas e recebe ranking relativo imediato, com uma linha de motivo por peça (nunca só o número). Disclaimer fixo na tela: "Ranking relativo entre as suas peças, calculado agora sobre dados já coletados. Não é previsão de venda." Peça clássica aparece com badge e leitura própria (preço e oferta), avisando que aquecimento não se aplica. Salvar comparação é opcional e discreto.

**Estados vazios e de erro (obrigatórios):** cobertura insuficiente (mensagem honesta + o que dá para mostrar); coletor atrasado (exibir sempre a data/hora da última coleta junto aos números); offline (servir o cache da última sincronização com carimbo visível "dados de DD/MM HH:MM"); termo fora da taxonomia (resposta honesta + termos próximos).

**Vocabulário de interface:** estados sem duração no título (`em alta`, `estável`, `em queda`, `pico`; janelas de tempo vão para a letra miúda dos insumos). Palavras proibidas: a lista negra da seção 6, mais "provão" (não existe no produto), "atualizada hoje" e equivalentes que sugiram cultivo/espera.

### 28. Entrada por imagem e visão computacional

`[REVOGAÇÃO em 10/08/2026 por A15, decisão do JP: a v1 passa a usar a API da OpenAI no runtime. A imagem é reduzida e tem os metadados removidos no aparelho, segue para uma Supabase Edge Function e dali para o modelo gpt-5.6-luna. A saída principal é fechada nos ids da taxonomia; atributos visuais extras podem vir separados, mas não recebem índice nem métrica porque o painel não os mede. O formulário humano continua obrigatório. Antes de entrar no app, a rota precisa atingir pelo menos 80% em categoria e cor num conjunto rotulado; primeiro teste: 300 imagens no i7. OCR, cor local e marcação manual ficam como fallback.]`

`[REVOGAÇÃO PARCIALMENTE DESFEITA em 30/07/2026, decisão do JP: a ENTRADA POR ARQUIVO volta ao escopo da v1 — print, foto e PDF via seletor de documentos, SEM câmera. Cortar a câmera preserva os dois ganhos que motivaram o A7: nenhuma permissão de câmera ou fototeca, e ficha de privacidade da App Store trivial. Retenção ZERO por decisão do JP: o arquivo é exibido na sessão e descartado, nada é guardado. A aba "armário" que o time cogita para salvar peça permanece FORA da v1 pelo anti-escopo da §34 ("sem closet/monitoramento contínuo por peça") e exigiria entrada revogatória própria. A visão computacional treinada segue revogada; o que entra é leitura de TEXTO (OCR) do arquivo, reaproveitando o matcher que já converte título de produto em atributo.]` `[REVOGADO PARA A v1 em 23/07/2026 por A7: com 32 dias até o Demo Day, a entrada por foto e a visão computacional saem por completo. A entrada é só busca textual, que já era a principal por decisão de privacidade. Ganho colateral: sem permissão de câmera nem de fototeca, a ficha de privacidade da App Store fica trivial. Volta na v1.1 (A9), treinada com o dataset de imagens que o coletor terá acumulado até setembro. O texto abaixo permanece como especificação da v1.1.]`

- **Fluxo:** upload → tela de formulário onde o usuário confirma/corrige os atributos. O humano no circuito é o que derruba a exigência de acurácia da visão.
- **v0:** formulário primeiro; visão é conveniência de pré-preenchimento apenas se disponível e confiável.
- **Evolução:** dataset a partir das imagens do próprio coletor, rotuladas pelos títulos dos produtos (títulos de e-commerce são etiquetas quase prontas). Treinar classificador multirrótulo no Create ML. **Critério de aceitação para a visão poder pré-preencher:** concordância ≥ 80% com etiquetagem humana em categoria e cor, num conjunto de teste de 100 peças que o time rotula à mão.
- ~~**Privacidade:** processamento on-device (Vision/Core ML). A foto é processada e descartada; retenção zero por padrão (miniatura local opcional, apagável pelo usuário). Nada de nuvem na v1.~~ `[REVOGADO em 10/08/2026 por A15: o produto precisa declarar o envio à OpenAI e atualizar a ficha de privacidade. A requisição usa store=false, mas isso não equivale a retenção zero: a política padrão da API admite logs de monitoramento de abuso por até 30 dias. A imagem não é salva pelo Canário.]` Tags sempre editáveis.

### 29. Relatório da peça

Ordem dos blocos, de cima para baixo:
1. **Parágrafo-resumo por template determinístico, preservado como fallback.** Frases pré-escritas com slots preenchidos exclusivamente por valores computados pelo motor. Exemplo de template: "No painel de {n_marcas} marcas, encontrei {n_similares} similares: {pct_preco_cheio}% a preço cheio e {pct_grade_quebrada}% com grade quebrando {formato}. A busca por {termo} está {estado} ({variacao} em {janela})." ~~Proibido LLM na v1. `[LLM como redator com coleira: apenas v2]`~~ `[REVOGADO em 10/08/2026 por A15: o gpt-5.6-luna pode redigir o relatório na v1, recebendo somente fatos e números já computados. A chamada é separada da visão. Antes de exibir, um validador exige que todo número esteja no pacote-fonte, aplica a lista negra e mantém as fontes visíveis. Qualquer falha cai no template determinístico.]`
2. **Atributos da peça** (chips editáveis, com o índice individual de cada um).
3. **Índice do cluster + estado + minigráfico**, com as pernas ativas declaradas.
4. **Insumos, um bloco por fator:** sites/varejo (similares com preço, remarcação e estado da grade, sempre; N, faixa de preço, formato da quebra), sazonalidade (Trends, na etiqueta de estação da conta), cores, modelagem, composição. Cada bloco com fonte, data de coleta e link.
5. **Contexto condicional** (se o usuário preencheu): percentil de preço, leitura da janela de entrada.
6. **Limites declarados:** "Não consideramos: seu histórico de vendas, seus custos, sua capacidade de produção. Sinal editorial carrega viés comercial de publicidade."
Rastreabilidade (regra inviolável 3) em todos os números.

### 30. Referências internas (opcional, por cliente)

`[REVOGADO PARA A v1 em 23/07/2026 por A7: o cliente ainda não entregou dado nenhum e construir para dado que não existe é desperdício no prazo atual. Volta na v1.1 (A9). O texto abaixo permanece como especificação da v1.1.]`

- Template rígido, nunca documento livre: um arquivo com 1 linha por peça e 10 colunas: `ref, descricao, categoria, preco, qtd_comprada, pct_vendido_preco_cheio, semanas_em_loja, colecao, vendas_por_tamanho (opcional), foto (opcional)`. Duas coleções: a mesma estação do ano anterior (análogos diretos) e a estação oposta (controle que separa atributo sazonal de atributo estável).
- **Usos:** análogos no relatório ("as 3 peças mais parecidas da sua coleção passada e o desfecho delas"), baseline por categoria da própria marca, e autocalibração por cliente (correlação entre o índice externo e o desempenho interno, exibida com honestidade).
- **Privacidade e escopo:** o arquivo é importado, processado e armazenado **localmente no dispositivo**. Não sobe ao servidor na v1 (não existe conta de usuário; seção 34). Multi-dispositivo fica para depois.

### 31. Validação retroativa (o termômetro)

Como o ciclo real do cliente (341 dias) não fecha dentro do Academy, o índice é validado contra o passado:
- Obter do cliente uma coleção antiga já lançada, com desfecho conhecido (pergunta aberta, seção 36).
- **Protocolo anti-vazamento:** congelar a data de decisão daquela coleção; computar o índice usando somente informação que existia naquela data. As pernas com passado real (Trends, 5 anos; editorial, backfill) tornam isso possível mesmo sem história de varejo.
- Medir: o ordenamento do índice contra `pct_vendido_preco_cheio` real das peças; reportar acerto de ordenamento, erro e viés, por categoria.
- Os limiares da seção 22 são recalibrados a partir daqui, com registro no changelog.

### 32. Acessibilidade

Dynamic Type respeitado, rótulos de VoiceOver em todos os números/estados/gráficos, contraste adequado nos dois modos, e estados nunca comunicados só por cor (sempre ícone ou texto junto).

---

## PARTE 6 — ARQUITETURA E OPERAÇÃO

### 33. Arquitetura e infraestrutura

**Fluxo de dados de mercado:** GitHub Actions (cron) → coletores Python → Supabase (Postgres) → app SwiftUI lê séries computadas via API do Supabase (chave anônima somente leitura, políticas RLS de leitura pública nas views computadas; chave de serviço só nos GitHub Secrets). **Fluxo de visão da A15:** app reduz a imagem e remove metadados → Supabase Edge Function → OpenAI Responses API (`gpt-5.6-luna`, `store=false`) → ids da taxonomia + observações visuais separadas → confirmação humana. A chave da OpenAI fica somente nos secrets do GitHub durante a avaliação e no secret da Edge Function em produção; nunca no repositório, `Config.xcconfig` ou binário.

- **GitHub:** conta e repositório **privado** criados pelo JP (tarefa humana); autenticação do agente via `gh auth login` (OAuth local, token no chaveiro, segundo fator permanece ligado; nunca senha em texto). Free tier: 2.000 minutos/mês em repo privado, muito acima do consumo estimado (~10 min/dia). Limite de gasto padrão zero: jobs param em vez de gerar cobrança.
- **Três pegadinhas do agendador, mitigadas:** (1) cron é sempre UTC: madrugada BRT ~03:00 = `0 6 * * *` UTC; (2) workflows agendados desativam após 60 dias de inatividade do repo: o commit diário do `SAUDE.md` resolve; (3) não há notificação de falha: o relatório de saúde é o alarme. Atrasos de 10 a 30 minutos em pico são irrelevantes para o caso.
- **Supabase:** conta e projeto criados pelo JP (tarefa humana); o agente escreve schema, migrações e políticas. Verificar a política vigente de pausa de projetos inativos no plano gratuito; o toque diário do cron tende a manter o projeto ativo, mas confirmar.
- **Fases e execução:** F0 tarefa zero → F1 fundação (repo, secrets, schema, materialização dos anexos CSV) → F2 coletores + saúde (prioridade absoluta; varejo primeiro) → F3 motor → F4 app esqueleto de 3 abas lendo séries reais → F5 relatório da peça + Comparar → F6 laço de validação + termômetro → F7 polimento + TestFlight. Nenhuma fase começa antes da anterior passar nos critérios de aceitação. Coleta nunca sai do ar durante as fases seguintes.

### 34. Anti-escopo da v0/v1 (não construir)

Sem login/conta de usuário, sem push notification, sem closet/monitoramento contínuo por peça, sem modo offline completo (apenas cache da última sincronização), sem multi-idioma, sem Android/web, ~~sem LLM no relatório~~ `[REVOGADO em 10/08/2026 por A15, sob as travas da §29]`, sem Instagram/TikTok, sem pagamentos, sem painel administrativo web. Agente que "adiantar" qualquer um desses itens está violando o documento.

### 35. Riscos e planos B

- Poucas marcas passam no teste dos 30 segundos → priorizar multimarcas acessíveis, reduzir a promessa do segmento e declarar a cobertura real; a demo migra o peso para busca + editorial.
- Alpha do Trends negado e pytrends instável → cadência quinzenal com cache + exportação manual assistida (o agente gera a lista de consultas; humano exporta CSV).
- Supabase pausar/limitar → exportação automática dos dados em CSV no repositório como cópia fria; religar é migração simples.
- Visão abaixo de 80% → app segue formulário-primeiro (já é o padrão da v0); nada quebra.
- Dado fictício vazando para demo → tarefa zero, `DADOS_FICTICIOS.md` e checagem obrigatória do arquivo antes de qualquer apresentação.
- Site do painel muda layout/endpoint → o relatório de saúde acusa queda; coletor daquela marca entra em quarentena até correção, sem derrubar o resto.

### 36. Perguntas abertas com o cliente (não inventar respostas)

1. Definição quantitativa de sucesso de peça (percentual vendido a preço cheio? em quantas semanas?): destrava a régua do termômetro.
2. Histórico de notas do provão: existe? é consultável?
3. Dados de uma coleção antiga com desfecho conhecido, para a validação retroativa.
4. Mapa oficial de meses → sub-coleções (verão, alto verão, inverno, alto inverno), com a Lorena.
5. Teste presencial / visita deles na Mostra: datas e formato.
6. Quanto da informação externa o comercial já tem hoje (calibra o discurso de valor).
7. **Autorização escrita para coletar Maria Filó e Fábula** `[ADITIVA 23/07/2026]`. As duas são VTEX mas fecharam a API de catálogo no edge, e o teste dos 30 segundos as reprovou (23/07). São marcas do próprio grupo do cliente, então a autorização é dele para dar. **Enquanto não vier, as duas permanecem `falhou` e fora da coleta**, mesmo tratamento dado a Colcci e Centauro — senão a regra 7 vira conveniência. Se a autorização chegar, registrar no changelog e só então liberar a coleta, pelo caminho que funcionar. Prioridade: a Maria Filó é a cliente-modelo e hoje está fora do próprio painel.

### 37. Glossário

Cluster: conjunto de atributos de uma peça. Célula: cruzamento termo x segmento x semana. Grade quebrada: percentual de tamanhos indisponíveis. Reposição: retorno persistente de disponibilidade (2+ snapshots). Remarcação: queda de preço. Continuativo: produto de linha contínua (clássico). Painel de medição: marcas coletadas pelo bot. Painel de direção: marcas/veículos monitorados só por frequência de atributo. Termômetro: validação retroativa do índice. Cobertura: mínimos de marcas, peças e semanas para exibir número. Z-score: desvio da série contra a própria história. Raridade (IDF): peso maior para atributo raro. Sub-coleções: verão, alto verão, inverno, alto inverno (calendário Azzas). Pct preço cheio: percentual vendido sem remarcação.

### 38. Anexos

- `anexos/taxonomia.csv` (Anexo A): 35 termos, status inicial `proposto`; primeira tarefa humana do JP é a sessão de revisão e aprovação.
- `anexos/painel_marcas.csv` (Anexo B): painel v0 com papéis, justificativas e `status_teste=pendente`.
- `anexos/veiculos.csv` (Anexo C): veículos editoriais + Lyst, `status_feed=pendente`.
- **Anexo D, esquema de dados** (o agente materializa como migração SQL na F1; coletor escreve, motor computa, app só lê):

```sql
marcas(id, nome, dominio, plataforma, segmento, papel, justificativa, status_teste, congelada_em, ativa)
produtos(id, marca_id, id_externo, url, titulo, descricao, categoria_site, imagem_url, primeiro_avistamento, flag_tipo)  -- flag_tipo: continuativo | colecao | indefinido
snapshots(id, produto_id, data, preco_original, preco_atual, composicao, grade_por_tamanho_jsonb, capturado_em)
eventos(id, produto_id, tipo, data, detalhe_jsonb)  -- tipo: reposicao | remarcacao | saida_de_linha
termos(id, rotulo, dimensao, sinonimos, termo_busca, palavras_pt, palavras_en, exemplo, status)  -- espelho do CSV aprovado
produto_termos(produto_id, termo_id, origem)  -- origem: titulo | visao | manual
artigos(id, veiculo, url, titulo, data_pub)
artigo_termos(artigo_id, termo_id)  -- contagem única por par
series_semanais(termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra)
saude(data, fonte, itens, pct_campos_ok, alertas_jsonb)
```

Se os arquivos CSV não estiverem presentes junto deste documento, o agente os cria a partir das versões entregues com ele e para para o JP validar antes de coletar.

### 39. Changelog

- 23/07/2026 | v1.0 | CRIAÇÃO | Documento inicial consolidando todas as decisões da fase de pesquisa e estruturação.

**23/07/2026 | v1.1 | Respostas à AUDITORIA_INICIAL (arquivo `RESPOSTAS_AUDITORIA.md`, autor JP).** A auditoria da tarefa zero (§2) voltou com 6 bloqueadores, 6 contradições, 11 constantes ausentes e 7 ambiguidades. Abaixo, o que cada resposta mudou.

**Prazo (o que reorganiza tudo)**

- `ADITIVA` | **B1** | Demo Day fixado em **24/08/2026**, 32 dias a partir de 23/07. Consequência aceita como decisão explícita, não como acidente: **a perna de varejo nunca terá z-score dentro deste projeto**, porque §8 exige 8 semanas e a coleta começa em 24/07. A regra não é afrouxada — z-score com 4 pontos é instável, e afrouxar seria exatamente a conveniência que a regra existe para impedir.
- `ADITIVA` | **B1.2** | O índice de aquecimento roda na v1 com **duas pernas: busca e editorial**, as duas com anos de história via backfill. A interface declara "baseado em: busca + editorial", mecanismo que §8 já previa.
- `ADITIVA` | **B1.3 (a §21 e §23)** | Criada a **camada descritiva de varejo**: o varejo entra no produto sem passar por z-score, como fatos do presente que não precisam de normalização nem de história longa — participação do atributo no sortimento, percentil de preço, estado da grade, velocidade relativa de esgotamento por tamanho, eventos de reposição e de remarcação. Cada número declara o N e a data de coleta. Não é consolo: é o ativo proprietário do projeto, e nunca precisou de z-score para existir.
- `ADITIVA` | **A3** | Forma descritiva do marco de demo 2: participação atual do atributo no sortimento contra a curva sazonal de busca dos últimos 5 anos. Exige ~2 semanas de varejo em vez de 8, desde que a tela declare que a leitura é descritiva e não normalizada.

**Coleta**

- `ADITIVA` | **B2 (interpretação oficial da regra inviolável 4)** | A regra 4 governa a coleta **por termo** (consultas ao Trends, matching editorial), o cálculo de índice e a exibição em tela. O snapshot de varejo não depende de termo e pode ligar imediatamente, antes da aprovação da taxonomia. Justificativa: o matching título→termo é **retroativo** — snapshot guardado hoje pode ser etiquetado semana que vem sem perda, e o contrário não é verdade, porque dia não coletado não volta. Registrado aqui para não haver reinterpretação futura.
- `ADITIVA` | **B3** | Gravação por **delta**: linha de snapshot só quando algo muda (preço, disponibilidade, grade), mais um batimento semanal por produto; série diária reconstruída por carry-forward na leitura. Condição obrigatória: **visitar diariamente, gravar por exceção** — sem visita diária não existe detecção de ausência (K1) nem debounce de reposição (§23). O `SAUDE.md` registra produtos *visitados* e linhas *gravadas*; se os dois números convergirem, é bug na comparação de delta.
- `REVOGATÓRIA` | **B4 (corrige o Anexo D)** | `segmento` sai de `marcas` e passa a ser coluna de `produtos`, derivada do mapa de categorias, com `marcas.segmento` como padrão de fallback. Sem isso, produto de multimarca não podia ser atribuído a um segmento e a célula termo × segmento × semana ficava sem ele.
- `ADITIVA` | **A2** | **Colete amplo, classifique depois.** Resolve a colisão entre B2 (ligar já) e B5 (o mapa de categorias ainda não existe): desde o dia 1 coleta-se o **catálogo feminino inteiro** de cada marca aprovada, sem filtrar por segmento. A atribuição de `segmento` por produto é retroativa. Com a gravação por delta o excedente é barato; a história perdida por esperar o mapa não é recuperável.
- `ADITIVA` | **B5** | Criado `anexos/mapa_categorias.csv`, tudo `status=proposto`, aprovado junto com a taxonomia.
- `ADITIVA` | **B6** | E-mail do projeto: `canarioch3@gmail.com`. User-Agent final: `CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)`.

**Taxonomia e motor**

- `ADITIVA` | **C1** | "Conta" lê-se "ajuste local do dispositivo" em toda a v1 (aplicado em §15).
- `REVOGATÓRIA` | **C2 (corrige §11)** | A dimensão `modelagem` misturava dois eixos e a promessa de exclusividade intra-dimensão era falsa: uma peça é midi **e** flare ao mesmo tempo. `modelagem` se divide em `comprimento` (curto, midi, longo) e `silhueta` (flare, reta_wide), e entra a coluna `exclusiva` por dimensão, com `tecido` e `cor` como não exclusivas. **Sete dimensões, 35 termos, nenhum `id` alterado** — a regra de id estável de §11 continua honrada. A implementar junto: o IDF (K5) precisa lidar com cardinalidade variável por dimensão.
- `REVOGATÓRIA` | **C3 (reenquadra §11)** | O teste triplo de admissão deixa de ser **porta de admissão** e passa a ser **anotação de capacidade**: o termo existe, o que varia é quais pernas conseguem servi-lo. Antes de marcar `sem_perna_busca`, tenta-se corrigir o `termo_busca`, registrando qual variante foi testada. Motivo: o teste original eliminaria `liso`, que é o denominador da dimensão estampa. Aplicado: os `termo_busca` genéricos ("roupa lisa", "roupa preta") foram reescritos ancorados em categoria real, e a dimensão `cor` inteira passou a ser medida dentro de "vestido", categoria âncora do segmento, para as sete cores serem comparáveis entre si.
- `ADITIVA` | **C4 (corrige §22)** | O estado `pico` passa a ser calculado sobre a contagem editorial da **semana crua**, não sobre a janela móvel de 4 semanas — que o mantinha aceso quase um mês, o oposto de "evento pontual que morre rápido". A janela de 4 semanas permanece para todo o resto. É a única métrica do sistema que quer sensibilidade em vez de estabilidade, e isso fica escrito ao lado da fórmula.
- `ADITIVA` | **C5** | Lyst permanece em `veiculos.csv`, sai da soma editorial por construção (`tipo=dado_agregado` excluído da perna) e ganha `fonte` própria em `series_semanais`.
- `ADITIVA` | **C6 (exceção a §6)** | A lista negra proíbe as formas futuras e prescritivas; o teste automatizado carrega allowlist explícita de rótulos factuais no passado. Princípio, escrito no próprio arquivo de teste: **passado observado é permitido; futuro e prescrição são proibidos.**
- `ADITIVA` | **A1** | Bootstrap do flag continuativo: K2 (26 semanas) e K3 (3 reposições em 12 semanas) são regime permanente mas inúteis no prazo. Entram `continuativo_presumido` e `colecao_presumida`, presumidos por categoria de básicos e palavras-chave de título, substituídos pela classificação medida assim que houver dado. A interface diferencia presumido de medido.
- `ADITIVA` | **K1 a K11** | Constantes aceitas conforme propostas na auditoria. K7 (âncora fixa nas consultas ao Trends) e K11 (coorte fixa de marcas, célula vira "cobertura insuficiente" acima de 25% de ausência) não se relaxam sem consulta ao JP.

**Escopo e publicação**

- `REVOGATÓRIA` | **A6 (revoga §26)** | Publicação na App Store passa a ser requisito, com data. Conta de desenvolvedor resolvida sem custo (regra 13 intacta). **Similares com identidade visual própria**: o binário submetido não republica foto de produto de terceiro — cada card é representação gerada dos atributos (bloco na família de cor, glifo de silhueta, textura pela estampa) mais marca em texto, preço, remarcação e estado da grade; o toque abre a página original em `SFSafariViewController`, cumprindo a rastreabilidade da regra 3. Tarefa de design da Bianca, e é identidade do produto, não fallback. Feature freeze 10/08, submissão até 13/08.
- `REVOGATÓRIA` | **A7 (revoga §28 e §30 para a v1)** | Saem da v1 a entrada por foto e visão computacional inteira, e as referências internas. Fica de pé: Analisar (busca → relatório), Explorar, Comparar, coletores e relatório de saúde.
- `ADITIVA` | **A8** | Vocabulário interno nunca vira produto. "Efeito Ozempic", "provão" e apelidos de regra não aparecem em interface, templates, release, nomes de variável ou identificadores visíveis. O achado da curva de tamanhos é descrito como "deslocamento da curva de tamanhos" ou "quebra de grade concentrada nos tamanhos menores". **Referência a medicamento, peso corporal ou condição de saúde é proibida em qualquer texto do produto.** Entra como bloco próprio no teste automatizado de §6.
- `ADITIVA` | **A9** | Roadmap v1.1 (setembro): a coleta não para no Demo Day, o varejo cruza as 8 semanas em meados de setembro e o z-score liga sozinho pelo mecanismo de pernas declaradas — como o índice é computado no servidor, **o app publicado em 24/08 passa a exibir a perna nova sem atualização de binário**. Depois: referências internas e visão computacional.

**23/07/2026 | Execução da F1 (agente).**

- `ADITIVA` | **Teste dos 30 segundos executado** nas 26 marcas pendentes. Resultado: 14 aprovadas (12 VTEX, 2 Shopify). **As externas de `feminino_casual_br` somam 11 aprovadas contra o mínimo de 8 de §8: o segmento v1 passa** e o plano B de §35 não é acionado.
- `ADITIVA` | **Nenhum multimarca passou** (Dafiti, Shop2gether, Iguatemi 365, Centauro). O multiplicador de cobertura de §13 **não existe na v1**, e a ressalva de leitura relativa dentro da mesma vitrine fica sem objeto. O painel externo se sustenta sem eles.
- `ADITIVA` | **Fora por plataforma ou proteção:** Youcom (Linx), Mixed (Magento), Shoulder e Renner (plataforma própria), Foxton (domínio não resolve), Colcci e Centauro (HTTP 403, fora por regra 7 — não se procura outro caminho).
- `ADITIVA` | **Maria Filó e Fábula reprovadas por decisão de princípio.** As duas são VTEX mas fecharam a API de catálogo no edge. O host da plataforma responderia, e a decisão do JP foi **não contornar**: API fechada no edge é escolha deliberada da loja, e entrar por outra porta é o mesmo que foi negado a Colcci e Centauro — senão a regra 7 vira conveniência. Vira a pergunta aberta 7 de §36: o JP pedirá autorização escrita ao cliente, e só com ela a coleta é liberada. Domínio real da Fábula corrigido para `afabula.com.br`.
- `ADITIVA` | **Anexo B ganha as colunas `dominio`, `data_teste` e `detalhe_teste`.** O Anexo D exigia `marcas.dominio` e o CSV não trazia a coluna — o teste dos 30 segundos não tinha como rodar.
- `ADITIVA` | **Escala medida para dimensionar o B3:** só na consulta "vestido", C&A tem 13.436 produtos, Dress To 1.755 e Farm 1.443. A gravação por delta é requisito, não otimização.
- `ADITIVA` | **Ambiente:** a máquina do JP não tem Homebrew nem Python 3.11, só o 3.9.6 do sistema. Os coletores rodam em 3.11 no GitHub Actions e o código evita sintaxe de 3.10+ para permanecer testável localmente, sem instalar nada.

**24/07/2026 | Instruções consolidadas (arquivo `INSTRUCOES_24-07.md`, autor JP) + execução (agente).**

- `EMENDA ADITIVA` | **Regra inviolável 7** | O teto de requisições é por IP, não por domínio: 1 req/s **global**, marcas em série, nunca em paralelo. Anotado na própria regra 7. Motivo: o painel de varejo inteiro está atrás da infraestrutura compartilhada da VTEX, e paralelizar toma 429.
- `REVOGATÓRIA` | **§13** | O multiplicador de cobertura por multimarca não existe na v1 (0 de 4 passaram). Reversível se o pente fino recuperar algum multimarca.
- `ADITIVA` | **Schema + RLS aplicados** (F1, Passo 2) no projeto `JogzDev Canario-CH3`. Migração `0001_f1_schema_e_rls`: as 10 tabelas do Anexo D com `segmento` em `produtos` (B4), `flag_tipo` com os valores presumidos (A1), e as colunas `exclusiva`/`sem_perna_busca` na taxonomia (C2/C3). RLS ligado nas 10 antes de qualquer linha entrar: `anon` (chave publishable do app) só lê `series_semanais`, escreve em nada, e não enxerga nenhuma tabela crua; o coletor escreve com `service_role`, que ignora RLS. Advisor de segurança sem ERROR nem WARN.
- `ADITIVA` | **Coleta em modo amplo com filtro provisório de categoria** (A2 operacionalizado): o coletor pagina as categorias que o classificador marca como vestuário feminino, com `segmento` do produto em NULL até o mapa ser aprovado, quando é preenchido retroativamente. Colher o catálogo feminino inteiro sem esperar o mapa, sem baixar a loja de departamento inteira.
- `ADITIVA` | **Condição 2.3** | O coletor pagina pelo header `Range` da VTEX, sem teto de tamanho de resposta (o truncamento de 600 KB do script de teste não existe no coletor de produção). O `SAUDE.md` grava o total declarado no header `resources` por marca e o compara com o coletado; divergência acima de 2% vira alerta.
- `ADITIVA` | **Correspondência exata nos matchers** (item 4): módulo `coletor/matcher.py` compartilhado pelos três matchers (categorias, título→termo, editorial), correspondência por palavra inteira com prefixo livre só no sufixo `*`. Regressão fixada: `reta` não casa `preta`.
- `ADITIVA` | **Pergunta aberta §36.7** já registrada em 23/07 cobre a autorização de Maria Filó e Fábula.

**28/07/2026 | Revisão da taxonomia e desbloqueio da coleta.**

*Infraestrutura e decisões do JP*

- `ADITIVA` | **§36.7 RESPONDIDA: o cliente autorizou a coleta das marcas do grupo Azzas**, incluindo Maria Filó e Fábula. Como as duas fecharam a API de catálogo no domínio próprio, a autorização escrita do dono da marca torna o acesso pelo host da plataforma (`*.vtexcommercestable.com.br`) **acesso autorizado, não contorno** — é exatamente essa autorização que separa este caso de Colcci e Centauro, que permanecem fora porque não temos nem pediremos autorização delas. A sonda de descoberta da conta VTEX das duas roda na próxima execução do pente fino.
- `ADITIVA` | **Runner residencial aprovado**: a coleta passa a poder rodar num Mac i7 do JP, em IP residencial, que é o que a VTEX aceita. O workflow escolhe o runner pela variável de repositório `RUNNER_COLETA`. Guia em `RUNNER.md`. **A regra inviolável 13 permanece intacta: nada pago.**
- `ADITIVA` | **Cron diário aprovado e ativado**: `0 6 * * *` UTC = 03:00 BRT. Só produz coleta real quando o runner residencial estiver de pé; no datacenter o disjuntor aborta em 429.
- `ADITIVA` | **Amaro fora da v1 por decisão do JP.** 429 persistente de datacenter mesmo com ritmo correto e backoff longo. Com o runner residencial volta a ser possível; até lá, as externas de `feminino_casual_br` ficam em 10, ainda acima do mínimo de 8 de §8.
- `ADITIVA` | **Candidatura ao alpha do Google Trends submetida** pelo JP em 28/07.
- `ADITIVA` | **Push de workflow com retry** (`.github/commitar.sh`): em 27/07 um push morreu com `Internal Server Error` (500 do GitHub) e deixou o job vermelho por erro de terceiro, com o dado já salvo no Supabase. Erro transitório agora tem 5 tentativas com espera crescente.

*Revisão da taxonomia (crítica endossada pelo JP; 7 pontos)*

- `REVOGATÓRIA` | **§11: contaminação semântica corrigida.** Três `termo_busca` mediam população fora de moda: `croche` (no Brasil mede artesanato — receita, ponto, amigurumi, tapete — com sazonalidade própria que nada tem a ver com o mercado), `estilo boho` (puxa decoração e casamento) e `animal print` (puxa bolsa, sapato, capinha, papel de parede). Todos ancorados no frame de moda feminina. Uma alta contaminada entraria no índice como se fosse desejo por peça.
- `ADITIVA` | **§11: uma âncora por dimensão, declarada.** O princípio já estava aplicado em `cor` e não fora generalizado: `tecido` tinha quatro âncoras diferentes e `estetica`, cinco. Isso não quebra o z-score (que é contra a própria história), mas quebra o ranking dentro da dimensão, que é o que aparece no Explorar e no peso de raridade do cluster. Âncoras: `feminino/a` em categoria, `vestido` em estampa, tecido, comprimento e cor, `calça` em silhueta e cintura, `look` em estética.
- `ADITIVA` | **§25: a dimensão `cor` ganha `cinza`, `amarelo_laranja` e o residual `outras_cores`.** Era buraco silencioso: cinza é cor central de moda e não tinha casa, e — diferente de `estampa`, que tem `liso` como denominador — `cor` não tinha balde residual, então produto de cor inclassificável sumia do denominador e a dominância de cor no sortimento (§25) saía errada por omissão. `outras_cores` é atribuído por exclusão pelo motor, nunca por casamento de palavra, e nasce `sem_perna_busca=sim`.
- `REVOGATÓRIA` | **`estetica` deixa de ser exclusiva.** Mesmo bug que o C2 pegou em `tecido`: um vestido de festa com babado é `festa_brilho` **e** `romantico`. Marcada como exclusiva, o formulário da foto forçaria escolha falsa e o tagging do bot descartaria metade da informação.
- `ADITIVA` | **`oversized` sai de `reta_wide`.** O `termo_busca` mede calça e `oversized` etiquetava camisa e blusa no varejo: as duas pernas mediam populações diferentes e viravam o mesmo número no índice. **Princípio geral adotado para toda revisão de termo: o que o `termo_busca` mede e o que as `palavras_pt` etiquetam têm de ser a mesma população.** `oversized` fica como candidato a termo próprio numa dimensão `caimento` futura.
- `ADITIVA` | **Termos novos por mérito:** `macacao` (categoria real e relevante em moda feminina BR), `cintura_alta` (atributo forte e muito buscado) e `xadrez` (separado de `geometrica`, por ter ciclo próprio e reconhecimento visual claro). **Correção de registro:** a revisão supôs que `macacão` e `cintura alta` existiam no documento e se perderam no anexo; verificação exaustiva mostrou que nunca estiveram no `CANARIO.md` nem no CSV original. Entram pelo mérito, não por restauração — não há inconsistência anterior a caçar.
- `ADITIVA` | **`cintura` como dimensão própria** em vez de dentro de `silhueta`: `cintura_alta` coexiste com `wide leg` ("calça wide leg cintura alta"), e juntá-las obrigaria `silhueta` a ser não exclusiva, perdendo a exclusividade real entre `flare` e `reta_wide`.
- `ADITIVA` | **Verificação de volume ANTES da aprovação** (`VERIFICACAO_TRENDS.md`): 10 grupos de até 5 termos, âncora fixa `vestido floral` (K7), Brasil, 5 anos. Corrige uma afirmação errada do agente em 27/07 — de que só daria para aferir volume quando a perna de busca existisse. Dá para conferir à mão hoje, e aprovar sem conferir seria aprovar às cegas um `termo_busca` possivelmente morto.

*Decisões do JP em 28/07 (segunda leva)*

- `ADITIVA` | **Taxonomia APROVADA**, os 41 termos com `status=aprovado`. Aprovação declarada como provisória ("por enquanto"), a revisitar. **Consequência a registrar:** a perna **editorial** pode andar imediatamente, porque o casamento editorial usa `palavras_pt`/`palavras_en` e não toca em `termo_busca`; já a perna de **busca** continua dependendo da verificação de volume (`VERIFICACAO_TRENDS.md`), porque é ela que consome `termo_busca`. Termos aprovados podem virar `sem_perna_busca=sim` depois da verificação sem perder a aprovação.
- `ADITIVA` | **Marco de demo 3 resolvido** — ver §10: duas consultas ao vivo.
**30/07/2026 | Exceção ao mínimo de 8 semanas, congelamento da coorte e varredura de pendências.**

- `EXCEÇÃO PONTUAL` | **§8, mínimo de 8 semanas de história para exibir z-score.** O JP abriu **uma exceção, explicitamente pontual**, para a perna **editorial**, que chegará ao Demo Day com cerca de 6 semanas. Palavras dele: *"o que combinamos não é pra ser negociável, é a LEI, estou abrindo apenas uma exceção dessa vez"*. Registrado assim de propósito:
  - **Escopo:** só a perna editorial, só até o Demo Day de 24/08/2026. Não vale para varejo (que segue sem z-score por decisão B1) nem para busca (que tem 5 anos e não precisa).
  - **Motivo:** cortar a perna editorial inteira seria perda maior que exibi-la com história curta declarada.
  - **Obrigação que continua valendo:** a tela declara quantas semanas sustentam o número, e a regra 6 (cobertura mínima ou silêncio honesto) permanece intacta para todo o resto.
  - **Não é precedente.** Qualquer outro afrouxamento de §8 exige nova decisão escrita.
- `ADITIVA` | **Coorte congelada em 30/07/2026** (regra 5 e K11), com **16 marcas**: 6 núcleo (Cantão, Dress To, Lança Perfume, Morena Rosa, Zinzane, Amaro), 3 adjacente (Le Lis Blanc, Bo.Bo, PatBô), 2 âncora (C&A, Hering), 5 grupo (Farm, Animale, Maria Filó, Fábula, NV). Marca nova só na virada de temporada. **O congelamento estava previsto para 25/07 nas instruções do JP e o agente não o executou na data**; o efeito prático é nulo porque nenhuma marca entrou ou saiu desde então, mas fica registrado como atraso, não como cumprimento no prazo.
- `ADITIVA` | **`DADOS_FICTICIOS.md` criado** (regra 2 e §35). Lista vazia: nenhum dado fictício em uso, tudo coletado pelo próprio sistema com origem e data. Cumpre o critério de sucesso 4 do §9.
- `ADITIVA` | **`coletor/teste_vocabulario.py` criado**, que é o teste que o §6 exige em texto ("o agente deve implementar um teste automatizado que varre os textos da interface contra esta lista"). Três blocos: previsão de venda (§6/regra 1), vocabulário interno (A8, inclusive proibição de referência a medicamento e peso corporal) e sugestão de cultivo (§27). Allowlist do C6 com o princípio escrito no arquivo: *passado observado é permitido; futuro e prescrição são proibidos*. Escopo por bloco, porque tratar código de coletor como interface gera falso positivo e teste com falso positivo é teste que se aprende a ignorar.
- `ADITIVA` | **Motor no ar (F3).** Migrações 0004–0006. `produto_termos` saiu de zero: 65.787 produtos ligados à taxonomia, 97,8% com pelo menos um termo. Série semanal de varejo como **share do sortimento** (§15/§21), z-score em janela móvel de 12 semanas (§21), índice por média das pernas ativas com pesos iguais fixados antes de olhar resultado (§22), e estados com a regra anti-ruído de 2 semanas. O cálculo vive no Postgres (§33: servidor calcula, app consulta).
- `ADITIVA` | **Matching de atributo usa título + categoria, nunca descrição.** §28 diz que "títulos de e-commerce são etiquetas quase prontas"; descrição é texto de marketing. Medido: 74% dos casamentos de `reta_wide` vinham da descrição, com camiseta de "caimento amplo" virando silhueta de perna. Ligações caíram de 375 mil para 190 mil e a cobertura de produtos quase não mudou (98,4% → 97,8%) — o excedente era ruído.
- `ADITIVA` | **`ampla|amplo` removido de `reta_wide`**, pelo mesmo motivo que `oversized` saiu em 28/07: etiquetava peça de cima. Aplica o princípio já acordado — termo_busca e palavras têm de medir a mesma população.
- `ADITIVA` | **Correção de honestidade no estado.** O motor afirmava `estável` com **uma única perna ativa**. A §22 exige 2 fontes concordando, então com uma perna nenhum estado é alcançável, e cair no `estável` faz o sistema afirmar estabilidade que não mediu — valor plausível no lugar de nulo declarado, o que a regra 2 proíbe. Agora o estado fica **nulo**, com o motivo em `meta.estado_indisponivel_por`, e o índice continua exibível com as pernas declaradas (§8). **Consequência de produto:** enquanto só a busca tiver z, o app mostra índice sem estado. O estado passa a existir quando o editorial cruzar 6 semanas (pela exceção de 30/07), por volta do fim de agosto.
- `ADITIVA` | **Runner residencial de pé** no Mac i7 da Academy, instalado como serviço (LaunchAgent) e com `RUNNER_COLETA=self-hosted` criada. **Confirmação empírica de 28/07:** uma requisição única à VTEX a partir de IP residencial devolveu `HTTP 206` com JSON válido (`resources: 0-4/216` no Cantão), contra `429` consistente do datacenter do GitHub. A hipótese de rate-limit por range de IP está confirmada.

*Pendência de demo aberta (RESOLVIDA em 28/07, ver acima)*

- **Marco de demo 3 (§10) precisa de decisão.** O roteiro era "verde e lilás no masculino", com as pernas de busca e editorial respondendo e o varejo declarando cobertura insuficiente. Mas o `termo_busca` de `verde` e `lilas_roxo` é `vestido verde` / `vestido lilas`, ou seja, moda feminina: a perna de busca **também** não responde à pergunta do masculino, e a demo mostraria duas pernas vazias — o que parece defeito, não honestidade. Ver seção 10.

**31/07/2026 | Bloco de reclamações do JP sobre o app, e o que ele expôs no motor.**

O JP abriu o app com os prints na mão e listou nove problemas. Três eram de tela; os outros seis apontavam defeito real embaixo. Registrados aqui pela mesma razão que os anteriores: o que o teste não pega, o documento tem de pegar.

*Defeito de motor, não de interface*

- `ADITIVA` | **`computar_eventos()` nunca esteve no motor.** A função foi criada no banco em 30/07, está correta, e não entrou em `motor_computar.py` nem em migração. Resultado: a tabela `eventos` congelou em 30/07 enquanto as coletas seguiram gravando snapshot todo dia, e a tela mostrava "Remarcações da semana" com o dado de anteontem — que foi exatamente a reclamação. Ao ser ligada, a primeira chamada gerou **894 eventos atrasados de uma vez**, todos reais. Corrigido na migração `0007` (a função passa a existir em arquivo) e no `motor_computar.py`, como **primeiro** passo, para que um erro no cálculo de índice não impeça o registro da §23 do dia. **O `PENDENCIAS.md` marcava K1 e K4 como feitos** — a função existia. É a mesma classe de dívida que o placar foi criado para pegar, agora com uma lição: *função criada não é função chamada*.
- `ADITIVA` | **Ordinal do evento por produto** (`eventos_da_semana`). O JP pediu "*1ª reposição" e "*3ª reposição dos tamanhos PP/P em menos de 2 meses". A segunda frase é muito mais forte que a primeira — repor três vezes o mesmo tamanho em dois meses é a marca dizendo que aquele tamanho vende — e as duas apareciam iguais na tela. A **1ª vem ancorada na data de início da coleta** ("1ª reposição desde 24/07/2026"), porque afirmar "primeira" com oito dias de história seria afirmar o que não foi medido (regra 2).
- `ADITIVA` | **A perna editorial passa a guardar quem publicou.** `series_semanais.meta` ganha `veiculos` (contagem por veículo) e `exemplos` (até 3 manchetes com link). O JP: *"quero o nome dos sites que fizeram o bot chegar a essa conclusão"*. A regra 3 pede o caminho até a origem, e a origem parava no rótulo da perna. Vale para o coletor diário e para o backfill — os dois fazem upsert na mesma chave, e sem mexer nos dois o backfill sobrescreveria a meta com uma versão mais pobre.

*Vocabulário*

- `ADITIVA` | **`bolinha` entra no termo `geometrica`.** O JP buscou "vestido de bolinha" e recebeu só "Vestido". A taxonomia tinha `poá`, que é o nome técnico, e não o nome que o comprador usa. Nenhum termo criado, nenhum `id` alterado: é vocabulário de um termo existente, e `poá` continua funcionando (está nos títulos do catálogo).

*Interface*

- `ADITIVA` | **Todo número sai com unidade colada.** O cartão mostrava "+1,15" sozinho, e o JP perguntou: *"1,15 o quê? Paçoquitas?"*. Agora sai "+1,15 desvios" com a definição por extenso abaixo, e cada perna declara o que conta (matérias, % do sortimento, índice do Trends de 0 a 100).
- `ADITIVA` | **O estado explica a própria regra ao usuário.** *"Por que isso é considerado pico? Não é pra mim que você tem que explicar, é pro usuário."* O `Explicacao.swift` espelha `computar_indice()` linha a linha e é testado contra ela — se um dos dois mudar sem o outro, o teste quebra. "Pico" passa a dizer que a imprensa disparou e **nenhuma outra fonte acompanhou**, que é a condição que o separa de "em alta" e o que o comprador precisa saber antes de agir.
- `ADITIVA` | **Eventos agrupados por marca**, com a lista de peças abrindo no toque. Vinte cartões soltos viravam uma parede.
- `ADITIVA` | **Vírgula decimal.** A tela mostrava "-2.18" e "2.2 desvios". Mesma família da regra de data em dd/mm/aaaa e do horário de Brasília, e estava faltando.
- `REVOGATÓRIA` | **§27, aba Comparar.** O JP: *"pra que exatamente ela serve? Acho que ela ficou meio aquém do resto do projeto."* Estava certo, e o defeito era de concepção: ordenar termos por um único número e chamar aquilo de ranking não ajuda a decidir nada. A aba passa a comparar em **dois eixos de pernas diferentes** — presença no painel (share do sortimento, descritivo, sem z-score por B1) e movimento editorial (índice da §22) — e a mostrar **a distância entre eles**. O que fazer com a distância continua sendo do comprador, que tem custo e prazo que o app não conhece (regra 1).
- `ADITIVA` | **Atalho de importação em um lugar só.** O botão do canto superior direito saiu; aquele lugar é de configurações.

*Entrada por arquivo (§28)*

- `ADITIVA` | **PDF de imagem passa a ser rasterizado e lido.** O arquivo que o JP mandou é uma foto de produto da Hering salva em PDF, com `/Image` e `DCTDecode` e **nenhum `/Font`**. O leitor chamava `PDFDocument.page.string`, recebia vazio e desistia sem olhar a imagem que estava ali. Agora a página vira bitmap a 2x e segue para o OCR.
- `ADITIVA` | **Cor medida no pixel** (`CorDaPeca.swift`), quando o arquivo não tem letra nenhuma. Medido antes de prometer: a classificação genérica da Vision devolve `clothing` com 0,53 de confiança e mais nada — sabe que é roupa, não sabe que peça. **Cor, porém, é medível direto do pixel**, e é uma dimensão inteira da taxonomia recuperada de uma foto muda. No arquivo do JP, o app agora marca `cinza` com 94% de cobertura útil. A cor entra **marcada no formulário como sugestão**, com a procedência dita ("medida no próprio pixel, é a marcação que mais pede conferência"), e **o texto ganha do pixel** quando os dois falam de cor: o título é a cor que a marca declarou, o pixel é a cor sob a luz do estúdio.
  - **Limite declarado:** os limiares foram calibrados em 5 fotos e acertaram as 5. É amostra pequena. A calibração definitiva sai do catálogo inteiro — temos 180 mil imagens já rotuladas pelo próprio coletor —, e depende do **runner residencial**: os CDNs das marcas devolvem `429` para o datacenter, e a regra 7 proíbe contornar isso.
  - **Nomear a peça a partir da imagem continua não existindo.** Exige modelo treinado, e o caminho está aberto (nosso catálogo já é o conjunto rotulado). Fica registrado como próximo passo, não como feito.
- `ADITIVA` | **Formatos nomeados um a um** no seletor (`pdf`, `jpeg`, `png`, `heic`, `heif`, `tiff`), porque arquivo vindo de WhatsApp às vezes chega declarado como tipo genérico e o item ficava cinza.
- `ADITIVA` | **Busca com dois ou mais atributos oferece a leitura do conjunto.** O JP: *"vestido de bolinha claramente não é a mesma coisa que vestido, e não teria as mesmas estatísticas"*. Uma busca que descreve uma peça responde sobre a peça. **O índice do conjunto (K5) continua não implementado** e a tela segue declarando isso — o que existe hoje é a leitura atributo por atributo, junta na mesma tela.

*Dois erros de paginação, encontrados na tela e não no teste*

- `ADITIVA` | Com 681 remarcações em 31/07, uma consulta única ordenada por data enchia a página inteira e **o bloco de reposições aparecia vazio havendo 217 no banco** — sumindo justamente com o sinal mais forte do painel (§23). Passou a ser uma consulta por tipo. O mesmo erro atingiu as séries do digest, onde um cartão dizia "vários desvios" em vez do número por não ter recebido a linha do editorial. Registrado porque a causa é a mesma nos dois: **teto de linhas com ordenação única esconde a minoria**, e a minoria costuma ser o que interessa.

**01/08/2026 | Curva de tamanhos (§24) no ar — marco de demo 1.**

*O problema que decidiu o método*

- `ADITIVA` | **Nada é convertido entre marcas.** Medido no painel: a Hering usa `XP · P · M · G · XG · XXG` e não tem PP nem GG; a Zinzane usa `PP · P · M · G · GG · XG · XGG`, onde XG fica **acima** do GG. O mesmo rótulo é o maior tamanho de uma marca e um degrau intermediário de outra, então **uma tabela global rótulo→tamanho seria demonstravelmente errada**. Converter 38 para M seria pior ainda: a equivalência número↔letra varia por marca e não temos como aferir. O que se faz é ordenar os rótulos **dentro da grade de cada produto** e usar a **posição relativa** — 0 = o menor que aquela marca oferece, 1 = o maior. Numa grade de cinco degraus isso recorta exatamente o que a §24 pede (menores = PP/P, meio = M, maiores = G/GG) e funciona igual na Hering, sem ninguém afirmar que XP "é" PP. A leitura **por rótulo** existe, mas só nas grades da escada padrão `{PP,P,M,G,GG}`, que é a única forma de nomear tamanho sem misturar sentido.
- `ADITIVA` | **`coletor/tamanhos.py` + `teste_tamanhos.py`**, espelhando a função `ordem_do_tamanho()` do Postgres. O normalizador é a peça que decide se a curva compara coisas comparáveis, e um erro nele não apareceria como erro: apareceria como uma curva plausível e errada. Todos os casos do teste vieram do painel real.

*Uma correção de método, no meio do caminho*

- `REVOGATÓRIA` | **A medida principal passou a ser a dinâmica, não a foto.** A primeira versão usava `share_indisponivel` (estado de hoje) como manchete, porque tem N maior. Isso contraria a §23, que é explícita: *"Usar dinâmica (velocidade de quebra, percentual da grade ao longo do tempo), **nunca a foto de um dia**"*. E as duas medidas **discordam de verdade**:
  - pela foto: GG é o que mais quebra (62,5%), com curva em U;
  - pela dinâmica: **P é o que mais quebra (3,57%) e GG é o que menos (2,16%)**.
  
  A foto carrega toda a indisponibilidade antiga e a profundidade de compra da marca, que não observamos — como se compra menos PP e menos GG, as pontas aparecem esgotadas por construção. A especificação já tinha decidido isso antes; o erro foi meu, e foi corrigido antes de virar tela.

*O achado*

- `ADITIVA` | **Painel inteiro, escada de letra, janela de 14 dias:** PP 2,35% · **P 3,57%** · M 3,26% · G 2,68% · GG 2,16%. A quebra tem **pico em P**, e os menores saem 1,18 vez mais que os maiores. Na escada numérica o formato é ainda mais limpo e monotônico: menores 4,23% · meio 3,51% · maiores 3,13%.
- `ADITIVA` | **A tela nomeia o tamanho de pico, e não a ponta da grade.** É decisão de produto com teste próprio: no painel, PP é o **segundo que menos quebra**. Um comprador que lesse "os menores quebram mais" e reforçasse PP estaria agindo sobre uma leitura errada. Dizer "o tamanho P é o que mais sai de linha" é ao mesmo tempo mais verdadeiro e mais acionável.
- `ADITIVA` | **Por atributo**, a diferença é muito maior que no agregado: Alfaiataria 2,39x, Flare e evasê 1,57x, Casaco e jaqueta 1,44x, Vestido 1,33x. É aí que a curva vira decisão de compra.
- `ADITIVA` | **Composição de grade (soma zero) implementada e testada** como a §24 autoriza, em linguagem condicional, com as ressalvas obrigatórias na mesma tela. O teste barra explicitamente as formas de recomendação de volume, que a regra 1 proíbe.

*Dívidas que a curva expôs*

- `ADITIVA` | **Bug no coletor Shopify:** `shopify_extrair` pegava `option1` às cegas como tamanho. Na Amaro a primeira opção é **cor**, e 335 produtos entraram com a grade preenchida de "PRETO", "MARROM", "BEGE". O caminho VTEX já fazia certo — procurava a variação cujo nome contém "tam" — e o Shopify não. Corrigido lendo `options` por nome. O dado velho continua no banco até a próxima coleta residencial; o normalizador já o descarta, então não contamina a curva.
- `ADITIVA` | **Calçado da PatBô entrou no painel** com `segmento` preenchido (`34BR/36EU`, 47 peças por numeração). O classificador deixou passar. Volume baixo, mas é população errada.
- `ADITIVA` | **Consolidação por rótulo**, encontrada na tela e não no teste: o banco guarda a curva por (faixa, rótulo) e **o mesmo rótulo cai em faixas diferentes conforme o formato da grade** — `M` é meio numa grade de cinco degraus e maiores numa que vai de PP a M. A tela mostrava `M` três vezes e elegeu como destaque uma linha de 727 amostras na frente de uma de 11 mil. A consolidação é ponderada pelo risco, e há piso de amostra por tamanho. É o terceiro defeito desta natureza em dois dias — **agregação com grão errado escondida atrás de um número plausível** —, e os três só apareceram olhando a tela.

**01/08/2026 (tarde) | O nome da marca entrando como atributo, e o que ele estava escondendo.**

Fui checar de onde vinham os similares antes de construir o bloco da §29, e o dado não passou no cheiro. O que apareceu foi grande.

*O erro*

- `ADITIVA` | **O nome de quem vende estava descrevendo o que se vende.** O caminho de categoria da Dress To é `/dress to/Bazar/Blusas/`, e `dress` está em `vestido.palavras_en`. Resultado: **os 6.895 produtos da marca inteira** viraram `vestido` — calça, blusa, saia e bolsa junto. Eram **41,3% de todas as ligações de `vestido` do painel**. O mesmo com "Morena Rosa", que dava `vermelho_rosa` a 612 produtos (11,2% daquele termo). Corrigido no `motor_atributos.py`, que agora tira o nome da marca do texto antes de casar — para toda marca, não só as duas que colidem hoje, porque uma marca nova chamada "Linho" ou "Preta" reintroduziria o problema em silêncio.
- `ADITIVA` | **Acessório e calçado não são peça de roupa.** 1.425 produtos (2,3% do painel) — bolsa, brinco, sandália, necessaire, e até "Capa de Laptop" e "Planner" — estavam com `segmento` preenchido. O filtro por árvore de categoria não pega, porque a Shopify não expõe árvore: a PatBô entrava inteira, com 256 bolsas, 70 sandálias e 66 brincos. Agora o filtro é pelo **início do título**, e a âncora foi escolhida por medição: `cinto` aparece em 1.117 títulos e só 127 são cintos — os outros 990 são vestidos e macacões "com cinto"; `lenço` aparece em 207 e 158 são "Calça Lenço". No sentido oposto a âncora quase não custa: `bolsa` casa 509 e 499 começam com ela.
- `ADITIVA` | **É a terceira vez que texto que não descreve a peça entra como se descrevesse**: a descrição de marketing (30/07), o `content:encoded` do editorial (30/07) e agora o nome da marca. Nenhuma das três aparece como erro — as três aparecem como um número maior. `teste_populacao.py` trava as três famílias.

*Como a limpeza foi feita, e por que quase deu errado duas vezes*

- `ADITIVA` | O motor em Python é a autoridade, mas não roda fora do Actions (não tem a chave). A limpeza do dado já gravado foi feita em SQL, e **a primeira tentativa teria apagado 675 ligações corretas**: meu regex SQL não reproduzia a flexão do matcher (`canelado`→`canelada`), nem os plurais da categoria (`/Vestidos/`), nem `cherry`. A formulação correta é **diferencial**: a ligação só é do nome da marca se o termo casa o texto original e **deixa de casar** sem o nome — aplicando o mesmo regex nos dois lados, a imperfeição se cancela. Com isso o resultado foi exatamente as duas marcas com colisão real.

*O que mudou nos números que já estavam na tela*

- `ADITIVA` | **`vestido` caiu de ~27,5% para 19,7% do sortimento**, e `blusa e top` passou a liderar com 30,9% — que é o que se espera de um painel de moda feminina. As curvas de tamanho por atributo mudaram de ordem: Alfaiataria 1,82x (era 2,39x), Cinza 1,77x, Casaco e jaqueta 1,52x. **`Vestido` saiu do topo**, porque o 1,33x de ontem estava calculado sobre uma população que incluía todo o catálogo da Dress To.

*Uma superafirmação minha, encontrada pelo teste*

- `REVOGATÓRIA` | **A manchete da curva de tamanhos elegia um vencedor onde havia empate.** Depois da limpeza, o painel deu M com 5,4% e P com 5,3%, e a tela declarou o M campeão. Em onze mil amostras cada, dois erros-padrão da diferença somam 0,6 ponto: a distância de 0,14 cabe inteira no ruído. Entrou `empatados()` com o erro-padrão binomial, e a manchete passou a nomear os dois. **Ao ligar a margem, o teste antigo quebrou e mostrou que a afirmação de ontem — "o tamanho P é o que mais sai de linha" — também nunca se sustentou**: P e M já empatavam então (3,57% contra 3,26%, margem de 0,51). O achado que o dado sustenta, e que vale em todas as versões medidas, é outro e mais simples: **as pontas da grade (PP e GG) são as mais lentas**. A composição de grade também passou a se calar quando a diferença não se sustenta — mandar deslocar grade sobre ruído é pior que não dizer nada.

**01/08/2026 (noite) | A perna de busca estava parada há 19 dias, e nada avisou.**

O JP pediu relatório operacional e firmou o acordo de que "relatório" passa a significar **o estado de tudo** — GitHub, coletores, servidor, Mac i7 —, e não um resumo do que foi feito. O primeiro relatório já achou o problema.

- `ADITIVA` | **A série de busca congelou em 13/07/2026**, com 20 de 40 termos. Três causas empilhadas, e a terceira é a que deixou as outras duas invisíveis:
  1. **O cron era semanal** (segunda 04:00), mas a lógica de retomada foi escrita pensando em avanço noturno — o próprio comentário no código dizia "algumas noites cobrem a taxonomia inteira". Com 429 do Google em 7 de 10 grupos, uma tentativa por semana nunca fecha.
  2. **A retomada era permanente.** Ela pula todo termo que já tem série, o que é certo no backfill e errado na coleta semanal: os 20 termos com série **nunca mais eram consultados**. O coletor virou um backfill de uma vez só, e a cadência semanal da §19 simplesmente não acontecia.
  3. **O coletor não gravava linha de `saude`.** Só `varejo` e `editorial` gravavam. Por isso ninguém viu por 19 dias — nem eu, que passei três dias construindo em cima.
- `REVOGATÓRIA` | **O cron passa de semanal para diário** (04:30 BRT). A série continua semanal (§19): o Trends devolve ponto por semana e a gravação é idempotente na chave (termo, segmento, fonte, semana). Rodar todo dia só aumenta a chance de a semana corrente ser preenchida. **A regra 7 continua intacta**: o volume por execução não muda, o teto é de 1 req/s e a espera entre grupos segue em 45 segundos.
- `ADITIVA` | **Dois modos explícitos**, escolhidos pela cobertura e não por variável de ambiente: `backfill` enquanto faltar termo sem série, `semanal` quando todos tiverem. `TRENDS_MODO` força a mão quando preciso.
- `ADITIVA` | **A execução falha com código diferente de zero quando nenhum grupo responde**, em vez de terminar verde em silêncio. Verde silencioso foi o que escondeu isto por 19 dias.
- `ADITIVA` | **Consequência a registrar, e ela é de produto:** enquanto a busca não voltar, o índice da §22 é a média de **duas pernas editoriais** (BR e internacional). Atende ao mínimo de duas fontes, mas as duas são imprensa — é uma concordância mais fraca do que "editorial + busca", e eu vinha descrevendo as três pernas como se as três estivessem ativas.

*Limitação de observação, registrada para não se repetir*

- `ADITIVA` | O repositório é privado, o `gh` CLI não está instalado na máquina do JP (que também não tem Homebrew) e a API pública devolve 404. **O agente não enxerga o Actions diretamente** — infere pelos commits do `CanarioBot` e pela tabela `saude`. Um workflow que falha sem gravar nada é invisível. Foi exatamente o caso. Enquanto o `gh` não existir, `saude` é o único instrumento, e é por isso que toda perna precisa gravar nela.

**01/08/2026 (noite) | Bloco de similares (§29) no ar.**

É o que a §5 lista como **substituto aprovado** da previsão que o projeto proíbe: *"análogos descritivos — as 3 peças mais parecidas e o desfecho delas"*. E é o que sustenta o bloco 1 da §29, o parágrafo-resumo, que vem antes do índice do cluster (bloco 3, ainda não feito).

*Decisões de método*

- `ADITIVA` | **O resumo é sobre TODOS os similares; a lista é amostra.** Uma peça "vestido + floral + midi" tem 230 similares. Calcular a porcentagem sobre os 8 cartões exibidos seria estatística de vitrine. A tela declara quantos são contra quantos aparecem.
- `ADITIVA` | **Limiar de semelhança: 70% dos atributos, arredondado para cima.** A primeira versão exigia "todos menos um" e devolveu **3.989** similares para três atributos — porque tolerar uma diferença em três deixa entrar todo vestido midi liso e todo floral curto. Com 70%, três atributos exigem os três: 230 peças. Aperta onde cada atributo pesa muito e afrouxa onde há muitos. A tela declara o limiar aplicado.
- `ADITIVA` | **A amostra é espalhada pelas marcas**, uma peça de cada primeiro. Ordenar por id devolveu três peças da PatBô, todas esgotadas e com 50–70% de desconto, num conjunto onde 22% estão a preço cheio — a amostra contava outra história que o resumo.
- `ADITIVA` | **Porcentagem só acima de 12 similares.** Com 4, "25% a preço cheio" é uma peça.

*Desempenho, que mandou no desenho*

- `ADITIVA` | A função é chamada **ao vivo pelo app**, que entra como `anon` com `statement_timeout` de **3 segundos** — diferente da curva de tamanhos, que é lote noturno e leva 64s. A primeira versão levava **11,3 segundos** numa busca por "vestido" sozinho, porque formatava o estado da grade de 11.579 peças só para agregar. Duas correções: o formato caro passou a rodar só nas peças que viram cartão, e as duas perguntas sobre a grade passaram a caber num lateral só. Ficou em **0,14s no pior caso**, com o índice `produto_termos_por_termo` como pré-requisito — a chave primária começa por `produto_id` e a pergunta do §29 é a inversa.

*Uma decisão de segurança, registrada por extenso*

- `ADITIVA` | **A função é `security definer`, e isso não afrouxa a RLS.** O app entra como `anon`, que por desenho não enxerga `produtos`, `marcas` nem `produto_termos` — e o primeiro teste na tela devolveu **401** justamente por isso. Em vez de expor as tabelas, a função virou uma **janela controlada**: devolve exatamente o que a §29 manda mostrar (marca, título, url pública, preço, remarcação, estado da grade) de no máximo 24 peças, com o teto imposto pela própria função e não pelo cliente. O app continua sem poder listar as tabelas, filtrar por marca ou paginar o catálogo. O dado devolvido é público por natureza — peças à venda em loja aberta — e o cartão leva o link para a página original, que é o que a regra 3 exige.

*A6, parcialmente cumprida*

- `ADITIVA` | O cartão **não republica foto de produto de terceiro**, como a A6 exige. A representação é gerada: um bloco cuja altura preenchida mostra o estado da grade, mais marca em texto, preço, remarcação e o desfecho em uma linha. A identidade visual definitiva é tarefa da Bianca e troca em `MarcaVisual`, sem tocar na tela.

*O que o painel diz hoje, para "vestido + floral + midi"*

> No painel de 9 marcas, encontrei 230 peças. 22% seguem a preço cheio. 88% estão com a grade quebrada, e 72% já sem nenhum tamanho. O preço do meio é R$ 130.

E a amostra mostra a matriz preço × grade da §23 ao vivo: Cantão a R$ 1.199 com grade cheia e preço cheio, Dress To a R$ 429 remarcada 50% e esgotada.

---

### 02/08/2026 — K5, o índice do cluster: a fórmula da §22 não sobreviveu ao próprio dado

*O que a §22 manda, e o que o IDF cru devolveu*

- `ADITIVA` | **§22 / K5 implementado** (migração 0010). A §22 pede "média dos índices dos atributos ponderada por raridade (lógica IDF)". Rodei o IDF cru **antes de escrever qualquer código**, e ele coroou `liso` como o atributo mais pesado de toda a taxonomia: **6,87 contra 1,17 de "blusa e top"**. `liso` tem 61 peças — não porque peça lisa seja rara, mas porque **90,7% das peças não têm nenhum termo de estampa detectado**. As 61 são as que escreveram a palavra no título. Raridade medida sobre não-medição, e premiada com o maior peso do sistema.

*Por que o df é medido errado, e por que o resto do sistema sobrevive a isso*

- `ADITIVA` | **O viés de detecção depende da marca, e isso está medido.** % de peças com algum termo de estampa: C&A 14,2% · Farm 9,0% · PatBô 4,8% · Le Lis Blanc 0,4% · **Morena Rosa 0,0% em 812 peças** — e a Morena Rosa vende estampa. A cor vai de **0,1% (Lança Perfume) a 88,6% (PatBô)**, 900× com a mesma taxonomia e o mesmo matcher. A detecção é função da convenção de nomenclatura da marca, não da roupa. Na literatura isso é a violação da hipótese SCAR de Elkan & Noto (KDD 2008): o caso SNAR de Bekker & Davis.
- `ADITIVA` | **A consequência boa, e ela precisa ficar registrada porque protege o que já está no ar:** um viés de detecção aproximadamente constante no tempo **se cancela no z-score**, porque z é desvio contra a própria história — o viés desloca a média e a observação juntos. Ele **não** se cancela no IDF, porque IDF é um nível comparado *entre* termos. Por isso `series_semanais` e `indices_semanais` não precisam de conserto, e só o peso de raridade precisava.

*Três correções, cada uma com procedência*

- `ADITIVA` | **Raridade dentro da dimensão** (BM25F: Robertson, Zaragoza & Taylor, CIKM 2004). Resolve a cardinalidade variável que o **C2 já tinha registrado como dívida do K5**: `cintura` tem 1 termo e o IDF cru lhe dava 2,92, mais que a `vestido`; agora cai para o piso ln(2)=0,69, que é o correto — uma dimensão de um termo não distingue nada.
- `ADITIVA` | **Raridade condicionada à categoria** (o MAVE, WSDM 2022, registra que atributos são definidos por categoria). Medido: **`jeans` é 23,7% dentro de `calça` e 1,8% dentro de `vestido` — 13×**. `midi` é 9,7% no painel e 35,8% dentro de `saia`. **Efeito colateral que fecha um círculo:** ao condicionar, o próprio termo de categoria vira 100% do seu denominador e cai para o piso. Ou seja, *"vestido pesa pouco"* — o exemplo escrito na §22 — sai de graça, mas por um mecanismo diferente do que a §22 nomeou.
- `ADITIVA` | **Encolhimento contínuo** (Micci-Barreca, SIGKDD Explorations 3(1), 2001, na forma empírico-bayesiana do `TargetEncoder` do scikit-learn): λ = n/(m+n) com m = σ²/τ². Substitui o portão de preenchimento que eu ia usar — limiar é penhasco arbitrário, isto degrada suavemente. **Nenhum número escolhido a dedo entra no cálculo.**
- `ADITIVA` | **Forma não-negativa** ln(1+1/p), família ATIRE/Lucene. Kamphuis et al. (ECIR 2020) testaram 8 variantes de BM25 em 3 coleções TREC e não acharam diferença significativa — mas registram que vale usar uma que não produza valor negativo. Ao condicionar à categoria, `jeans` dentro de `calça` está em 54,3% e `reta_wide` em 78,6%, então o caso `df > N/2` deixou de ser hipotético.

*Uma tentativa medida e descartada, registrada para ninguém repetir*

- `ADITIVA` | O encolhimento conserta **contagem baixa**, não **detecção enviesada** — são dois problemas e eu tratei como um. Com ele ligado, `liso` continuou o mais pesado (3,65). Testei então sobredispersão de Pearson entre marcas (φ = χ²/gl, correção quase-verossimilhança). **Não discrimina:** `vestido` deu o maior φ de todos (**305**), porque marcas de fato diferem em sortimento, e `liso` nem aparece no top 22. φ mede heterogeneidade real e não separa isso de viés de detecção. Descartado.

*A correção que funcionou já estava escrita na taxonomia*

- `ADITIVA` | **`termos.papel`**, espelhando `marcas.papel`. O campo `motivo` de `liso` diz, desde a construção da taxonomia: *"Denominador da dimensão estampa: sem ele o share de floral perde base de comparação"*. `liso` **nunca foi um atributo a medir** — e o IDF transformou o denominador no atributo mais pesado do sistema. O mesmo vale para `outras_cores`: *"balde residual... atribuído por exclusão pelo motor, nunca por casamento de palavra"*. Um termo `denominador` fica fora do denominador da própria dimensão, não conta para o k do prior, e recebe o **peso médio dos atributos medidos da sua dimensão** — nem prior (que depende de k, e k é arbitrário) nem zero (o termo tem índice válido vindo de busca e editorial; só a contagem no painel é que não é medição). `liso` foi de **3,65 para 1,97**, e o topo virou `lilás e roxo` (2,1% das peças com cor), que é raridade de verdade.

*O que o índice do cluster NÃO faz*

- `ADITIVA` | **Não cria estado do cluster.** A §22 define `em alta`/`em queda`/`pico`/`estável` para a série semanal de um TERMO, com regra anti-ruído de 2 semanas e 2 pernas concordando. Nada disso está definido para um conjunto, e inventar seria a regra 2 ao contrário.
- `ADITIVA` | **Não afirma direção quando os atributos discordam.** Devolve `dispersao` (desvio ponderado dos índices em torno da média) e `ha_direcao`, verdadeiro só quando |índice| ≥ dispersão. Medido no caso real: *vestido+floral+midi* dá índice **−0,77 com dispersão 1,28**, porque `vestido` está em −3,10 e `floral` em +0,29. A tela diz *"os atributos desta peça não apontam para o mesmo lado"* e mostra o número mesmo assim. É a mesma lição da manchete da curva de tamanhos, corrigida em 01/08.
- `ADITIVA` | **Tamanho efetivo de amostra de Kish** ((Σw)²/Σw²) na saída: diz quantos atributos *realmente* sustentam o número. Se um carrega quase todo o peso, o "índice do conjunto" é um atributo só usando roupa de conjunto, e a tela avisa.

*Honestidade sobre a fundação, porque ela não transfere inteira*

- `ADITIVA` | Spärck Jones (1972) propôs a especificidade do termo como **heurística**. Robertson (2004) mostra que as derivações por Teoria da Informação são problemáticas e que a justificativa boa está no modelo probabilístico (RSJ) — que é sobre **discriminar documentos relevantes de não-relevantes**. O Canário não tem consulta nem conjunto relevante, então a justificativa probabilística **não transfere**; o que transfere é a intuição heurística. Isso não invalida usar IDF: significa que a escolha se decide por comportamento medido, e que o código não deve fingir princípio onde há heurística.

*Dívida nova, achada de passagem*

- `ADITIVA` | **`outras_cores` tem 0 peças.** Foi criado em 28/07 para ser o balde residual da dimensão `cor`, preenchido **por exclusão pelo motor** — e o motor nunca o preenche. O buraco que ele existia para tapar (produto de cor inclassificável sumindo do denominador) continua aberto: 38,6% das peças não têm nenhum termo de cor.

---

### 02/08/2026 (madrugada) — a perna editorial estava medindo a si mesma

- `ADITIVA` | **Quatro `pico` na tela eram três revistas novas.** O app dizia que preto, azul, branco/cru e vermelho/rosa estavam em pico na imprensa BR na semana de 27/07. Nos quatro veículos que já eram medidos (Elle, Steal the Look, Harper's, Fashion Bubbles) a cobertura desses termos naquela semana **caiu para 1 artigo — o menor de toda a série**. Os outros 14 vieram inteiramente de **Marie Claire, Vogue Brasil e Glamour, que entraram entre 23 e 27/07**.
- `ADITIVA` | **Zeros materializados (migração 0011).** `editorial_br` tinha **0 linhas com valor 0** e só **30,6%** das células (termo × semana); `editorial_intl`, 48,5%. Semana sem matéria virava ausência, não zero, e a janela do z só enxergava as semanas boas do termo. Sintoma: **z médio do BR negativo em 13 de 13 semanas** e `em alta` = 0 em toda semana desde 01/06. Corrigido, o z passa a oscilar em torno de zero (média −0,03). O zero só é criado a partir da primeira semana em que o termo já tinha linha — antes disso não se sabe se ele estava sendo casado, e afirmar zero onde não houve medição seria a regra 2 ao contrário.
- `ADITIVA` | **A "janela móvel de 12 semanas" da §21 não era de 12 semanas.** `rows between 12 preceding` conta **linhas**. Com 30,6% de preenchimento isso cobria **29,2 semanas em média e até 216 — mais de quatro anos**, enquanto o app escrevia "média das últimas 12 semanas" na tela. Passa a ser `range` de calendário.
- `ADITIVA` | **"Share of voice" era contagem absoluta.** O docstring do coletor e o nome do workflow dizem share of voice desde sempre; a conta era `sum(janela)/4` — divisão pelo número de **semanas**. O denominador BR foi de ~460 para **896 matérias (+90%)** em uma semana com a entrada dos veículos novos. Agora divide pelo total da própria perna na mesma janela, em partes por mil. **§33 mandou onde isso vive:** o coletor só enxerga o feed recente, então quem divide é o motor (`computar_serie_editorial()`, novo passo antes do `computar_z`).
- `ADITIVA` | **`computar_indice()` nunca apagava.** Uma leitura que perdia a base ficava na tela para sempre: ao ligar o portão, os quatro `pico` continuaram exibidos com índice 5,48 e **as duas pernas com z nulo**. Agora a linha some e a tela cai no "sem leitura neste recorte" que já existia.

*O que a correção revelou e NÃO resolve — fica registrado para não ser improvisado*

- `ADITIVA` | **Z-score é o modelo errado para contagem esparsa.** Com os zeros, um termo que fica em 0 na maior parte das semanas tem desvio quase nulo, e uma semana com 5 matérias vira **z = 10,27** (`azul`). Testei o resíduo de Poisson, que seria o candidato óbvio: **piorou** (1.428 leituras acima de 2,5 contra 781) e o desvio observado deu **1,74** — variância 3× a de Poisson. A contagem editorial é **superdispersa** porque matéria de moda vem em rajada temática. O modelo correto é binomial negativa, e isso é decisão de método.
- `ADITIVA` | **Portão de cobertura da §8 na perna editorial**, que ela nunca teve — o varejo tem `cobertura_por_celula` (30 peças, 8 marcas), a busca tem 5 anos de Trends, o editorial não tinha nada. Piso: **10 matérias na janela de 4 semanas**, regra de bolso padrão para tratar contagem como aproximadamente normal, declarada como o chute documentado que é. **Consequência de produto, e é grande: a tela fica bem mais vazia** — na semana de 27/07 sobram 6 termos com leitura e nenhum estado. É o tamanho real da imprensa de moda brasileira (450 a 900 matérias por 4 semanas, 40 termos disputando menção). **O valor do piso é decisão do JP**, e mexer nele muda o que o Demo Day mostra.

---

### 06/08/2026 — as abas descrevem o app errado, e a §34 tem uma linha no meio disso

- `REVOGATÓRIA` | **A10 (emenda §34 e §27)** | A revisão de 03/08 do companheiro de time abriu com *"Tabs não estão certinhas: Analisar / Explorar / Comparar — quando deveria ser Adicionar / Armário / Dados / Busca"*. Está certo no diagnóstico: as abas atuais são nomeadas pelos **verbos que o app executa**, e não pelas coisas que o usuário tem. E o resto da revisão mostra o custo — *"a tab Comparar tá bem confusa, não entendi tão bem"* — porque Comparar **pressupõe peças já analisadas** (§27) e o app esquecia todas ao trocar de aba. A §27 passa a ser: **Adicionar** (entrada por busca ou arquivo), **Minhas peças** (as que você montou, com a comparação dentro) e **Dados** (o que era Explorar, incluindo o que a revisão pediu para mover para lá).
- `ADITIVA` | **A §34 continua excluindo closet, e "Minhas peças" não é um.** A diferença não é de nome, é de promessa, e ela está no tipo: `PecaSalva` guarda **só o que o usuário digitou** — atributos, apelido, contexto — e **nenhum número calculado**. Todo índice, estado e z é recomputado do dado de hoje quando a tela abre. Sem alerta, sem histórico por peça, sem "sua peça caiu 3% desde a semana passada" — que é o produto que a §34 proíbe e que o dado não sustenta: a peça é do cliente, não está no painel, e não temos como segui-la. `testPecaSalvaNaoGuardaNumeroCalculado` falha se alguém acrescentar um campo dessa natureza, com a razão escrita na mensagem de falha.
- `ADITIVA` | **Teto de 200 peças, dito e não engolido.** A revisão imaginou *"5000 peças"*. Cinco mil peças numa lista sem pasta nem busca é o mesmo problema de tela cheia em outro lugar; enquanto não houver organização de verdade, o teto recusa e avisa, em vez de aceitar e virar depósito.
- `ADITIVA` | **Fica no aparelho.** A §34 não tem conta de usuário na v1, então não há para onde sincronizar nem por quê. JSON em Application Support.

---

### 07/08/2026 — o nome da aba volta a ser Armário, por decisão do JP

- `REVOGATÓRIA` | **A11 (revoga o nome dado na A10)** | O JP: *"A aba armário volta, mas com uma roupagem diferente. A ação revogatória que estou fazendo agora é pro nome da aba, a função dela eu explico com mais detalhes em breve."* A aba passa a se chamar **Armário**. A A10 tinha escolhido "Minhas peças" justamente para não prometer o que a §34 exclui; a escolha do nome é do JP e o design da Bianca ainda não chegou.
- `ADITIVA` | **O nome mudou; a garantia não.** `PecaSalva` continua guardando **só o que o usuário digitou** — atributos, apelido, contexto — e nenhum número calculado. Índice, estado e z seguem recomputados do dado de hoje a cada abertura. `testPecaSalvaNaoGuardaNumeroCalculado` falha se alguém acrescentar campo dessa natureza.
- `ADITIVA` | **O que fica pendente da função.** Se a "roupagem diferente" envolver acompanhar a peça ao longo do tempo — alerta, histórico por peça, "sua peça caiu 3%" — então a §34 precisa de revogação com **consequência de método**, e não só de rótulo: a peça do cliente não está no painel, não é vendida por nenhuma marca que a gente mede, e afirmar movimento sobre ela seria a regra 2 ao contrário. Se for organizar, agrupar ou reabrir, não há conflito nenhum e nada mais precisa mudar.

---

### 07/08/2026 — câmera e fototeca entram (A12)

- `REVOGATÓRIA` | **A12 (desfaz o resto do A7 sobre a §28)** | O JP: *"E se necessário, o app vai passar a pedir permissão sim"* e *"Camera pode ser antes da submissão, acho que dá"*. Entram **câmera** e **leitura da fototeca**, ao lado da entrada por arquivo que já existia. As três terminam no mesmo `LeitorDeArquivo`: OCR do texto, cor do pixel, atributos confirmados no formulário.
- `ADITIVA` | **A retenção zero fica mais fácil de verificar, não mais difícil.** Câmera e fototeca entregam a imagem **em memória**, sem passar por arquivo. Não existe caminho de disco em nenhum dos três caminhos — e o que não existe não pode ser esquecido ligado.
- `ADITIVA` | **O que a ficha de privacidade perde, e o que ela não perde.** O app deixa de poder dizer "não pede permissão nenhuma": agora pede duas. Mas `NSPrivacyCollectedDataTypes` **continua vazio**, porque permissão de acesso e coleta de dado são coisas diferentes. Não pedimos escrita na fototeca: o app não salva foto nenhuma, nem a que ele mesmo tirou.
- `ADITIVA` | **`allowsEditing = false` na câmera, de propósito.** O recorte do iOS parece útil e não é: ele devolve a imagem já cortada, e o corte feito com o dedo mudaria a cor dominante que o `CorDaPeca` mede. O app estaria medindo o enquadramento, e não a peça.

### 07/08/2026 — leitura do design da Bianca e do Davi

Quatro pontos do Figma que colidem com o documento, registrados antes de virarem código:

- **Login / Cadastrar / Account** colidem com a §34 (*"sem login/conta de usuário"*). Conta significa dado de usuário, ficha de privacidade diferente e autenticação a manter. Se a conta existe só para guardar o armário, o aparelho já faz isso sem ela. Pergunta em aberto para o Davi: **o que a conta habilita?**
- **"Métricas da peça" com gráfico de linha** implica acompanhar a peça do usuário ao longo do tempo, que é o closet da §34 e que o dado não sustenta — a peça não está no painel. **Conserto barato, tela idêntica:** o gráfico é dos *atributos* dela (o índice do cluster), que existe e é medido.
- **"Taking measurements" / "Clothing DNA"** prometem que o app mede a peça pela foto. Medido em 07/08: 64,1% só em categoria. O texto de carregamento precisa dizer o que acontece de fato.
- **"Mostrar similares" com foto de produto** colide com o A6 (*"o binário submetido não republica foto de produto de terceiro"*). Se as imagens do Figma são placeholder, não há questão.

---

### 10/08/2026 — foto por hotlink (A13) e o gráfico da peça (A14)

- `REVOGATÓRIA` | **A13 (emenda o A6)** | O JP: *"quero muito usar, de verdade, podemos usar Hotlink sem problemas, desde que funcione"*. O card de similar passa a mostrar a **foto da peça carregada do CDN da própria loja**. É *hotlink*, e não cópia: o aparelho busca a imagem na origem, na hora de exibir; nada é copiado para o nosso servidor nem embutido no binário, e o toque continua abrindo a página original (regra 3). O bloco de cor do A6 **não sai** — vira o fundo, e é o que aparece enquanto carrega, quando a loja tira a imagem do ar e quando o produto não tem foto.
- `ADITIVA` | **O que fica em aberto, e é do JP.** O "Google faz assim" vem de precedente americano de *fair use* (miniaturas), e o Brasil não tem *fair use* geral — a Lei 9.610/98 tem exceções enumeradas. Hotlink com atribuição e link para a origem é o menor risco disponível, e não é parecer jurídico: vale conferir os termos das lojas antes da publicação.
- `ADITIVA` | **A14 — `serie_do_cluster()`** | O gráfico de "Métricas da peça" do Figma passa a ser dos **atributos** da peça, e não da peça do usuário (que a §34 exclui acompanhar e o dado não sustenta). Mesma ponderação por raridade e mesmo recorte de categoria do número grande. Cada ponto carrega `n_atributos`: semana com 1 de 3 atributos não é comparável com semana com 3 de 3, e a tela precisa poder dizer isso em vez de desenhar linha contínua fingindo cobertura constante.
- `ADITIVA` | **O último ponto NÃO bate com o número grande, e não deve.** O número grande é a leitura mais recente de *cada* atributo, que pode vir de semanas diferentes; o ponto é o que havia *naquela* semana. Medido em 10/08 para vestido+preto+floral: −0,43 contra −0,57. Escrevi o contrário no primeiro comentário da migração e corrigi.

---

### 10/08/2026 — OpenAI no runtime (A15) e interface em inglês (A16)

- `REVOGATÓRIA` | **A15 — visão pela API.** O JP aprovou enviar a foto escolhida pelo usuário à OpenAI porque as rotas locais medidas ficaram em 49,6% e 64,1%, abaixo do piso de 80%. O modelo inicial é `gpt-5.6-luna`. A chave fica atrás de uma Supabase Edge Function; o app nunca a recebe. A imagem é reduzida e perde metadados antes do envio. `store=false` reduz persistência de estado da Responses API, mas não autoriza prometer retenção zero. O formulário humano continua sendo o dado final.
- `ADITIVA` | **Taxonomia fechada sem desperdiçar o que o modelo enxergar.** A resposta separa `taxonomy_attributes`, restrito aos ids aprovados que têm série e métrica, de `additional_visual_attributes`, texto visual que não entra no motor. Um rótulo livre nunca ganha número por parecer plausível; pode virar candidato de taxonomia em decisão posterior.
- `REVOGATÓRIA` | **A15 — Luna como redator na v1.** Cai a proibição da §29/§34, mas não as regras 1–3. A chamada de redação é independente da visão e recebe só um pacote estruturado de fatos calculados. Números precisam pertencer ao pacote, a lista negra continua obrigatória e o template atual é fallback automático.
- `ADITIVA` | **Portão antes do app.** Primeiro se valida o secret sem inferência e sem tokens via `GET /v1/models`; depois vem um benchmark estratificado de 300 imagens no i7. Categoria e cor continuam precisando de pelo menos 80% contra rótulo humano. Comparação com rótulo derivado de título é diagnóstico, não abre o portão da §28.
- `REVOGATÓRIA` | **A16 — idioma.** O JP decidiu que o app será em inglês. PT-BR deixa de ser o idioma da v1. Nome definitivo segue aberto; candidatos citados pelo time: Label/Labl e Stitched. Esta entrada registra a decisão; a tradução da interface continua pendente.

### 11/08/2026 — avaliação da visão sem ensinar a prova (A17)

- `ADITIVA` | **A17 — as 24 são calibração, as 300 são holdout.** O JP decidiu repetir as mesmas 24 e só gastar a rodada de 300 se categoria e cor atingirem pelo menos 80%. Como 24 só admite degraus de 4,17 pontos, o piso operacional é **20/24 = 83,3% em categoria e 20/24 em cor primária**, separadamente. A meta de qualidade é 90%+, mas 24 imagens não conseguem demonstrá-la; quem mede generalização é o holdout de 300, que exclui por código todas as 24 imagens de calibração.
- `ADITIVA` | **Verdade humana antes de comparar.** Dois revisores rotulam categoria e cor de forma independente, sem ver pasta, título, rótulo do catálogo ou resposta do modelo. Divergência é adjudicada antes de calcular acurácia. Fotos com várias peças e sem alvo visual inequívoco recebem `not_visible`; o avaliador não pode ser punido por não adivinhar qual SKU o catálogo vendia.
- `ADITIVA` | **Categoria nasce da construção visível.** O modelo e o revisor escolhem a mesma estrutura operacional — peça única com/sem pernas, painel inferior contínuo, duas pernas curtas/longas, construção de camisaria, camada externa ou superior residual — e o código deriva os oito ids. Isso fecha especialmente camisa × blusa/top e saia × short. `blusa_top` não é dividido: nenhuma das cinco divergências do smoke seria consertada por essa divisão e o painel não mede duas séries separadas.
- `ADITIVA` | **Auditoria sem nova cobrança.** Cada futura rodada paga guarda o JSONL completo em artefato privado por três dias; imagens continuam separadas no pacote cego. Preparar, revisar e consolidar não recebe `OPENAI_API_KEY` nem chama a OpenAI. O benchmark de 300 falha antes da primeira imagem se o arquivo de portão humano das 24 estiver ausente, abaixo do piso ou pertencer a outra versão de prompt.
- `ADITIVA` | **Preço corrigido antes da segunda rodada.** A fórmula inicial usou Luna a US$0,20/US$1,20 por milhão de tokens. A página oficial em 11/08 informa **US$1,00 entrada, US$0,10 entrada em cache e US$6,00 saída**. Os mesmos tokens do smoke passam de US$0,010906 exibidos para **US$0,054530**. O avaliador foi corrigido e também contabiliza escrita explícita de cache a 1,25× quando reportada.
- `ADITIVA` | **Duas revisões recebidas; divergência não vira empate arbitrário.** Fadul e Bianca completaram 24/24 sob a rubrica `categoria-cor-v2`. Concordaram em 19 categorias e 17 cores primárias. Como dois votos não resolvem empate, as dez amostras que divergem em alvo, categoria, estrutura ou cor primária seguem para adjudicação cega; discordância apenas em cor secundária não afeta o portão. A segunda rodada paga continua proibida até existir esse gabarito.
- `ADITIVA` | **Saúde não usa o fuso acidental do runner.** A data operacional de coleta e consolidação é `America/Sao_Paulo`, por uma função única compartilhada. Isso impede uma execução manual depois das 21h BRT de escrever a saúde no dia seguinte por causa do UTC do GitHub Actions.
- `ADITIVA` | **Queda VTEX continua bloqueando; corrigiu-se a cobertura, não o portão.** O vermelho de 11/08 foi real nos dados (C&A 4.011 contra média 16.217; Farm 766 contra 2.581), mas nasceu de paginação instável por preço quando muitos produtos empatavam. A coleta agora ordena por nome, deduplica ids e, abaixo de 98% do total declarado, completa pela ordem inversa. O limiar de queda superior a 70% da §20 permanece intacto.
- `ADITIVA` | **Recuperação provada na origem e na publicação.** Farm voltou de 766 para 2.858 itens visitados e C&A de 4.011 para 10.661. Depois das duas coletas focadas, o portão consolidado declarou nenhuma fonte obrigatória bloqueada e o motor publicou atomicamente 75.004 produtos, 186.960 ligações e todos os cálculos. Uma coleta isolada nunca basta como prova: a exigência é fonte recuperada, saúde verde e motor concluído.

### 12/08/2026 — gabarito humano, saúde do Trends e primeira tela (A18)

- `ADITIVA` | **Os comentários do JP são dado, não rodapé.** As dez divergências foram adjudicadas preservando o texto integral. Quando clique e descrição colidiram, a descrição visual prevaleceu: S02 é vestido e explicitamente “não é macacão”; S05 é blazer cropped, logo camada externa; S14 mostra separação entre blusa e bermuda, portanto é conjunto sem alvo único e exige abstenção; S20 mantém continuidade de vestido apesar de gola e botões. O gabarito final cobre 24/24 e vive separado do resultado do modelo.
- `ADITIVA` | **Prompt `alvo-estrutura-v3`, sem nova inferência.** Entraram regras verificáveis para conjunto coordenado, continuidade de vestido, separação que proíbe chamar conjunto de macacão, blazer cropped que continua outerwear, cor medida apenas na peça-alvo e metálicos em `outras_cores`. Leitura, consolidação e testes não recebem chave nem chamam a OpenAI. A próxima cobrança continua proibida até a repetição deliberada das 24.
- `ADITIVA` | **O vermelho de 12/08 tinha motivo conhecido que se perdeu.** Google Trends respondeu HTTP 429 em todos os seis grupos após o backoff, mas o coletor guardava o motivo apenas dentro de `grupos_que_falharam`; a saúde lia zero sem `alertas.erro` e bloqueava como falha desconhecida. O motivo passa a ser consolidado no campo de topo. HTTP 429/5xx conhecido vira aviso nos dois primeiros dias e bloqueia no terceiro; erro interno ou zero sem motivo bloqueia imediatamente.
- `ADITIVA` | **Não se martela uma fonte que acabou de recusar.** Quando todos os grupos falham apenas por HTTP transitório conhecido, o job termina entregando o diagnóstico à saúde, em vez de disparar imediatamente outra recuperação de ~39 minutos. Uma reconsolidação cirúrgica atualizou a linha já salva em 15 s e registrou no log que não consultou o Google. O portão e o motor foram então executados sobre as coletas existentes e concluíram verdes.
- `ADITIVA` | **A18 — a abertura vira o fluxo aprovado da Bianca/Fadul.** Paleta `#BBE5ED`, `#374A67`, `#0E1116`; spotlight vetorial nasce do Dynamic Island real; botão de três pontos abre o menu Favorites · Account · Terms · Settings · Privacy · Q&A; navegação principal é Add · Closet · Analytics, com Search separado. A comparação não some: abre por dentro do Closet, fechando a dobra da A10.
- `REVOGATÓRIA` | **A18 — miniatura local para o Closet.** A regra anterior de “sem miniatura” cai porque o design exige as duas últimas peças reais nas laterais da home. A imagem original continua temporária. Só depois de “Save to Closet” o app redesenha uma prévia de no máximo 720 px em JPEG, removendo EXIF/localização, grava em Application Support excluído de backup e apaga o arquivo junto com a peça. O JSON guarda apenas um nome opaco; nenhum índice, estado ou série calculada entra em `PecaSalva`.
- `ADITIVA` | **Liquid Glass sem elevar o requisito do app.** A implementação usa o material nativo do iOS 17 com borda, luz e sombra, em vez de depender de `glassEffect` de SDK posterior. A aparência foi conferida em simulador de iPhone; a compilação completa e 127 testes Swift passaram.

### 12/08/2026 — a peça vira protagonista visual sem inventar dado (A19)

- `REVOGATÓRIA` | **A19 — a miniatura pode ter transparência.** A18 fixava JPEG branco; o JP pediu a peça principal limpa para o carrossel e o Armário. A imagem continua local, com no máximo 720 px, sem metadados e excluída de backup. `VNGenerateForegroundInstanceMaskRequest` roda no aparelho; entre até 16 instâncias escolhe a maior máscara plausível, com desempate leve pelo centro. Máscara confiável vira PNG transparente e substitui a cópia anterior. Se a máscara for vazia, quase total ou falhar, o app conserva a miniatura íntegra: apagar roupa é pior que manter fundo. Em foto de modelo ou conjunto, a máscara separa primeiro plano, não adivinha semanticamente qual SKU está à venda; o formulário humano continua sendo o portão.
- `ADITIVA` | **Closet em grade e foto corrigível.** A lista vira os cards em duas colunas do Figma, com a roupa inteira em `scaledToFit`. Cada item expõe `Add photo` ou `Replace photo`; peças legadas podem ganhar miniatura e a troca apaga o arquivo anterior. Abrir uma peça salva não cria uma duplicata. O carrossel procura as duas miniaturas mais recentes existentes, em vez de parar em duas peças legadas sem foto.
- `ADITIVA` | **A13 se estende a reposições e remarcações.** `eventos_recentes()` devolve `imagem_url` do CDN da própria loja sob o mesmo regime de hotlink dos similares. A consulta limita os eventos antes de calcular ordinal; a view anterior calculava janelas sobre todo o histórico e estourava o `statement_timeout=3s` da chave pública. `ImagemRemota` valida HTTP e MIME, mantém cache e repete uma vez após cancelamento transitório.
- `ADITIVA` | **Índice não é estado.** O gráfico sumia porque `serie_do_cluster()` exigia `estado is not null` em cada atributo; isso apagava índices legítimos sempre que só uma fonte chegou. A série agora desenha o índice disponível e carrega `n_atributos`, `n_atributos_com_estado` e `n_pernas_min`; pontos parciais ficam marcados e nunca são chamados de direção. A interface de estado procura, em até 13 leituras, a última semana que já teve estado sustentado por duas fontes e mostra a data dela. Se nunca houve, continua `Sem estado`: nulo jamais vira `estável` por conveniência.
- `VERIFICAÇÃO` | **A19 aplicada no Supabase em 12/08.** O SQL Editor retornou `Success. No rows returned`. Pela mesma chave publicável do app, `eventos_recentes` devolveu 5/5 reposições e 5/5 remarcações com imagem, `similares_da_peca` devolveu 8/8 peças com imagem e `serie_do_cluster` devolveu 52 pontos para vestido+preto+floral. Os três hotlinks amostrados responderam HTTP 200 com `image/jpeg`. A série registrou `n_pernas_min=1` em todos os 52 pontos: o índice é desenhável, mas esses pontos não autorizam estado direcional.

### 13/08/2026 — revisão real de navegação: verdade temporal e linguagem (A20)

- `ADITIVA` | **A20 — novidade tem prazo de validade.** O JP abriu “O que mudou” em agosto e encontrou uma semana de junho, incluindo um perfil do Vini Jr. que só continha “camisa” no sentido de jogador. A vitrine passa a se chamar **Tendências da semana** e não exibe como novidade leitura com mais de 21 dias. O histórico não é apagado: continua nos relatórios. Se não houver direção recente, a tela diz isso. Dado velho pode ser evidência histórica; não pode vestir a fantasia de atualização.
- `ADITIVA` | **A20 — estado ordena a vitrine.** Em alta · Destaques editoriais · Estáveis · Em queda passam a ser grupos explícitos. “Pico” continua sendo atenção de uma perna, não tendência confirmada. Nulo continua nulo: o pedido visual de reduzir “Sem estado” não autoriza inventar estabilidade onde busca e editorial BR não concordaram.
- `ADITIVA` | **A20 — estatística sustenta a frase, não protagoniza o produto.** “+1,56 desvios” deixa de ser o título. A intensidade em palavras vem primeiro; o valor na escala estatística sobre 12 semanas permanece na explicação auditável. A camada de apresentação pode preservar “bolinha” ou “poá” digitado pelo usuário enquanto o motor usa `geometrica`; isso não renomeia id, série nem gabarito.
- `ADITIVA` | **A20 — relevância editorial ganha uma trava estreita e testável.** Para `camisa`, um match exige contexto de moda no título ou uma segunda evidência de vestuário em título+resumo. O perfil “camisa 7” e metáforas como “vestir a camisa da empresa” viraram regressões. A regra não foi espalhada para todas as categorias sem medir recall. Antes de reprocessar histórico, precisa de amostra cega de pelo menos 100 matches, precisão ≥95% e recall ≥90%.
- `ADITIVA` | **A20 — ausência de produto não ganha placeholder.** O bloco final “Ainda sem cobertura — peças novas por combinação” saiu: não tinha cálculo, ação nem data de entrega. Pendência real fica no placar, não ocupando espaço na tela como promessa apaziguadora. O mesmo princípio passa a valer para os alertas provisórios do menu: tela visível precisa ter função ou conteúdo real.
- `ADITIVA` | **A20 — acabamento visual compartilhado.** Ellipsis e X passam a usar a mesma view, 62×62 e os mesmos recuos. O material do iOS 17 ganhou reflexão, dupla borda e sombras sem elevar o deployment target. Build e inspeção de simulador passaram; aprovação de transição e aparência no iPhone continua pendente, portanto não vira verde apenas por compilar.
- `ADITIVA` | **A20 — fontes novas são candidatas, não coleta autorizada.** Google Trends API alpha, Pinterest Trends, TikTok Creative Center e Lyst foram mapeados a partir de documentação oficial. Cada um mede fenômeno e cadência diferentes. Nenhum endpoint privado, automação de interface ou soma direta ao índice entra sem acesso documentado, termos, cobertura e papel metodológico medidos.
- `ADITIVA` | **A20 não revoga o inglês nem fecha a taxonomia por gosto.** A16 continua valendo. O app misto precisa de catálogo e revisão humana em inglês. `blusa_top` merece auditoria, inclusive de `camiseta`, mas a mudança exige definição visual exclusiva, volume, concordância humana, impacto nas séries e migração versionada; trocar um rótulo largo por várias classes frágeis não é curadoria.

### 13/08/2026 — fontes vivas, tela instantânea e vidro do sistema (A21)

- `ADITIVA` | **A21 — fonte atual não é sinônimo de estado atual.** Diagnóstico direto no banco: busca chega a 03/08 em 40 termos, mas poucas células editoriais têm z na mesma semana; a antiga tela selecionava a última linha que já tinha estado composto e fazia o Google parecer parado em julho. A abertura de Analytics separa três fenômenos: interesse de busca atual, manchetes atuais de moda e movimentos confirmados por duas fontes. Nenhum pulso isolado é promovido a tendência.
- `ADITIVA` | **A21 — o Trends respeita a própria cadência e a regra 7.** Segunda a quarta toleram uma semana de publicação; quinta em diante cobram a última semana fechada. Se todas as séries atingiram o corte, o coletor registra `adiado_por_cadencia` e faz zero chamadas. Depois de HTTP 429/5xx, abre circuito após um backoff real e deixa os outros grupos para outra janela; o pipeline não repete imediatamente uma fonte que acabou de recusar. O User-Agent volta a identificar `CanarioBot`, sem disfarce de Chrome.
- `ADITIVA` | **A21 — relevância editorial é requisito do título.** Título+resumo ainda casam atributos, mas o título precisa declarar uma peça ou intenção editorial de moda. Vini “camisa 7”, gravidez, viagem, UFC e metáfora empresarial são regressões. A semana mais nova publica zeros explícitos, de modo que corrigir o filtro também substitui uma célula falsa anterior; não basta deixar de acrescentar o erro. A amostra cega de 100 continua obrigatória antes de afirmar os pisos de precisão/recall.
- `ADITIVA` | **A21 — a primeira moldura não espera servidor.** A Home abre com dados locais e só aquece taxonomia e índices depois do primeiro frame. Taxonomia e índice usam snapshot persistente compartilhado, e uma chamada fria em curso é reutilizada por todas as telas. Analytics mostra o último snapshot no instante do toque e renova se ele passou de 15 minutos. No relatório da peça, cinco operações começam juntas; cada RPC ocupa e falha apenas na própria seção. Imagens remotas são limitadas a quatro conexões por host e reduzidas a 384 px antes de decodificar.
- `REVOGATÓRIA` | **A21 corrige a descrição de vidro da A18/A20.** `ultraThinMaterial` é blur translúcido, não Liquid Glass, e não pode produzir a refração dinâmica do sistema novo. Com SDK 26.2, aparelhos em iOS 26 usam `glassEffect`, `GlassEffectContainer` e `.buttonStyle(.glass)` nativos; iOS 17–25 preservam o fallback visual. O deployment target continua iOS 17. Ellipsis e X deixaram de ser duas views: um único controle na raiz troca só o símbolo, então posição e safe area são idênticas por construção.
- `ADITIVA` | **A21 — candidatas externas ficam separadas por fenômeno.** A documentação oficial deixa quatro decisões: Google Trends alpha continua a substituição prioritária, aguardando acesso; Pinterest Trends é a melhor candidata para um piloto de intenção visual, condicionado a Trial e `trends_read`; Guardian Open Platform é tecnicamente viável somente como veículo editorial; TikTok Research é inelegível para este produto no Brasil. YouTube e Wikimedia foram recusados como índice por ruído semântico. A matriz e links vivem em `FONTES_OFICIAIS_INTERNACIONAIS.md`; nenhuma candidata entrou no motor.

### 13/08/2026 — menu deixa de ser maquete (A22)

- `ADITIVA` | **A22 — ação visível precisa funcionar.** Os seis alertas provisórios do menu saem. Favorites lista peças marcadas e abre seus relatórios; Settings mostra e apaga o armazenamento local com confirmação; Privacy, Terms e Q&A descrevem o comportamento do binário e o método atual. Account não simula login: mostra quantidade local e diz, corretamente, que não existe conta nem sincronização nesta versão.
- `ADITIVA` | **Favorito é escolha do usuário, não número do motor.** `PecaSalva.favorita` é opcional para decodificar peças antigas e só é persistido depois do primeiro toque. A trava da §34 continua: índice, estado, z e semanas nunca entram na peça. O coração existe nos cards do Closet, e Favorites permite remover por gesto lateral.
- `ADITIVA` | **Texto de privacidade acompanha código, não intenção.** Embora A15 tenha autorizado a futura rota pela OpenAI, o binário de A22 ainda lê a imagem localmente e não possui chamada à API no runtime. Privacy declara exatamente isso e já registra a obrigação: o texto, a ficha da App Store e a exclusão de conta precisam mudar no mesmo commit que ligar análise remota ou sincronização.
- `VERIFICAÇÃO` | **A22 compilada e inspecionada.** 136 testes Swift passaram, o build completo de simulador com SDK 26.2 fechou e screenshots de Home/menu confirmaram ellipsis e X no mesmo centro. Terms e Privacy continuam sujeitos a revisão jurídica humana antes da submissão; código não transforma texto de produto em parecer legal.
- `ADITIVA` | **A22 — miniatura não bloqueia scroll.** Closet e Home deixaram de chamar `UIImage(data:)` dentro do `body`. A leitura e descompressão usam ImageIO em tarefa destacada, com teto de 384 px; Favorites não pré-carrega o armário inteiro e pede a imagem apenas quando a `List` materializa a linha. O arquivo local continua o mesmo e não perde qualidade persistida — o limite é só da apresentação.

### 13/08/2026 — feedback consolidado e navegação nativa (A23)

- `ADITIVA` | **A23 — o device fecha o bloqueio de performance.** O JP confirmou abertura muito mais rápida e uso aquecido adequado; resta somente uma leve hesitação no primeiro cold launch. Performance deixa de bloquear as telas. Reabre apenas com medição reproduzível, não por sensação isolada.
- `ADITIVA` | **A23 — a Tab Bar deixa de imitar o sistema.** No iOS 26, `TabView`, `Tab` com papel de Search e `.tabBarMinimizeBehavior(.onScrollDown)` fornecem o comportamento nativo do Apple Music e a safe area. iOS 17–25 mantém o fallback customizado. A barra nativa também impede que o último card seja coberto.
- `ADITIVA` | **A23 — categoria é o portão da foto.** OCR/cor local não podem transformar mão, fundo ou objeto em conjunto de atributos. Sem uma categoria de roupa reconhecida, nenhuma sugestão automática entra e o formulário começa por Category. Dimensões passam a depender da categoria: casaco não recebe cintura/silhueta/comprimento de vestido.
- `ADITIVA` | **A23 — reconhecer marca é enriquecimento, não prova.** OCR local de texto de marca é o baseline sem custo. Google Cloud Vision Logo/Web só pode entrar num experimento pareado contra Luna após disclosure e backend; wrappers de Google Lens por scraping não recebem foto privada na v1. Marca/logotipo nunca autorizam afirmar composição sem produto exato e ficha oficial.
- `ADITIVA` | **A23 — fontes internacionais novas ficam para v1.1.** O JP avaliou as candidatas oficiais e decidiu que custo de integração supera retorno antes da entrega. O arquivo de pesquisa permanece; não se substitui API oficial ausente por proxy, scraping ou automação de interface.
- `ADITIVA` | **A23 — feedback estrutural passa por protótipo.** Sidebar esquerda já aprovada e sheet direita sugerida por uma revisora são alternativas legítimas e conflitantes. Fluxo Add, menu e paleta serão comparados em protótipo com tarefas observáveis antes de nova troca estrutural. Bugs de contraste, alvo de toque, campos irrelevantes e linguagem não esperam esse teste.

### 13/08/2026 — calibração humana do Luna concluída (A17)

- `CORREÇÃO` | **O ouro foi auditado antes da inferência.** Os comentários dos três revisores e a construção visível corrigiram S01 e S03 de camisa para `blusa_top`, S11 de vestido para saia e S20 de vestido para camisa. Esta última corrige explicitamente a leitura histórica de 12/08: colarinho, carcela, botões e amarração com pontas livres sustentam camisa; não existe painel inferior inequívoco de vestido. O arquivo `auditoria-gabarito-v3.md` registra a razão de cada mudança e as respostas do modelo não participaram do voto.
- `CORREÇÃO` | **Preço oficial atual do Luna.** A página oficial consultada em 13/08 informa US$0,20 por milhão de tokens de entrada, US$0,02 em cache e US$1,20 de saída. A entrada de 11/08 com US$1,00/US$6,00 ficou desatualizada e não deve ser usada. O avaliador calcula as tarifas atuais e registra tokens por resposta.
- `VERIFICAÇÃO` | **O v4 falhou o portão:** 17/24 (70,8%) em categoria e 17/24 em cor. O diagnóstico foi excesso de abstenção em looks com várias peças, além de limites vestido/conjunto, saia/short e camisa/vestido. A rodada custou US$0,015997. Uma tentativa anterior consumiu cinco respostas (~US$0,006) e falhou num limite local de 120 caracteres; o avaliador agora grava cada resposta imediatamente e transforma saída inválida em erro auditável, sem pagar outra chamada para descobrir o que ocorreu.
- `ADITIVA` | **Prompt `alvo-estrutura-v5`.** A escolha do alvo usa evidências em ordem — completude, área/extensão, centro/detalhe e só então estilo/cor — e exige dois sinais independentes. Costura ou mudança de cor não prova duas peças; pontas livres de amarração não viram saia; tecido dourado não vira metal por causa do brilho. O conteúdo é travado pelo SHA-256 `f376aba99183b6c0277a856b7aaac3abe954bdb2016d3c20c31076fdfd6444c5`.
- `VERIFICAÇÃO` | **O v5 abriu o piso da A17:** categoria **20/24 (83,3%)**, cor primária **22/24 (91,7%)** e clareza do alvo 21/24 (87,5%). Foram 24/24 respostas válidas, US$0,018898, mediana 4,6 s e p95 7,3 s. `blusa_top` ficou 3/3; dividi-lo não resolve S10, S18, S20 nem S21. O portão técnico das 300 existe em `anexos/portao_luna_24.json`, mas o holdout não foi disparado porque categoria ainda está abaixo da meta de produto de 90% e retunar repetidamente as mesmas 24 criaria sobreajuste.
- `ADITIVA` | **A auditoria não exige novos créditos.** `relatorio-calibracao-v4.md`, `relatorio-calibracao-v5.md` e `respostas-calibracao-v5.jsonl` preservam métricas, matrizes, evidências visuais, tokens e todas as respostas sem chave nem `response_id`. As imagens continuam no pacote cego que os revisores receberam. As 300 seguem sendo holdout: excluem as 24 por código e só podem ser disparadas deliberadamente.

### 14/08/2026 — alvo humano antes da leitura e banco antes do limite (A24)

- `ADITIVA` | **A24 — instância visual antes de atributo.** Câmera e fototeca passam por `VNGenerateForegroundInstanceMaskRequest` no aparelho e mostram até quatro primeiros planos, ordenados por área e centralidade, mais a foto completa. A primeira opção pode vir pré-selecionada, mas nenhuma leitura começa sem o toque explícito em “Analyze this item”. O alvo confirmado — e somente ele — alimenta OCR, cor, semelhança e a miniatura do Closet. Vision separa instâncias; o usuário decide qual delas é a peça. A foto inteira permanece como saída segura quando a máscara corta roupa ou escolhe pessoa/objeto.
- `VERIFICAÇÃO` | **A24 — o aviso de 100% era real.** Consulta direta mediu 482.864.275 bytes contra o teto decimal de 500 MB. `produtos` ocupava 194 MB; `artigos`, 61 MB; `series_semanais`, 55 MB; `produto_termos`, 52 MB; `snapshots`, 43 MB. As tabelas de estágio tinham zero linha, nenhum motor ativo e 16,8 MB de índices residuais. A RPC guardada `preparar_stage_motor()` truncou só o estágio reconstruível e o banco caiu para 466.078.867 bytes (444 MiB), sem remover história.
- `ADITIVA` | **A24 — capacidade passa a ser porta de entrada, não autópsia.** `uso_do_banco()` devolve apenas o total agregado ao `service_role`; `anon` e `authenticated` não executam. Cada uma das quatro coletas mede antes de escrever: 85% gera aviso visível no Actions e 96% bloqueia a coleta, preservando 4% para operação. Limpeza de catálogo, artigos, snapshots ou séries exige plano de retenção e consequência metodológica; o pipeline não apaga evidência para caber.

### 14/08/2026 — corte de submissão e runtime seguro da A15 (A25)

- `ADITIVA` | **A15 só liga depois do backend inteiro.** A ponte iOS, a Edge Function e a migração de limite de custo existem, mas `REMOTE_ANALYSIS_ENABLED` nasce em `NO`. O app só pode mudar para `YES` depois de implantar a função e os secrets, fazer um teste real no device e conferir o formulário. Falhar remoto nunca remove o caminho local/manual.
- `ADITIVA` | **Consentimento por envio.** Depois de escolher visualmente a peça e antes de transmitir, o app nomeia OpenAI e Supabase, diz que envia somente a cópia reduzida sem metadados, informa a possível retenção de logs de abuso por até 30 dias e oferece continuar localmente. Aceitar uma vez não autoriza fotos futuras.
- `CORREÇÃO` | **Cor é da roupa, nunca da tela.** O cálculo local ignorava RGB de pixels transparentes e podia transformar o fundo removido em preto dominante. A mediana agora considera somente pixels com alpha suficiente. O fluxo oferece crop/zoom 3:4 e uma dica textual opcional de alvo; segmenta novamente após o recorte e só envia a cópia confirmada. Há regressão com peça azul opaca sobre fundo transparente.
- `ADITIVA` | **A17 liberada pelo JP apesar da meta aspiracional.** O piso combinado continua sendo 80%; 20/24 em categoria e 22/24 em cor o abriram. As 300 passam a exigir máscara Vision sem fallback para imagem bruta e excluem por hash a calibração. No iPhone o request separa instâncias; o i7 legado usa saliência compatível com o SDK e falha fechado. O resultado contra pasta de catálogo continua diagnóstico até adjudicação humana.
- `ADITIVA` | **Produto de submissão passa a se chamar DataDrobe.** A versão inicial é 1.0 (build 1), iPhone only e interface principal em inglês. Isso não muda ids históricos em português no banco, que são contrato interno e recebem rótulo apresentável na borda.
- `VERIFICAÇÃO` | **Links da loja foram auditados, não presumidos.** 262 destinos únicos foram visitados respeitando cadência e redirects; 183 não apresentaram sinal técnico. Foram encontrados 404, esgotado explícito e URLs administrativas da Maria Filó. A P7 converte o domínio para `www.mariafilo.com.br` e recusa similares antigos ou sem estoque; links mortos antigos deixam de ser clicáveis sem apagar o evento histórico.
- `ADITIVA` | **Publishable key não vira controle de gasto.** A função autentica a chave pública pelo modo `publishable`, mas reserva atomicamente um limite diário por origem pseudonimizada e um teto global antes da chamada paga. IP cru, imagem e resposta não entram nessa tabela; contadores com mais de sete dias são removidos.
- `CORREÇÃO` | **Zero VTEX preserva a causa.** O pipeline de 14/08 bloqueou porque Bo.Bo apareceu como zero sem motivo. O endpoint voltou a responder e provou falha transitória; o coletor agora registra status HTTP, contrato `Resources` ausente ou catálogo explicitamente zerado. Saúde continua bloqueando zero verdadeiramente inexplicado e converte recusa HTTP transitória em aviso conforme a regra já aprovada.
- `ADITIVA` | **Submissão ganhou portão próprio.** `APP_STORE_READINESS_14-08-2026.md` separa código verde de bloqueadores reais: deploy da visão, inglês/nome, assinatura Release, URLs públicas, metadata, termos de terceiros e TestFlight físico. Build de simulador não é sinônimo de app apto para revisão.

### 20/08/2026 — presença observada deixa de ser catálogo histórico (P17)

- `REVOGATÓRIA` | **B3 não autoriza presença eterna.** A gravação por delta continua, mas `primeiro_avistamento <= fim_da_semana` deixa de definir sozinho o sortimento. Um produto que entrou uma vez não pode permanecer no denominador de todas as semanas futuras. Cada snapshot confirma no máximo sete dias, a mesma cadência do batimento B3; sem nova confirmação o intervalo termina.
- `ADITIVA` | **Avistamento, snapshot e oferta são três sinais.** `ultimo_avistamento_em` anda em toda visita real; `ultimo_snapshot_em` continua andando apenas em mudança ou batimento; `ofertavel` exige ao menos uma variante ou seller comprável. Preço cadastrado sem estoque não prova oferta. O legado sem grade capaz de provar disponibilidade fica desconhecido, não é convertido silenciosamente em `false` nem incluído no painel atual.
- `CORREÇÃO` | **Share e raridade passam a usar oferta observada.** A série semanal conta uma peça uma vez quando ela esteve ofertável em ao menos um dia da semana dentro de um intervalo confirmado. A raridade do cluster usa apenas produtos ofertáveis avistados há no máximo sete dias. Materializações antigas que deixaram de existir são removidas por anti-junção na mesma transação; resultado vazio falha fechado e preserva a publicação anterior.
- `VERIFICAÇÃO` | **P17 aplicada e medida em produção em 21/08.** O checkpoint `pre-mudanca-20260820-presenca-oferta` preserva o estado anterior. Migração, coleta completa e publicação atômica terminaram verdes; a execução `a3480682-5e5f-4995-be20-b23336261144` publicou 84.297 produtos e 212.409 ligações. O denominador semanal caiu de 74.937 históricos para 25.160 ofertas confirmadas, com 25.270 ofertas atuais avistadas em até sete dias e zero estado atual desconhecido depois da reobservação. As 27 suítes Python e os 213 testes Swift passaram. A correção de presença não resolve a cobertura semântica: `liso` segue praticamente invisível e dimensões abaixo de 30% não podem ganhar linguagem confiante.

### 21/08/2026 — cobertura real, observabilidade semântica e corte 1.1 (P18/P19)

- `CORREÇÃO` | **C&A não tinha 66 mil ofertas escondidas.** As partições indivisíveis de R$ 0–1 na busca Legacy continham produtos indisponíveis ainda indexados. Quando uma faixa não pode mais ser dividida e passa do teto, o coletor consulta disponibilidade, mantém apenas o universo ofertável e registra quantos indisponíveis ficaram fora. Na coleta completa: 7.876 visitados = 7.876 declarados; 66.353 indisponíveis excluídos; nenhum truncamento.
- `CORREÇÃO` | **NV tinha sobreposição, não perda.** As categorias 2, 29 e 131 devolvem conjuntos sobrepostos cuja união é 563; somar as contagens produzia o falso denominador 1.329. A categoria vazia 138 saiu. A saúde agora compara contra a união única e fechou 563 = 563 sem alerta.
- `ADITIVA` | **P18 — confiança depende também da observabilidade da dimensão.** Cada célula de varejo carrega dimensão, número de peças com algum rótulo nela, denominador e percentual de cobertura. O portão conserva os pisos de 30 peças e 8 marcas e acrescenta cobertura mínima de 30%; metadado ausente falha fechado. Na publicação de 21/08, 23/40 células passaram — categoria, cor e tecido — e as 17 de comprimento, estética, estampa, silhueta e cintura ficaram sem linguagem confiante. `liso`, com 39 observações, não pode mais soar como conclusão sobre o mercado.
- `CORREÇÃO` | **P19 — similar precisa ser oferta recente.** A RPC deixou de aceitar snapshot de até 14 dias e agora exige simultaneamente `ofertavel = true` e avistamento nos últimos sete dias. O mesmo contrato de atualidade que alimenta o painel passa a proteger o link que o usuário toca.
- `ADITIVA` | **O próximo binário é 1.1 (build 2).** O gerador, o projeto e o teste de identidade concordam. Um String Catalog inicial reúne 150 chaves; PT-BR ainda não foi aberto e a A16 continua valendo. O alvo `CanarioUITests`, também gerado, cobre Add/menu, Closet e Privacy no iPhone 17 simulado e agora roda no CI.
- `VERIFICAÇÃO` | **A madrugada terminou verde e medida.** O pipeline `32448665712` executou VTEX, Shopify, editorial, Trends, saúde e motor em 52 minutos, sem recuperação. A publicação atômica `19b92240-eb02-45a2-99ef-3b512258bc1e` fechou com 84.298 produtos, 212.409 ligações, 25.162 ofertas no denominador semanal e zero estado recente desconhecido. Entre as 40 células, a maior mudança de share contra a medição anterior foi −0,0054 ponto percentual; a correção de cobertura não rompeu a série.
- `CORREÇÃO` | **Categoria VTEX vazia só é crítica quando todas são vazias.** Dress To ainda publica o ramo legado Lovedress (28), com zero produto, ao lado de dress to (58), que contém o catálogo vivo. O zero isolado passa a ser registrado até o fim da visita e não contamina uma coleta completa; se nenhum ramo devolver produto, o coletor continua emitindo erro crítico com a lista das categorias zeradas. A regressão cobre os dois lados.
- `VERIFICAÇÃO` | **Recuperação final fechou 15/15 sem corte.** C&A publicou 7.880 = 7.880 e separou 66.355 indisponíveis; Maria Filó 1.617 = 1.617; Dress To 6.628 = 6.628; Amaro 276 e PatBo 7.461 sem 429. A saúde `64e343e` declarou cobertura completa e nenhuma fonte obrigatória bloqueada. O motor `da258a9b-6e0a-4696-b99d-7247498f98b6` publicou 84.301 produtos, 212.415 ligações e as 193 células de varejo; o denominador semanal foi a 25.176 e `calca` moveu só +0,0019 ponto percentual.
- `VERIFICAÇÃO` | **O candidato 1.1 chegou ao TestFlight, não à revisão.** 226 testes Swift, 27 suítes Python e quatro fluxos de interface passaram; a camada Supabase ganhou contrato HTTP direto para GET, RPC, headers, 4xx e repetição única de 5xx. O Archive Release 1.1 (2) foi validado com Luna ligada, privacidade empacotada e assinatura íntegra. A exportação App Store e o upload foram aceitos às 09:18 de 21/08; o pacote entrou em processamento no TestFlight e nenhuma ação de App Review foi executada.

### 24/08/2026 — conta opcional e sincronização do Closet (A26)

- `REVOGATÓRIA` | **A26 revoga somente a proibição de login/conta da §34.** O JP autorizou explicitamente conta com Sign in with Apple, Google e e-mail/senha para permitir escala. A conta habilita restauração e sincronização dos dados estruturados do Closet; não transforma índice, estado, z-score ou série em dado persistido da peça. As demais exclusões da §34 continuam valendo até revogação própria.
- `ADITIVA` | **Conta não sequestra o aplicativo.** “Continue without an account” permanece disponível, usuários da 1.1 continuam vendo o Closet local e nenhuma peça é apagada ou escondida antes de uma autenticação concluída. O primeiro login faz merge por UUID entre o conjunto local e o remoto; nunca substitui silenciosamente um conjunto inteiro pelo outro.
- `ADITIVA` | **Offline-first é a garantia operacional.** Toda alteração confirma primeiro no armazenamento atômico local e entra numa fila idempotente para sincronização. Falha de rede ou de autenticação não bloqueia Add, Closet, Analytics nem relatórios já disponíveis. O servidor é réplica sincronizável, não condição para abrir o armário.
- `ADITIVA` | **Só sobe o que a conta promete.** Apelido, ids da taxonomia, preço-alvo, canal, data de criação, favorito e rejeição explícita de similares podem sincronizar. ~~Miniatura e foto continuam neste iPhone na primeira entrega;~~ `[EMENDADO em 25/08/2026 por A44: a miniatura reduzida e sem metadados passa a sincronizar em bucket privado do próprio auth.uid; a foto original continua sem sair do aparelho.]` nenhum caminho local, arquivo, EXIF, número calculado ou resposta da OpenAI entra na tabela do usuário.
- `ADITIVA` | **Identidade é isolada por política, não por convenção.** Toda linha sincronizada referencia `auth.users(id) on delete cascade`, tem RLS obrigatória por `auth.uid()` e nenhuma chave administrativa entra no binário. Testes com dois usuários precisam provar leitura, escrita e exclusão cruzadas impossíveis antes do deploy.
- `ADITIVA` | **Excluir conta é parte da conta.** A tela Account oferece logout e exclusão integral dentro do app. A exclusão remove dados remotos, cache local daquela identidade e credenciais do chaveiro; Sign in with Apple também revoga a autorização aplicável. Desativação, e-mail para suporte ou simples logout não substituem exclusão.
- `ADITIVA` | **Privacidade acompanha o mesmo commit funcional.** O manifesto, a política pública, a ficha da App Store e a tela Privacy passam a declarar identificadores de conta vinculados ao usuário e sincronização do Closet quando o primeiro fluxo remoto for ligado. Até o backend e os provedores estarem configurados, o app falha aberto para o modo local e não simula conta conectada.

### 24/08/2026 — direção internacional sem romper a coorte (A35)

- `ADITIVA` | **Regra 5 permanece de pé.** Doen, Rouje, Staud, Faithfull the Brand e With Jean passaram novamente pelo catálogo público Shopify, em série e respeitando a regra 7. Elas entram em `direcao_intl`, nunca em `feminino_casual_br`; portanto não alteram denominador, share, raridade ou z-score da coorte brasileira congelada.
- `CORREÇÃO` | **O motor deixa de apagar segmentos.** Até A35, a coleta e o schema eram multissegmento, mas `motor_atributos.py` carimbava todo produto elegível como `feminino_casual_br`. A publicação atômica agora usa o segmento configurado da marca como fallback B4 e preserva esse valor na linha autoritativa do produto.
- `ADITIVA` | **Coleta e saúde têm escopo explícito.** `COLETA_SEGMENTO` nasce com default brasileiro, de modo que o pipeline diário continua observando exatamente a coorte de 30/07. A direção internacional ganha workflow manual próprio e conserva métricas de saúde no banco sem reescrever `SAUDE.md` nem participar do portão da v1.
- `ADITIVA` | **Cinco fontes ainda não autorizam índice.** O catálogo já pode sustentar exploração e similares rastreáveis, mas o mínimo metodológico de oito marcas da §8 continua obrigatório para qualquer número de painel ou estado em `direcao_intl`. Escassez permanece declarada; marca internacional não é licença para produzir uma estatística frágil.
- `ADITIVA` | **A36 — Closet encontrável sem servidor.** Busca por nome/atributo e filtro por favoritos e taxonomia rodam sobre a cópia local, inclusive offline. Dimensões combinam por AND e alternativas da mesma dimensão por OR, a mesma semântica adotada na calibração de similares; nenhum filtro vira preferência de perfil nem dado novo sincronizado.

### 24/08/2026 — produção verificável sem abrir o banco (A37)

- `ADITIVA` | **A37 — isolamento de painel é um portão operacional.** Um workflow manual somente de leitura mede capacidade e conta, por marca, produtos dentro e fora do segmento solicitado usando `service_role` apenas no runner. A chave publishable do app continua incapaz de fazer essa auditoria, RLS não é relaxada para conveniência e qualquer produto de uma marca do painel gravado fora do segmento faz a verificação falhar.

### 25/08/2026 — catálogo amplo sem adulterar o painel (A38–A40)

- `ADITIVA` | **A38 — Pattern é uma dimensão só na interface.** `motivo_estampa` continua sendo metadado preciso do motor, mas deixa de aparecer como uma segunda taxonomia ao usuário. Animal print vem primeiro; estampa conversacional reúne objetos, alimentos, plantas e símbolos reconhecíveis; malha e tricô/crochê aparecem como “Knit & crochet”. Waist passa a oferecer cintura alta, média e baixa.
- `CORREÇÃO` | **A39 — Farm é um caso real de canonicidade e cobertura.** Links públicos alternam `secure.farmrio.com.br` e `www.farmrio.com.br`; a busca passa a resolver os dois pelo mesmo slug, preservando query stripping e limite de URL. O formulário não descarta mais `motivo_estampa`. Quando um motivo reconhecível existe, ele ancora os similares entre categorias e o texto declara que a categoria foi relaxada. Tomate devolveu 13 ofertas, 3 marcas e 12 cards, sem chamada à OpenAI.
- `ADITIVA` | **A40 — marca candidata amplia produto, não estatística.** As candidatas brasileiras vivem em `catalogo_candidato_br`. Elas podem aparecer com foto, preço, fonte e atributos em similares, mas não entram em `feminino_casual_br`; portanto não alteram share, cobertura, raridade, índice ou z-score durante a temporada. Promoção ao painel medido continua exigindo virada explícita e recomputação.
- `ADITIVA` | **Manutenção tem custo zero e portão.** A coleta candidata reutiliza a cadência global, robots, estado estreito e portão de 96% do banco. Roda duas vezes por semana para não vencer a atualidade de sete dias; Malwee permanece inativa (`pendente`) até a expansão provar folga real. Uma coleta candidata nunca reabre o pente fino de 72 domínios.
- `CORREÇÃO` | **Os três menus são literalmente um componente.** Add, Closet e Weekly Trends usam `BotaoDoMenu` no mesmo placement de toolbar. Compare escolhe a semana mais recente com cobertura útil, oferece também termos medidos apenas no painel e não reduz a interface a duas opções porque uma única perna externa atrasou. A busca do Closet recolhe no gesto ascendente quando vazia.

### 25/08/2026 — editorial feminino recomposto sem estado parcial (A41)

- `ADITIVA` | **Arquivo e série voltam a ser coisas separadas.** Coletor diário e backfill podem ampliar somente `artigos`, preservando a série viva. Depois, `reclassificar_editorial.py` lê o arquivo completo, aplica a mesma regra de gênero por título no passado e no presente e troca BR e internacional inteiras, uma perna por transação. O app nunca enxerga uma mistura de série velha com cauda nova.
- `ADITIVA` | **Termo novo nasce na primeira evidência.** A recomputação não fabrica zeros antes de uma taxonomia existir. Se não havia série anterior, a primeira semana com artigo realmente casado define o início; ausência posterior continua sendo zero auditável, com contagem, denominador e exemplos.
- `ADITIVA` | **Escassez se resolve com fonte feminina, não com falso positivo.** Entram Claudia, Marie Claire US, The Zoe Report, W, Glamour US, Fashion Gone Rogue, Fashion Bomb Daily, Tom and Lorenzo, Fashion Week Daily e Red Carpet Fashion Awards. As fontes WordPress com arquivo profundo são retroalimentadas por até cinco anos; RSS só contribui a partir do que foi realmente observado.
- `ADITIVA` | **Luna não aprende a prova por repetição.** O contrato v10 já conhece conversacional e as três cinturas, mas não substitui a função de produção sem amostra nova. As mesmas 24 imagens não serão compradas outra vez; cinco casos difíceis permanecem erro conhecido. Texto livre visual continua fora das séries e o formulário humano continua sendo o dado final.

### 25/08/2026 — capacidade e recall editorial sem armazenar matéria (A42–A43)

- `ADITIVA` | **A42 — o piso seguro vira a retenção normal.** Eventos e curva de tamanhos usam no máximo 14 dias de snapshots crus. O motor conserva 21 dias, com uma semana adicional para atraso de coleta, e nunca poda `series_semanais`. A compactação inicial removeu 93.587 linhas fora da janela e levou o banco de 485.747.859 para 419.269.779 bytes; a série histórica permaneceu intacta.
- `CORREÇÃO` | **A43 — resumo volta a melhorar recall sem virar conteúdo armazenado.** A especificação sempre mandou casar título + resumo e persistir uma linha por artigo/termo, mas a implementação recente havia reduzido o histórico ao título para torná-lo reproduzível. Feed e backfill agora processam o resumo em memória e gravam apenas o par compacto em `artigo_termos`; texto integral e resumo continuam fora do banco.
- `ADITIVA` | **Recomputação usa evidência persistida.** `reclassificar_editorial.py` prefere os pares compactos e só recorre ao título para artigo legado ainda não reprocessado. Assim a mesma evidência alimenta passado e presente, o filtro de gênero continua uniforme e ampliar vocabulário não exige guardar obra protegida.
- `CORREÇÃO` | **Produto excluído não é contaminação.** O portão de painéis distingue produto sem segmento, recusado pelo recorte de população, de produto atribuído a outro painel. Só o segundo é vazamento. Nas 12 marcas candidatas, 14.678 produtos ficaram no catálogo candidato, 1.698 foram excluídos e zero foi atribuído a outro segmento.

### 25/08/2026 — miniatura restaurável e URL exata em todos os painéis (A44–A45)

- `REVOGATÓRIA` | **A44 emenda a cláusula “miniatura e foto continuam neste iPhone” do A26.** Aquela frase dizia “na primeira entrega”, e a primeira entrega acabou: reinstalar o app devolvia o Closet sem imagem, o que faz a restauração prometida pela conta parecer quebrada. Passa a subir **uma miniatura por peça, reduzida a no máximo 720 px no maior lado, recodificada num bitmap novo e sem metadados**. A **foto original continua sem sair do aparelho, em qualquer caminho** — esta emenda não a libera, e nenhuma outra pode liberá-la sem revogação própria.
- `ADITIVA` | **A44 — a miniatura é do dono, por política.** O objeto vive em `closet-thumbnails`, num caminho cujo primeiro componente é o próprio `auth.uid()`, com as quatro operações sob RLS, teto de 3 MB e apenas `image/jpeg` e `image/png`. O app confere o checksum antes de aceitar um download: byte que não bate com o hash gravado é descartado em vez de virar a foto de outra peça. Sem conta, nada disso existe — o Closet de convidado continua confinado ao aparelho.
- `CORREÇÃO` | **A44 — apagar a conta apaga a imagem.** `deleteUser` derruba `closet_items` por cascade, mas **não toca em objeto de bucket**: a purga do prefixo do usuário roda **antes** da exclusão, e a exclusão falha aberta se a purga falhar, para não deixar arquivo órfão sem dono para reclamá-lo. Apagar uma peça apaga a miniatura dela pelo mesmo caminho.
- `ADITIVA` | **A44 — declaração de privacidade é parte do commit, não pós-processo.** Ligar o Storage move `Photos or Videos` para **vinculado ao usuário** no manifesto, na ficha da App Store e na política pública ao mesmo tempo. `coletor/teste_privacidade_declarada.py` passa a reprovar o push quando código, manifesto, ficha, política e `excluir-conta` discordarem — a divergência de 25/08, em que o binário sincronizava e dois documentos públicos negavam, não pode reaparecer em silêncio.
- `ADITIVA` | **A45 — resolver URL não é privilégio do painel medido.** A busca por URL exata passa a valer nos segmentos brasileiro e candidato, por índice, preservando o corte de query e o limite de tamanho. Isso amplia o que a pessoa consegue colar sem chamar a Luna; **não** promove produto candidato a `feminino_casual_br` nem altera denominador, share, raridade, índice ou z-score. O que o A40 separou continua separado.

### 26/08/2026 — interface que não trava é requisito medido (A46)

- `ADITIVA` | **A46 — filtro de armário é lógica, e lógica mora no pacote.** O JP, no teste físico de 25/08: *"Aplicativo ta travando MUITO e muito lento"*. A causa era `rotulos`/`categorias`/`termosPorId` como **propriedades computadas** dentro do `body`: cada leitura percorria a taxonomia inteira, e elas eram lidas de dentro do laço de filtragem e três vezes por card. Medido com o armário no teto de 200 peças e 212 termos, vinte passagens do `body` — o equivalente a vinte teclas digitadas na busca — construíam **84.000 dicionários** e levavam **3,215 s**; com o catálogo montado uma vez, **0,023 s**. São **142×**, e o número de antes é ~161 ms por tecla numa máquina rápida.
- `ADITIVA` | **A46 — a regra que faltava.** "Tela se verifica olhando, lógica se verifica testando" tinha uma brecha: filtro, busca e rotulagem do Closet eram lógica escondida numa View, e por isso nunca foram medidos. `CatalogoDoArmario` e `FiltroDoArmario` passam a viver em `CanarioLogica`, com teste de comportamento (AND entre dimensões, OR dentro da dimensão, `motivo_estampa` dentro de `estampa`, id fora da taxonomia ignorado) e um **orçamento de interação**: vinte filtragens do armário cheio em menos de 1 s, ou o portão reprova.
- `CORREÇÃO` | **A46 — espera longa é dita, não disfarçada.** O teto do pedido da análise remota é 30 s, e a tela afirmava *"usually takes a few seconds"* durante os 30. Passados 8 segundos, o texto passa a dizer que está demorando, que o pedido para sozinho e que Close continua disponível. Isso não acelera nada e não finge acelerar: separa "demorando" de "travado", que é o que a pessoa não conseguia distinguir.
- `CORREÇÃO` | **A46 — verde por ausência é pior que vermelho.** `-only-testing` com um nome inexistente não falha: o `xcodebuild` roda zero testes e devolve `** TEST SUCCEEDED **`. `testFillInfoAbreClothingDetailsForaDaSheet` nunca existiu, estava listado como um dos cinco fluxos offline protegidos do CI e nunca rodou — justamente o fluxo Fill Info → Clothing Details que o JP pediu. O nome correto é `testConfirmacaoFinalSalvaSemTelaRepetidaDeClothingDetails`, e `teste_workflows.py` passa a exigir que todo identificador pedido por `-only-testing` exista no arquivo de testes. Cobertura afirmada e não executada é a mesma classe de defeito que a documentação que contradiz o binário.
- `CORREÇÃO` | **A48 — seis frutas não são uma dimensão.** A A31 criou `motivo_estampa` com tomate, cereja, morango, banana, abacaxi e melancia. Medido na produção em 26/08: cereja devolve 24 peças em 9 marcas, banana 24 em 2, morango 22 em 3, tomate 12 em 3, abacaxi 5 em 2 e **melancia 0** — um termo aprovado que nunca casou uma peça. E o que falta é maior que o que existe: não há azeitona, abacate, limão, sardinha, coração, estrela nem borboleta, e as três últimas estão nomeadas dentro do `palavras_en` do próprio `conversacional`. Os seis passam a `status = 'reprovado'`, o guarda-chuva `conversacional` cobre a família inteira e é exibido como **Illustrated prints** — o termo de mercado "conversational print" saiu por reprovar no teste mais simples que existe: o dono do projeto perguntou o que era. Nenhum índice, z-score, raridade ou série é tocado: estes termos nasceram com `sem_perna_busca = true`. Fazer direito seria vocabulário aberto de motivos, com "outras frutas", legumes e bichos desenhados; é projeto de virada de temporada, não seis linhas.
- `ADITIVA` | **A46 — o `+` do Add é conferido por geometria, não por opinião.** O botão foi relatado torto duas vezes. A primeira correção centrou o `+` no desenho (de 27 unidades para 1), mas o quadro `0 0 108 232` tem centro em 54 enquanto o eixo do manequim é 50: `scaledToFit` centraliza o quadro, não a tinta. Com `viewBox="-4 0 108 232"` e o disco azul concêntrico ao glifo, quadro, manequim, disco e `+` ficam todos em **x = 50,000**. `teste_experiencia_app.py` compara os dois números a cada push.
