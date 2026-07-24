# CANÁRIO — Documento Base do Projeto

**Versão:** 1.0 | **Data:** 23/07/2026 | **Autores:** João Pedro (JP), Davi e Bianca, com consultoria de pesquisa e estruturação via Claude
**Status:** especificação ativa. Este documento é a fonte da verdade do projeto. O agente (Claude Code) trata tudo aqui como lei; o que não estiver aqui, pergunta antes de assumir.
**Codinome:** "Canário" é provisório. Usar sempre como token isolado (nome do projeto, do diretório, do target, bundle id `com.canario.app`), nunca embutido em frases de texto de interface, para que a troca pelo nome definitivo seja uma operação única de find-and-replace.

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
7. **Etiqueta de coleta.** Máximo 1 requisição por segundo por domínio, coleta de madrugada (horário de Brasília), cache agressivo, só páginas públicas, robots.txt respeitado, User-Agent identificável (`CanarioBot/1.0 (projeto academico; contato: email-do-time)`). Nunca burlar autenticação ou proteção anti-bot.
8. **A foto da peça nunca sai do dispositivo.** Processamento de imagem on-device. Nuvem só como opt-in explícito e está fora da v1.
9. **Segredos nunca no repositório.** Chaves e tokens vivem em GitHub Secrets (coletores) e na configuração local (app). Commit com segredo é incidente: rotacionar a chave imediatamente.
10. **Servidor calcula, app consulta, câmera fica local.** O app nunca coleta nem computa índice; ele lê séries prontas.
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
3. **Consulta ao vivo "verde e lilás no masculino":** funciona como demonstração de honestidade do sistema: as pernas de busca e editorial respondem (o tema está documentado na imprensa de moda), e a perna de varejo exibe "cobertura insuficiente" porque o segmento masculino não está no painel v1. O app mostrando o próprio limite é parte do pitch.
4. **Roteiro:** o cliente (por exemplo, Lorena) digita a busca ao vivo. Nada de exemplo pré-cozido. Narrativa ancorada no calendário real da coleção Alto Verão 28 da Farm: desenvolvimento de estampa iniciando 07/ago/26, aprovação de visual 19/jan/27, provão 16/mar/27, mostruário a partir de 05/fev/27, venda atacado 25/jun/27, lançamento 06/out/27, lead time total 341 dias. O app entra na janela do comercial: entre aprovação de visual, provão e mostruário.

Consequência do calendário: o ciclo completo da AV28 não fecha dentro do Academy. A validação do índice é **retroativa** (seção 31), e a AV28 serve como acompanhamento ao vivo, não como prova.

---

## PARTE 2 — DADOS E CONHECIMENTO

### 11. Taxonomia (o vocabulário comum do sistema)

A taxonomia é uma **lista fechada de 35 termos** organizados em 6 dimensões. Ela é o contrato entre a foto, a busca, o Trends, o coletor e o motor. Vive no arquivo `anexos/taxonomia.csv`, versionado no repositório.

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
- **Multimarca é multiplicador com ressalva:** a ruptura num multimarca fala da compra daquele lojista, não da demanda total da marca. Vale como comparação relativa entre marcas dentro da mesma vitrine (mesmo público, mesmo tráfego). Etiquetar os dados com origem multimarca e nunca misturar com leitura de site próprio sem distinção.
- **Marcas do grupo Azzas** (Farm, Animale, Maria Filó, Fábula, NV, Foxton) entram com papel `grupo`: são autobenchmark para o cliente, nunca contam como "mercado externo" nos índices.
- **Painel de direção** (Misci, Zimmermann, Ganni, Réalisation Par, Sézane, Dôen, calendários de passarela): sem bot de estoque. O sinal é frequência de atributo no que publicam. Estoque de grife é escassez deliberada, não demanda.
- Cada marca tem uma linha de justificativa escrita (coluna própria). É a resposta pronta para "por que essas marcas?".
- Congelamento por temporada (regra inviolável 5). Marca nova entra com história zero e fica fora das comparações até acumular o mínimo de semanas.

