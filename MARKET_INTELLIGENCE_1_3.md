# Market Intelligence 1.3 — contrato de produto

## Resultado que a versão deve entregar

A 1.3 adiciona ao DataDrobe um radar curto de moda feminina que responde, com
evidência rastreável:

1. o que ganhou presença recentemente;
2. em qual ambiente isso foi observado;
3. se o sinal chegou ou não ao Brasil;
4. o que contradiz ou limita a leitura;
5. quais fontes e datas sustentam cada frase.

O radar descreve o presente. Ele não prevê venda, não recomenda volume de
produção e não chama uma publicação, lançamento ou peça indisponível de adoção.

## Cadência aprovada para o piloto

- **semanal:** coleta e geração privada de candidatos;
- **quinzenal:** briefing editorial, somente depois de revisão humana;
- **mensal:** retrospectiva de cobertura, fontes, falsos positivos, custo e
  mudanças de método.

As primeiras quatro semanas são laboratório privado. As primeiras 12 edições
publicáveis exigem revisão integral. Não existe publicação automática nesta
fase. A cadência pode ser reduzida quando a cobertura for insuficiente; não se
preenche uma edição com sinal fraco só para cumprir calendário.

## O que a pessoa verá

Cada leitura publicada precisa conter:

- título descritivo e resumo curto;
- estágio observado;
- período e território;
- evidências de suporte, contradição e contexto;
- cobertura disponível e lacunas explícitas;
- links canônicos e atribuição;
- data de atualização e versão da metodologia.

Estágios são rótulos de cobertura, não probabilidades:

| Estágio | Significado permitido |
|---|---|
| `global_only` | observado fora do Brasil, sem confirmação brasileira |
| `br_editorial_observed` | apareceu em cobertura editorial brasileira |
| `br_search_observed` | apareceu no sensor brasileiro de busca |
| `br_retail_early` | presença inicial no varejo brasileiro medido |
| `br_retail_broad` | presença distribuída no varejo brasileiro medido |
| `cooling` | os sensores comparáveis perderam presença |
| `divergent` | sensores contemporâneos apontam em direções diferentes |
| `insufficient` | cobertura insuficiente para outra classificação |

“Passarela”, “creator”, “busca”, “editorial” e “varejo” continuam sensores
distintos. Eles não são somados como se tivessem o mesmo denominador.

## Arquitetura de confiança

```text
registro de direitos -> descoberta -> item canônico -> extração factual
        -> evidência draft -> revisão humana -> leitura draft -> publicação
```

- O registro de fontes falha fechado.
- A promoção a `green` exige bloco indivisível de aprovação nominal, datas e
  SHA-256 da evidência autorizadora; autorização vencida bloqueia a execução.
- Descoberta e snippet produzem candidato, nunca evidência.
- Conteúdo integral só chega a IA quando a fonte autoriza esse processamento.
- `store=false` não é tratado como retenção zero: o gate exige compatibilidade
  com os logs padrão de até 30 dias. MAM/ZDR só entram numa futura revisão do
  schema com o projeto administrativo efetivamente verificado.
- Pacotes `facts` já vêm minimizados; o redator Luna não navega a partir deles.
- Números e datas são validados deterministicamente.
- Toda evidência começa `draft` e é imutável depois da revisão.
- Toda leitura começa `draft`; a publicação é uma transição auditável.
- Revogação de direitos retira leituras afetadas.
- Drafts e metadados temporários expiram; a trilha de uma leitura publicada é
  preservada no mínimo necessário para auditoria.

O contrato jurídico e operacional detalhado vive em
`GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md`; a lista executável vive em
`anexos/fontes_radar.csv`.

## Funções da Luna

Há duas funções separadas, com prompts, artefatos e permissões diferentes:

### Scout privado

Descobre no máximo oito páginas candidatas dentro de uma allowlist. Usa busca
somente quando o registro autoriza processamento integral por IA e declara
explicitamente `hosted_web_search_domain_tree` para toda a árvore do domínio.
API, RSS e host/prefixo limitado exigem adaptador próprio. A saída é
`candidate_only`, privada, temporária e obrigatoriamente revisada. Credencial e
projeto são dedicados; um recibo metadata-only nasce antes do POST e distingue
com precisão bloqueio sem custo de chamada iniciada com cobrança possível.
Na fundação inicial, a única retenção OpenAI executável para conteúdo enviado é
`standard_30d`; `none` significa que nenhum conteúdo daquela fonte vai ao
modelo. MAM/ZDR dependem de uma revisão futura do schema e de verificação real
do projeto, nunca de uma declaração unilateral no CSV.
O request fixa `service_tier=default`, que é o literal da Responses API para o
preço/desempenho padrão, e rejeita uma resposta resolvida em outro tier. Modelo,
projeto, usage, chamadas web, versão de preços e teto conservador de custo ficam
no recibo mesmo quando o candidato falha no portão semântico.

