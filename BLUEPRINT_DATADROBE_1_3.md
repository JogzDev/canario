# DataDrobe 1.3 — blueprint de produto e execução

Versão 1, 05/09/2026. Documento de execução, não declaração de funcionalidades
já entregues. O estado verificável de cada pacote fica em `EXECUCAO_1_3.md`.

## 1. Decisão de produto

Construir um radar de moda feminina que una **panorama curto, aprofundamento
rastreável e conversa sobre as evidências**. A Luna organiza e explica; o
DataDrobe conserva as fontes, calcula números e explicita os limites.

A pergunta central é: **o que merece minha atenção agora, onde apareceu, o que
isso tem a ver com o Brasil e como posso conferir?** Não é “o que produzir para
vender mais”. O produto informa decisões sem prometer resultados comerciais.

O primeiro recorte continua moda feminina casual/social brasileira, mid-market.
Referências internacionais são contexto identificado, não amostra representativa
do mercado brasileiro. A persona comercial existente permanece prioritária;
estilistas e pequenos empreendedores entram na validação exploratória, sem
redefinir silenciosamente a persona aprovada em `CANARIO.md`.

Esta blueprint detalha e estende a ordem de execução de
`MARKET_INTELLIGENCE_1_3.md`. Não revoga as regras de não previsão, direitos,
taxonomia aprovada, cobertura mínima e rastreabilidade. Não altera as regras da
1.2 nem autoriza serviços pagos, publicação ou acesso ao banco de produção.

## 2. O que aproveitamos da conversa de referência