### 14. Veículos editoriais

Vivem em `anexos/veiculos.csv`. Critérios de permanência: publica no mínimo semanalmente, fala de produto e tendência (não só celebridade), tem arquivo com profundidade. Regra do time: **somente veículos famosos e confiáveis de moda**; a lista pode crescer, não encolher, e adições passam pelo JP. Viés a declarar nos insumos do relatório: veículo de moda vive de publicidade de marca, então o sinal editorial carrega inclinação comercial. Editorial é sempre **direção**, nunca medição.

### 15. Sazonalidade e calendário

- O motor **nunca armazena estação**; armazena semana e mês. Estação é etiqueta de exibição configurável por conta: preset `PV/OI` (primavera-verão / outono-inverno) e preset `Azzas` (verão, alto verão, inverno, alto inverno). O mapeamento oficial de meses para as sub-coleções do Azzas é pergunta aberta ao cliente (seção 36); até lá, usar aproximação declarada como aproximação.
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

SwiftUI, iOS 17 como mínimo, iPhone primeiro. Idioma da interface: PT-BR apenas na v1. Gráficos com Swift Charts. Dependências de terceiros: mínimas e justificadas uma a uma. Coletores em Python 3.11+ na pasta `/coletor` do mesmo repositório. Distribuição: TestFlight interno (time) e depois externo (Pedro, Lorena, Victor); App Store não é obrigação do projeto.

### 27. Estrutura em 3 abas

- **Analisar:** entrada por busca textual (principal) ou upload de foto (opcional). Três campos de contexto opcionais que nunca bloqueiam: preço-alvo (gera percentil contra similares), canal (varejo/atacado), janela de entrada em loja (gera leitura sazonal). Saída: o relatório da peça (seção 29).
- **Explorar:** valor de esforço zero na abertura. Blocos: ruptura da semana (clusters e marcas com mais quebra, excluindo continuativos), reposições da semana (destaque editorial: é o sinal mais forte), novidades por cluster, e o digest do que mudou. Filtros por segmento.
- **Comparar:** o usuário seleciona 2 a 6 peças analisadas e recebe ranking relativo imediato, com uma linha de motivo por peça (nunca só o número). Disclaimer fixo na tela: "Ranking relativo entre as suas peças, calculado agora sobre dados já coletados. Não é previsão de venda." Peça clássica aparece com badge e leitura própria (preço e oferta), avisando que aquecimento não se aplica. Salvar comparação é opcional e discreto.

**Estados vazios e de erro (obrigatórios):** cobertura insuficiente (mensagem honesta + o que dá para mostrar); coletor atrasado (exibir sempre a data/hora da última coleta junto aos números); offline (servir o cache da última sincronização com carimbo visível "dados de DD/MM HH:MM"); termo fora da taxonomia (resposta honesta + termos próximos).

**Vocabulário de interface:** estados sem duração no título (`em alta`, `estável`, `em queda`, `pico`; janelas de tempo vão para a letra miúda dos insumos). Palavras proibidas: a lista negra da seção 6, mais "provão" (não existe no produto), "atualizada hoje" e equivalentes que sugiram cultivo/espera.

### 28. Entrada por imagem e visão computacional

- **Fluxo:** upload → tela de formulário onde o usuário confirma/corrige os atributos. O humano no circuito é o que derruba a exigência de acurácia da visão.
- **v0:** formulário primeiro; visão é conveniência de pré-preenchimento apenas se disponível e confiável.
- **Evolução:** dataset a partir das imagens do próprio coletor, rotuladas pelos títulos dos produtos (títulos de e-commerce são etiquetas quase prontas). Treinar classificador multirrótulo no Create ML. **Critério de aceitação para a visão poder pré-preencher:** concordância ≥ 80% com etiquetagem humana em categoria e cor, num conjunto de teste de 100 peças que o time rotula à mão.
- **Privacidade:** processamento on-device (Vision/Core ML). A foto é processada e descartada; retenção zero por padrão (miniatura local opcional, apagável pelo usuário). Nada de nuvem na v1. Tags sempre editáveis.