### Redator privado

Recebe apenas evidências aprovadas e fatos estruturados. Pode resumir,
organizar e apontar contradições; não pode inventar número, data, fonte,
causalidade ou previsão. Cada oração publicável precisa ser remontável aos IDs
de evidência recebidos. Falha de validação usa texto determinístico, não uma
segunda chamada paga automática.

## Sensores e ordem de entrada

1. **Etiqueta DataDrobe:** catálogo próprio já observado, materializado por
   regras determinísticas. É o primeiro baseline porque já existe e tem
   proveniência controlada.
2. **Varejo brasileiro:** presença, amplitude por marcas e movimento dentro do
   painel; indisponibilidade não é interpretada como venda.
3. **Busca:** interesse agregado, quando a API/método estiver autorizado e
   estável.
4. **Editorial:** cobertura de veículos licenciados ou metadados e links dentro
   do escopo permitido.
5. **Passarela e vitrines:** somente feeds, APIs, acervos ou curadoria com
   direitos documentados.
6. **Creators e redes sociais:** apenas APIs oficiais, contas consentidas ou
   acordos específicos. Instagram, TikTok e scraping social não entram como
   atalho.

Pinterest, Guardian, YouTube e Google Trends permanecem `yellow` ou `red` até o
registro conter autorização suficiente. A existência de uma API ou de uma
página pública não promove a fonte.

### Primeiro pacote factual da Etiqueta

O materializador inicial lê, por uma RPC privada e paginada, somente peças do
segmento brasileiro que estejam ofertáveis e tenham sido avistadas nos últimos
sete dias. Usa a etiqueta de composição mais recente ainda presente na janela
de 21 dias dos snapshots. Descrição de marketing, imagem, grade, preço e URL não
entram no pacote.

O texto integral existe apenas em memória durante o parse. O artefato guarda o
hash da etiqueta, trechos-fonte curtos, fatos `candidate_fact`, abstensões,
avisos e denominadores explícitos. Share de uma faceta usa somente produtos em
que aquela dimensão foi observável; a cobertura contra todos os elegíveis fica
separada. O resultado é `private_candidate_only`, requer revisão humana e não
insere conceito, evidência ou leitura. O workflow permanece manual e conserva o
artefato por sete dias durante o benchmark.

## Pautas do briefing

O piloto observa oito famílias, sem abrir a taxonomia pública automaticamente:

- cores;
- materiais e construções têxteis;
- silhuetas e caimento;
- acabamentos e texturas;
- styling e acessórios;
- presença e preço no varejo;
- diferença Brasil × exterior;
- sinais de arrefecimento ou contradição.

Um termo novo nasce como faceta candidata. Promoção a conceito exige definição,
aliases, exemplos positivos e negativos, volume mínimo e revisão humana.
O banco registra o protocolo e os volumes observado/mínimo, preserva quem tomou
a decisão e não concede ao `service_role` as colunas de aprovação ou retirada;
essas transições passam somente pelas RPCs auditáveis da fundação.

## Portões para aparecer no app

Uma leitura só pode ser publicada quando:

1. todas as evidências ligadas estão aprovadas;
2. conceitos e fontes estão ativos e aprovados;
3. cada URL é canônica e ainda pertence ao método autorizado;
4. há pelo menos uma evidência de suporte; fora de `insufficient`, são exigidas
   duas fontes de suporte independentes;
5. período, território, sensor e unidade estão explícitos;
6. não há linguagem preditiva, causalidade não demonstrada ou dado pessoal
   desnecessário;
7. o revisor aceita título, resumo, links, lacunas e estágio como um conjunto.

## Métricas do piloto

- zero fonte `yellow`, `red` ou não registrada chegando à IA;
- zero frase publicada sem evidência aprovada;
- 100% dos números, datas e links reprodutíveis;
- republicações de uma mesma origem contando uma vez;
- custo e tokens registrados por execução;
- taxa de candidatos aceitos, rejeitados e duplicados;
- cobertura por sensor, território e pauta;
- divergências humanas registradas nas primeiras 12 edições;
- zero impacto no pipeline, banco e séries da 1.2.

## Ordem de implementação

1. contrato, registro de fontes e fundação de evidências;
2. parser determinístico da Etiqueta e conjunto de regressão;
3. materialização privada do primeiro pacote factual — implementada; execução
   real depende da aplicação deliberada da RPC A52;
4. Scout privado com allowlist, sem cron e sem publicação;
5. tela/fila de revisão e primeiro briefing cego;
6. benchmark de quatro semanas e ajuste de taxonomia;
7. leitura somente de dados publicados no app;
8. avaliação da cadência e eventual ampliação de fontes.

Nada desta fundação aplica a migração em produção, executa chamada paga ou
altera a 1.2 por si só. Esses passos recebem portões próprios depois que esta
camada passar nos testes offline e na revisão do projeto.