A [conversa compartilhada pelo JP](https://chatgpt.com/share/6a958b07-531c-83e9-ae88-b0767f7f7ed6)
é referência de desejos e experiência, não dataset nem especificação jurídica.
As afirmações de mercado e os números ilustrativos dela não serão importados
como fatos atuais.

| Desejo | Tradução em produto | Limite que precisamos preservar |
|---|---|---|
| Panorama de cores e combinações | Brief com observações e relações entre cores | Cor isolada não comprova combinação num look |
| Estampas, cortes, caimento e modelagem | Conceitos separados, com exemplos e fronteiras | Imagem pode sugerir aparência, não comprovar construção invisível |
| Composição da etiqueta | Fibra, percentual e parte da peça quando declarados | Cetim não significa seda; mistura não vira fibra única |
| Texturas, acabamentos e peso | Campos diferentes para aparência, acabamento e gramatura declarada | Não medir gramatura pela fotografia |
| Styling, proporções e acessórios | Relações peça–peça e contexto de uso | Coocorrência em artigos diferentes não prova styling |
| Creators que realmente analisam moda | Painel curado de autores, com especialidade, território e vieses | Seguidores e engajamento não são autoridade nem demanda |
| Passarelas, vitrines, tênis e eurosummer | Contextos de observação com data do evento e lugar | Evento europeu não representa automaticamente o Brasil |
| Pinterest, Instagram e TikTok | Adaptadores e permissões separados por plataforma | Sem scraping proibido, senha compartilhada ou bypass |
| O que muda no Brasil | Comparação lado a lado de sensores compatíveis | Não inferir que Europa causou adoção brasileira |
| O que perdeu força | Séries comparáveis e contradições explícitas | Falha do coletor não é arrefecimento |
| Uma conversa tão boa quanto a referência | Respostas úteis, verificáveis e aprofundáveis | Fluência não substitui fonte; sem inventar citações |

Não adotaremos os scores hipotéticos de 0–100, percentuais de “chance de chegar
ao Brasil”, previsões de venda ou quantidades recomendadas da conversa. Também
não afirmaremos que o produto é inédito: diferenciação é hipótese a validar.

## 3. Experiência final, em quatro superfícies

### 3.1 Radar da quinzena

Uma abertura de duas ou três frases e, por padrão, três a cinco temas em cerca
de 300–600 palavras no total. É orçamento editorial, não requisito para
preencher uma edição fraca. Pode haver um tema ou nenhuma edição nova.

Cada tema responde: **observação → ambiente e período → Brasil → ressalva →
fontes**. A leitura de dois minutos deve fazer sentido sem abrir os detalhes.
Um tema não precisa ter todos os sensores; precisa declarar os ausentes.

Estados de interface: carregando, edição disponível, edição anterior ainda
válida, sem edição por cobertura insuficiente, offline com data do cache,
conteúdo corrigido e conteúdo retirado. “Sem novidade” não se confunde com erro.

### 3.2 Dossiê do tema

Definição visual/textual; fatos de suporte, contradição e contexto; território;
fontes canônicas; datas de publicação, evento e observação; unidades e
denominadores; limites de comparação; método e revisões. O usuário chega aqui
tocando uma frase do brief, sem procurar qual dos links a sustentava.

### 3.3 Histórico e comparação

Edições e observações anteriores, preservando correções. A interface distingue
“visto pela primeira vez neste painel” de “surgiu no mercado”. Novos sensores
começam com história zero. Não desenhar curvas onde só existe uma observação.

### 3.4 Conversa com a Luna

Perguntas iniciais: “E no Brasil?”, “O que sustenta isso?”, “E a composição?”,
“Há alguma fonte discordando?”, “O que mudou desde a edição anterior?” e
“Qual recorte você não acompanha?”. A resposta herda o tema, o período e o
território, mas mostra esses filtros e permite corrigi-los.

A primeira conversa consulta somente corpus aprovado e vigente. Não navega
livremente, não consulta rascunhos e não usa dados privados de outro usuário.
Uma pergunta sem base recebe uma lacuna específica e o que seria necessário
observar, não uma resposta de conhecimento geral apresentada como radar atual.
Sem agentes em loop, memória pessoal persistente ou inferência de idade/renda.

## 4. Fronteiras da versão

**Incluído na 1.3 privada:** Etiqueta e varejo descritivos, uma trilha externa
efetivamente utilizável, brief, dossiê, histórico, conversa ancorada, revisão,
auditoria, custos e operações. A cobertura de cada sensor estará identificada.

**Condicionado a acesso verificável:** busca, plataformas sociais, imagens de
passarela e vitrines. Um mock de Pinterest não conta como integração Pinterest.

**Depois da validação:** Android, oferta comercial, billing, organizações e
equipes, exportações profissionais, idiomas adicionais e personalização de
marca. Contratos independentes do cliente preparam esse caminho; não se
construirá uma segunda interface ou sistema de cobrança neste pacote.

**Excluído:** publicação automática no piloto, previsão de venda, instruções de
produção, cópia de matérias, galerias sem licença, scraping de área autenticada,
inferência de composição por imagem e alterações na 1.2.

## 5. Estado inicial comprovado e dívida reconhecida

Baseline de implementação: commit `6f6eac207ee7784ae89c1124b82b3867483efb7d`,
branch anterior `codex/1.3-luna-market-intelligence`. Recuperado no worktree
permanente `Canario-1.3-blueprint`, branch `codex/1.3-blueprint`, porque o checkout
temporário em `/private/tmp` perdeu arquivos. Arquivos remanescentes não foram
apagados e mudanças locais da `main` não foram transportadas nem sobrescritas.

Já existe código de fundação SQL A51/A52, governança de fontes, Scout privado,
parser/materializador de Etiqueta, revisão cega, adjudicação e consolidação.
Isso não comprova implantação, revisão humana real ou um radar comercial.

O consolidado continua `private_human_reviewed_candidates`, com
`requires_concept_review=true` e `evidence_staging_allowed=false`. O próximo
passo cria um recibo separado; não reescreve esse artefato para aparentar licença.

Lacunas estruturais descobertas na revisão:

1. Só a curadoria interna está `green`; nenhuma fonte externa utilizável pode
   ser presumida. A trilha de conteúdo externo começa em paralelo ao backend.
2. A51 usa URL única por fonte em item imutável. Reobservações semanais precisam
   de entidade canônica separada da observação versionada.
3. A unicidade da evidência inclui execução. Precisamos de identidade lógica
   independente da tentativa para impedir duplicação em reprocessamento.
4. A51 liga leitura a evidências, não cada afirmação nem edição ordenada.
5. O conceito guarda estado atual; mudar volume observado dispara invalidação
   ampla. Contadores operacionais não devem alterar o contrato semântico.
6. Expiração/cascatas ainda não demonstram o tombstone mínimo de auditoria
   prometido. Direito de apagar conteúdo vence a conveniência do histórico.
7. O enum de estágio mistura cobertura, geografia e dinâmica temporal.
8. Testes estáticos de SQL não demonstram transações, permissões ou concorrência.

P1 resolve o fluxo mínimo e a idempotência local. P2/P3 resolvem as estruturas de
reobservação, conceito, afirmação e edição antes de ampliação. Não vamos
refatorar todo o sistema antes de provar uma passagem completa.

## 6. Arquitetura e limites de responsabilidade

| Camada | Responsabilidade | Não pode fazer |
|---|---|---|
| Registro de fontes | Direitos, métodos, escopo, validade e retenção | Se autopromover por encontrar página pública |
| Adaptador/Scout | Descobrir candidatos no escopo permitido | Aprovar fonte ou publicar |
| Normalizador | Canonicalizar, datar, deduplicar, registrar origem | Somar republicações como confirmação independente |
| Extrator | Fatos explícitos com trecho/proveniência | Inferir fibra, causalidade ou compra |
| Revisor factual | Confirmar, rejeitar, abster-se | Criar conceito aprovado por consequência |
| Registro conceitual | Definições/revisões semânticas | Misturar mínimo conceitual e mínimo de tendência |
| Admissor | Validar cadeia e gravar drafts atomicamente | Revisar/aprovar/publicar ou alterar legado |
| Agregador | Contagens, cobertura e comparação reproduzíveis | Delegar cálculo de porcentagens ao modelo |
| Redator Luna | Explicar fatos admitidos e organizar temas | Navegar ou introduzir informação fora do pacote |
| Revisor editorial | Aceitar conjunto texto/fontes/limites | Ignorar falha de direito, cobertura ou verificador |
| Publicador | Transição auditável para corpus privado/público autorizado | Publicar por simples sucesso do job |
| App/conversa | Ler corpus permitido para o público correto | Acessar credencial de serviço ou rascunhos internos |

Implementação inicial: módulos Python existentes + PostgreSQL + contratos JSON;
jobs finitos. Sem Kafka, microserviços, banco vetorial ou framework multiagente
por antecipação. Busca lexical e filtros estruturados primeiro; só acrescentar
recuperação semântica se a avaliação identificar uma limitação concreta.

## 7. Modelo de evidência e identidade

Entidades necessárias: fonte/revisão de autorização; execução/tentativa;
entidade canônica; observação imutável; fato candidato; sujeito/submissão de
revisão; conceito/revisão; admissão; evidência; afirmação; leitura/revisão;
edição com ordem; decisão editorial; retirada; recibo de custo.

Hashes comprovam integridade entre artefatos, não identidade humana nem
legitimidade de uma fonte. A âncora precisa vir de processo confiável com acesso
separado do escritor. No laboratório ela é um bootstrap sintético explícito;
no piloto real, autenticação nominal e decisão persistida serão obrigatórias.

Uma ocorrência é selecionada por `fact_id` exato, nunca por “o primeiro algodão”.
O sujeito cego pode representar várias ocorrências; compartilhar revisão não
transforma todas em uma única peça nem multiplica o suporte independente.

Identidade lógica é distinta de tentativa e de hash do manifesto. Repetir o
mesmo conteúdo devolve o recibo existente; mudar conteúdo sob a mesma identidade
gera conflito sem sobrescrita. Nova metodologia ou revisão semântica gera nova
identidade com relação explícita à anterior. Hora da execução não é identidade.

Observações diferentes da mesma URL preservam data, hash e método; a entidade
canônica agrupa o histórico. Uma republicação mantém referência à família de
origem. A independência editorial considera autor/publicação/origem subjacente,
não apenas domínios distintos nem o número de URLs.

## 8. Taxonomia e revisão de conceitos

Famílias: categoria, cor, estampa, fibra, construção têxtil, acabamento, textura,
peso aparente, silhueta, caimento, comprimento, detalhe construtivo, styling,
acessório, ocasião e estética. Relações de look são próprias, não novos sinônimos.

Cada conceito possui ID estável, definição operacional, aliases PT/EN,
fronteiras, exemplos positivos e negativos, protocolo de promoção versionado,
unidade e suporte verificável. Nome parecido não é equivalência automática.

Três aprovações diferentes: **o trecho sustenta o fato; o conceito está bem
definido; o conjunto sustenta a afirmação editorial**. Um algodão corretamente
extraído não é uma tendência de algodão. Conceitos aprovados são reutilizados
na mesma versão; não exigimos reaprová-los a cada etiqueta.

Mínimos de produção serão especificados e congelados por protocolo antes de
avaliar os candidatos reais. Não serão reduzidos para fazer um candidato passar.
Fixtures locais usam um protocolo exclusivamente sintético, nunca aprovação do
JP. Mudanças semânticas preservam versões anteriores e reavaliam dependências;
mudança em contador operacional não revoga por si só conteúdo válido.

## 9. Medição, tempo e Brasil

Armazenar timestamps em UTC e apresentar fuso; recortes editoriais usam
America/Sao_Paulo. Não confundir publicação, data do evento, primeira captura e
última observação. Recorte temporal usa limites explícitos, preferencialmente
intervalos semiabertos nos agregadores novos.

Default: janela recente de sete dias fechados contra os sete dias imediatamente
anteriores; 28 dias anteriores como baseline auxiliar normalizado; 30 dias como
contexto editorial, não denominador intercambiável. Quinzenalidade do brief não
muda silenciosamente a janela da métrica. Sem comparação de semana parcial.

Cada medida expõe numerador, denominador, unidade, população elegível, parte
observável, abstensões, marcas/fontes ativas e versão do painel. Denominador
zero resulta em nulo. Produto com duas fibras pode contar em duas incidências;
esses shares não precisam somar 100%. Percentuais da composição de uma peça são
outra medida e distinguem tecido principal, forro e detalhes.

Separar: presença absoluta; incidência dentro do painel; distribuição entre
marcas; intensidade de menção; volume/índice de busca. Nunca somar sensores
heterogêneos. Mudança de preço compara unidade, moeda e população compatíveis;
indisponibilidade/restock/markdown não são quantidade vendida.

Comparabilidade exige mesmo sensor, método, unidade, território, janela e painel
ou interseção declarada com cobertura suficiente. Indisponibilidade de fonte
produz quebra de cobertura, não zero nem `cooling`. Preservam-se os mínimos
existentes da 1.2; protocolos novos não alteram suas séries.

Separar internamente três eixos:

- **suficiência:** insuficiente / suficiente para a alegação delimitada;
- **presença:** observações por território e sensor;
- **dinâmica:** estável / ganhou presença / perdeu presença / divergente /
  não comparável, somente quando houver série adequada.

O estágio atual pode ser mantido como resumo de compatibilidade até migração
explícita. `global_only` deve ser exibido como “observado no exterior; sem
confirmação brasileira neste corpus”, não “não existe no Brasil”. Definir
“early” e “broad” por protocolo antes de liberar esses rótulos; até lá,
`insufficient` ou descrição factual limitada. Duas fontes independentes são
um piso editorial, não prova automática de difusão de mercado.

## 10. Frente de fontes externas: trabalho em paralelo, não promessa

O inventário de acesso será uma matriz de **desejo × método permitido × direitos
de IA × exibição × retenção × cobertura × custo × responsável × próximo ato**.
Reaproveitar o registro existente, sem promover `yellow/red` por conveniência.

Prioridade de investigação: fontes primárias/editoriais acessíveis legalmente,
metadados licenciados e acordos simples; depois creators consentidos, feeds de
eventos/acervos, busca e APIs de plataformas. Não prometer ordem de ativação de
uma plataforma que depende de aprovação externa. URLs de Instagram, TikTok ou
Pinterest continuam referências de descoberta enquanto o método não for aprovado.

O painel exploratório inicial de creators pode ter 8–12 candidatos diversos,
incluindo autores menores com análise técnica. Avaliar especialidade,
originalidade, consistência, território, publicidade e repetição de pauta.
Tamanho do painel é limite de trabalho, não amostra estatística. Contas citadas
na conversa são candidatas, não endosso nem autorização de coleta.

Metadados e links podem gerar uma agenda de pesquisa. Snippet e título sozinhos
não comprovam uma análise factual de composição, modelagem ou difusão. Curadoria
própria não “lava” direitos de texto/foto de terceiros. Acesso público não é
permissão irrestrita de processamento, armazenamento e redistribuição.

Saída verificável desta frente: ao menos uma fonte externa realmente admitida
por método autorizado, ou relatório específico da restrição e alternativa
permitida. Se nenhuma existir, o produto será declarado “Etiqueta/varejo interno
em laboratório”, não “radar internacional pronto”. O desenvolvimento restante
prossegue com fixtures explícitas; não se finge cobertura.

## 11. Luna: três contratos, sem agente onipotente

**Scout:** descobre candidatos dentro da allowlist e teto já definidos; não
promove fatos. **Redator:** recebe corpus minimizado aprovado e produz afirmações
com IDs. **Conversa:** recupera evidências vigentes para pergunta/recorte e
responde usando esse mesmo contrato. Permissões e recibos são separados.

Saída estruturada inclui texto, afirmações, IDs de suporte/contradição/contexto,
recorte, lacunas e motivo de abstenção. Schema válido não garante que a afirmação
seja verdadeira; checar completude/recusa e validar conteúdo separadamente.
Base técnica: [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

Verificador determinístico: IDs existem e foram enviados; fonte/consentimento
vigentes; números, unidades, datas e recortes correspondem ao cálculo; nenhum
link inventado; sem acesso a drafts; vocabulário indevido; limites de comprimento.
Revisão semântica humana cobre inferências e sustentação que regex não prova.
Falha gera fallback factual ou abstenção, não loop de tentativas pagas.

Conteúdo externo é dado não confiável: instruções em páginas não alteram prompt,
ferramentas ou permissões. Redator e conversa não possuem ferramentas de escrita,
segredos de coleta nem acesso arbitrário à rede. URLs resolvidas pelo backend,
com controle de redirects/host/IP para evitar SSRF.

Modelo, versão, prompt, schema, retrieval, corpus, política de custo e resultado
da avaliação ficam versionados. A Luna é a primeira opção desejada pelo JP;
disponibilidade, ID de API e preço são conferidos antes de habilitar chamadas.
Não confundir assinatura/créditos do Codex com orçamento da API do produto.

`store=false` não significa retenção zero. Compatibilidade de cada fonte deve
considerar os controles reais do projeto e os logs padrão; MAM/ZDR não serão
declarados sem habilitação verificável. Ver [controles de dados da OpenAI](https://developers.openai.com/api/docs/guides/your-data).

## 12. Custos e cadência operacional

Coleta/candidatos semanais; edição revisada quinzenal; retrospectiva mensal.
Rotinas serão criadas no ambiente 1.3 apenas após testes e autorização de seus
alvos. O trabalho atual não cria cron nem automação pessoal para retomar sessões.

Teto pago atual: **zero**. Desenvolvimento usa cálculos locais e respostas de
teste identificadas. Antes da API: teto por execução e mês, moedas/preços
versionados, limites de entrada/saída/chamadas, projeto dedicado e chave server-side.
Orçamento exato é uma decisão financeira pontual futura, não motivo para parar P1.

Estimativa reproduzível: tokens de entrada × tarifa + tokens de saída × tarifa +
ferramentas + tentativas com cobrança possível. Reservar teto atomicamente antes
da chamada; reconciliar uso real, manter reserva em resultado incerto e impedir
segunda cobrança automática por timeout. Cache por conteúdo/método; alterações de
direitos invalidam cache. Emitir custo por edição, por tema aceito e por pergunta.

No início, dupla revisão cega mede extração, não cada frase para sempre. As
primeiras 12 edições publicáveis continuam com revisão integral. Em cadência
quinzenal isso representa aproximadamente 24 semanas de edições, **não quatro**.
Quatro semanas bastam para teste operacional inicial, não para comprovar toda
a qualidade editorial ou comportamento sazonal. Não encurtar essa regra em silêncio.

## 13. Ordem de construção e portões de saída

Os pacotes encerram unidades verificáveis. Não se volta a redesenhar o projeto a
cada sessão; detalhes locais e defeitos entram no pacote correspondente.

| Pacote | Construção, na ordem | Saída verificável | Dependência |
|---|---|---|---|
| P0 — recuperação e contrato | Recuperar baseline; registrar blueprint, isolamento, estado e testes | Checkout permanente e roteiro reproduzível | Concluído ao registrar documentos |
| P1 — uma passagem inteira | Fixture pelo parser real; reconsolidar revisão; dossiê separado; selecionar ocorrência; manifesto; PostgreSQL real; draft/recibo; testes adversos | Exatamente uma evidência e uma leitura `insufficient`, privadas e idempotentes | P0 |
| P2 — dados duráveis | Separar entidade/observação; revisões de conceito; chave lógica; expiração/tombstones; import privado autorizado; identidade real de revisão | Reprocessamento e reobservação seguros sem tocar legado | P1 |
| F1 — fontes utilizáveis | Inventário; verificar método/direitos; adaptador; corpus mínimo; avaliação de cobertura | Sensor externo real ou bloqueio documentado sem promoção artificial | Paralelo a P1/P2 |
| P3 — afirmações e edição | Claims e vínculos; dedup origem; recortes; métricas; três eixos; ordenar temas; histórico/correções | Edição determinística curta, com frase→evidência→origem | P2; F1 para alegação internacional |
| P4 — Luna avaliada | Redator estruturado; verificador; baseline cego; abstenção; recibos/limites; prompt injection | Ganho editorial demonstrado sem perda factual | P3; autorização de custo antes de chamada |
| P5 — experiência privada | Radar, dossiê, histórico, conversa; estados; acessibilidade; cache e retirada | Fluxo completo no build privado e contrato de consulta reutilizável | P3; P4 para redação/conversa assistida |
| P6 — piloto real | Quatro semanas operacionais; revisão/custo/cobertura; entrevistas; correções; continuação das 12 edições revisadas | Relatório de utilidade e limites com decisões baseadas em evidência | F1 + P4/P5 |
| P7 — liberação separada | Hardening, direitos, privacidade, observabilidade, rollback, loja | Go/no-go de release com autorização explícita | P6; produção permanece congelada até decisão nova |

### P1 — checklist completo do pacote iniciado agora

1. Executar baseline focal e preservar hashes/branch da 1.2.
2. Criar laboratório em diretório próprio, ignorado pelo Git para dados/runtime.
3. Subir PostgreSQL real efêmero, sem `.env`, URL remota ou credencial Supabase.
4. Aplicar A51 somente nesse banco; usar stubs mínimos para dependências legadas.
5. Gerar etiquetas sintéticas através do materializador e parser existentes.
6. Gerar submissões de teste explicitamente simuladas e consolidar pelo código
   de revisão real, sem chamar simulação de julgamento independente humano.
7. Reabrir cadeia original, recomputar consolidado e comparar integralmente.
8. Validar dossiê e revisão conceitual separados; mínimos e exemplos do protocolo
   sintético; rejeitar fatos não confirmados e escolha ambígua.
9. Criar manifesto imutável com identidade lógica, todos os hashes necessários,
   versão de conceito/método/template, destino e ocorrência exata.
10. Registrar âncora pelo bootstrap confiável; escritor restrito não a cria.
11. Gravar coleta, extração, briefing, item, evidência draft, leitura draft,
    vínculo e recibo em uma transação. A cardinalidade factual é um; três
    execuções representam funções diferentes, não três fontes.
12. Repetir, competir em duas conexões, interromper/rolar transação, variar
    conteúdo, expirar direito, alterar conceito e testar negativas de privilégio.
13. Verificar que `anon`/`authenticated` não veem draft e o escritor não revisa,
    publica, muda fonte, modifica legado nem fabrica âncora.
14. Gerar demonstração textual marcada FICTÍCIO, comandos, logs e recibo, sem
    colocar dados de teste em tela da versão enviada à Apple.
15. Encerrar processo PostgreSQL, registrar testes, revisar diff e checkpoint
    apenas na branch 1.3. Ausência de PostgreSQL/teste não conta como teste verde.

### P2 — antes de importar volume

Migrações aditivas na branch, ensaiadas do zero e de um snapshot sintético do
schema anterior; nenhum reset remoto. Catálogo de entidades/observações, revisões
semânticas, decisões autenticadas, recebimento imutável, migração de referências,
backfill determinístico, rollback lógico e testes de leitura anterior.

Dados reais para laboratório só de ambiente independente ou exportação
deliberadamente autorizada e minimizada. “Ambiente lab” com `SUPABASE_URL` genérica
não prova isolamento. Não executar o workflow manual antigo até seus destinos,
credenciais e permissões serem inequivocamente separados da produção.

### P3/P4 — antes de uma frase bonita

Primeiro edição determinística e conjunto de avaliação; depois Luna sobre os
mesmos insumos. Ordenação inicial por relevância ao recorte, recência, cobertura
e diversidade, com motivos legíveis; não por score de sucesso de mercado.
Contradição relevante acompanha o tema; não fica escondida numa lista de fontes.

Versionar edições, ordem, texto, claims e links. Correção não sobrescreve história
silenciosamente. Retirada invalida corpus de conversa, cache e exibição; conservar
apenas metadados cuja retenção seja permitida. Não prometer recuperação de texto
cuja licença obriga eliminação.

### P5 — integração sem regredir o app

Não redesenhar as telas estáveis da 1.2 para acoplar o radar. Rota e feature flag
privadas, backend próprio e estados desacoplados. Reusar tokens aprovados da
paleta; cobrir loading, navegação, retorno, modais, safe areas e transições.
Conferir tamanhos de fonte, VoiceOver, contraste, Reduce Motion e telas pequenas.

Testar rede lenta/offline, token expirado, logout, edição retirada, corpus vazio,
pergunta longa, fonte indisponível e interrupção da resposta. Contratos JSON e
API independem de SwiftUI; Android poderá reutilizar dados, não necessariamente
o código de interface. Nenhuma promessa de “port automático”.

## 14. Avaliação: o que deve ser medido

Datasets separados para desenvolvimento, validação e holdout; agrupamento por
origem/assinatura/período para evitar trechos duplicados em lados diferentes.
Fixtures testam regras; material real autorizado testa distribuição do problema.
Ambos identificados. Nunca declarar acurácia real com exemplos gerados por nós.

| Área | Teste/medida | Portão |
|---|---|---|
| Integridade | Alterar fato, hash, revisão, rubrica, destino ou conceito | Toda adulteração da suíte deve falhar sem escrita parcial |
| Isolamento | Escritor, usuário anônimo/autenticado, rede e legado | Zero caminho demonstrado para draft público ou produção |
| Extração | Precisão/recall por família e motivo de abstenção | Amostra, intervalos e erros apresentados; limiar congelado antes de holdout |
| Proveniência | Afirmação→evidência vigente→origem | 100% das afirmações publicadas com suporte auditável |
| Números | Recalcular cada número/data/unidade/denominador | Zero discrepância tolerada no conteúdo admitido |
| Semântica | Revisor verifica se evidência realmente sustenta texto | Zero erro crítico conhecido; revisão integral nas primeiras edições |
| Editorial | Comparação cega baseline × Luna no mesmo corpus | Melhora de utilidade/clareza sem piora factual; reportar tamanho da amostra |
| Conversa | Questões respondíveis, ambíguas, adversas e sem evidência | Abstenção específica; nenhuma fonte inventada ou draft recuperado |
| Operação | Reexecução, concorrência, timeout, expiração, mudança de direitos | Idempotência e retirada verificadas; alertas acionáveis |
| Custo | Reserva, execução incerta, uso real, teto mensal | Sem estouro provocado por retry/corrida; sem custo oculto |
| Experiência | Encontrar fonte, entender limite, completar pergunta | Testes de tarefa observados, não só opinião “gostei” |

Erros críticos: número/fonte inventados, direito violado, vazamento, previsão de
venda, inferência de compra a partir de estoque, geografia falsa ou fonte expirada
exibida como vigente. Erros menores de redação não têm o mesmo peso.

Para calibrar qualidade, seguir avaliação específica por tarefa, comparação
controlada e avaliação contínua, não impressão subjetiva de fluência. Referência:
[boas práticas de avaliação](https://developers.openai.com/api/docs/guides/evaluation-best-practices).
Um resultado perfeito em amostra pequena não prova taxa de erro zero no mundo.

## 15. Piloto, utilidade e produto comercial

Recrutar um pequeno grupo exploratório de pessoas do recorte, inicialmente
3–5 quando disponíveis. Número é meta de recrutamento, não significância
estatística nem autorização para contatar pessoas sem pedido. Perguntar sobre
decisão real recente, observar consulta e verificação da fonte, registrar o que
faltou e retorno espontâneo. Não medir sucesso por elogio ao texto.

Medidas: tempo para encontrar evidência; compreensão correta das lacunas;
perguntas efetivamente respondidas; motivos de retorno; tema salvo/consultado;
custo e minutos humanos por edição. Instrumentação agregada e mínima, sem
analytics publicitário ou gravação de conteúdo sensível por padrão.

No fim de quatro semanas: continuar, restringir recorte ou corrigir fundamento.
Conversão, disposição de pagar e diferenciação exigem validação própria;
não são consequência automática de um pipeline verde. Só então definir pacotes
comerciais e comparar custo por cliente com receita hipotética explícita.

## 16. Segurança, retenção e operação

Ambientes com bancos, chaves, identidades e permissões separados. O executor
rotineiro não recebe `service_role` com funções de revisão/publicação. CI não
herda segredos de produção; PR de origem não confiável nunca recebe credenciais.
Dependências fixadas e revisadas. Logs guardam IDs, hashes, tempos e classes de
erro; não tokens, corpos integrais, perguntas pessoais ou etiquetas brutas.

Coleta segue o limite global e etiqueta existentes. Cache, backoff com teto,
jitter e respeito a `Retry-After`; circuit breaker para origem com falhas;
interromper em proibição, não insistir para contornar. Retentativa determinística
não cria nova evidência. Não esconder falha como execução de sucesso vazia.

Pruning tem dry-run, alvos exatos, contagem, teste de dependências e evidência de
remoção. Auditoria mínima não é desculpa para reter conteúdo proibido. Backup e
restore do ambiente privado são ensaiados antes de dados reais persistentes.
Rastrear falha de job, idade do corpus, queda de cobertura, custo e retirada
incompleta. Alertar só mudança acionável, sem notificações repetidas de estado igual.

## 17. Forma de trabalhar daqui em diante

Cada sessão começa pelo estado, Git/diff e testes pendentes; termina com
arquivos/commit, comandos e resultados, limitações e próximo passo exato. Nada
importante vive apenas no chat ou em `/tmp`. Interrupção por limite não exige
refazer a arquitetura nem faz um teste incompleto virar aprovado.

Subagentes assumem arquivos/frentes não concorrentes; revisão cruzada antes do
checkpoint. O responsável principal integra e verifica. Indisponibilidade de
agente não paralisa tarefas independentes nem justifica alegar revisão feita.

Só reabrir decisão estrutural por: evidência de inviabilidade; direito/acesso
incompatível; risco de segurança; resultado do piloto; custo material; mudança
explícita de objetivo. Registrar alteração e impacto em vez de apagar a versão
anterior. Ajuste de função/teste/layout dentro do contrato não exige nova reunião.

Intervenções pontuais futuras do JP: aprovação real de conceito/fonte quando
necessária, teto financeiro, ajuda em autenticação que exija presença e decisão
de liberar produção. Todas as tarefas seguras independentes continuam enquanto
uma dessas decisões estiver pendente. Não pedir autorização para cada teste.

## 18. Definição de pronto

**P1 pronto** significa uma passagem local demonstrada, com dados sintéticos,
transação, idempotência e privacidade testadas. Não significa radar real pronto.

**1.3 privada pronta para piloto** significa fonte real suficiente para as
alegações exibidas, edição rastreável, conversa que sabe se abster, avaliação,
direitos/custos controlados e experiência testada de ponta a ponta.

**Pronta para distribuir** exige ainda decisão explícita de release, testes
físicos, privacidade/metadados, credenciais, revisão de acesso, rollback e
aceitação dos limites. Esta blueprint não autoriza merge em `main`, alteração
de produção ou novo envio à App Store. A 1.2 permanece congelada.