### 29. Relatório da peça

Ordem dos blocos, de cima para baixo:
1. **Parágrafo-resumo por template determinístico.** Frases pré-escritas com slots preenchidos exclusivamente por valores computados pelo motor. Exemplo de template: "No painel de {n_marcas} marcas, encontrei {n_similares} similares: {pct_preco_cheio}% a preço cheio e {pct_grade_quebrada}% com grade quebrando {formato}. A busca por {termo} está {estado} ({variacao} em {janela})." Proibido LLM na v1. `[LLM como redator com coleira: apenas v2, recebendo só números computados, com lista negra de vocabulário e números-fonte visíveis ao lado]`
2. **Atributos da peça** (chips editáveis, com o índice individual de cada um).
3. **Índice do cluster + estado + minigráfico**, com as pernas ativas declaradas.
4. **Insumos, um bloco por fator:** sites/varejo (similares com preço, remarcação e estado da grade, sempre; N, faixa de preço, formato da quebra), sazonalidade (Trends, na etiqueta de estação da conta), cores, modelagem, composição. Cada bloco com fonte, data de coleta e link.
5. **Contexto condicional** (se o usuário preencheu): percentil de preço, leitura da janela de entrada.
6. **Limites declarados:** "Não consideramos: seu histórico de vendas, seus custos, sua capacidade de produção. Sinal editorial carrega viés comercial de publicidade."
Rastreabilidade (regra inviolável 3) em todos os números.

### 30. Referências internas (opcional, por cliente)

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

**Fluxo:** GitHub Actions (cron) → coletores Python → Supabase (Postgres) → app SwiftUI lê séries computadas via API do Supabase (chave anônima somente leitura, políticas RLS de leitura pública nas views computadas; chave de serviço só nos GitHub Secrets). Em uma frase: **servidor calcula, app consulta, câmera fica local.**

- **GitHub:** conta e repositório **privado** criados pelo JP (tarefa humana); autenticação do agente via `gh auth login` (OAuth local, token no chaveiro, segundo fator permanece ligado; nunca senha em texto). Free tier: 2.000 minutos/mês em repo privado, muito acima do consumo estimado (~10 min/dia). Limite de gasto padrão zero: jobs param em vez de gerar cobrança.
- **Três pegadinhas do agendador, mitigadas:** (1) cron é sempre UTC: madrugada BRT ~03:00 = `0 6 * * *` UTC; (2) workflows agendados desativam após 60 dias de inatividade do repo: o commit diário do `SAUDE.md` resolve; (3) não há notificação de falha: o relatório de saúde é o alarme. Atrasos de 10 a 30 minutos em pico são irrelevantes para o caso.
- **Supabase:** conta e projeto criados pelo JP (tarefa humana); o agente escreve schema, migrações e políticas. Verificar a política vigente de pausa de projetos inativos no plano gratuito; o toque diário do cron tende a manter o projeto ativo, mas confirmar.
- **Fases e execução:** F0 tarefa zero → F1 fundação (repo, secrets, schema, materialização dos anexos CSV) → F2 coletores + saúde (prioridade absoluta; varejo primeiro) → F3 motor → F4 app esqueleto de 3 abas lendo séries reais → F5 relatório da peça + Comparar → F6 laço de validação + termômetro → F7 polimento + TestFlight. Nenhuma fase começa antes da anterior passar nos critérios de aceitação. Coleta nunca sai do ar durante as fases seguintes.

### 34. Anti-escopo da v0/v1 (não construir)

Sem login/conta de usuário, sem push notification, sem closet/monitoramento contínuo por peça, sem modo offline completo (apenas cache da última sincronização), sem multi-idioma, sem Android/web, sem LLM no relatório, sem Instagram/TikTok, sem pagamentos, sem painel administrativo web. Agente que "adiantar" qualquer um desses itens está violando o documento.

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
