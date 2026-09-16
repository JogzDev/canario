# Transição de infraestrutura — retirada dos Macs como servidores

**Data de decisão:** 16/09/2026.

**Prazo físico:** devolver o Mac i7 do laboratório em **17/09/2026, até 18h
(America/Sao_Paulo)**.

**Escopo:** branch `codex/produto-pos-challenge`; `main`, produção e o binário
1.2 permanecem intocados até uma mudança passar pelos portões deste documento.

## Resultado que esta transição precisa produzir

Nenhum serviço contínuo do DataDrobe deve depender de computador pessoal,
emprestado ou ligado numa sala. O estado-alvo separa três responsabilidades:

| Responsabilidade | Destino | Por quê |
|---|---|---|
| Build, testes e archive Apple | Xcode Cloud | Ambiente Apple gerenciado; 25 horas/mês incluídas na membership atual segundo a Apple; não mantém o Mac pessoal acordado |
| Testes Python e sondas curtas | GitHub-hosted Linux | Reprodutível e efêmero; sem segredo nas sondas; adequado para CI curto, não para toda a coleta diária |
| Coleta, saúde e motor | Job Linux gerenciado e agendado | Execução isolada, timeout, logs, segredos do provedor e nenhuma sessão pessoal; Cloud Run Jobs é o candidato inicial, condicionado a conta/billing e prova das fontes |

GitHub Actions Linux não é o executor diário escolhido por omissão. As duas
últimas execuções verdes medidas consumiram cerca de 66–67 minutos cada; uma
execução diária chega a aproximadamente 2.100 minutos em 30 dias, antes de CI,
retries e manutenção. Isso supera os 2.000 minutos/mês documentados para
repositório privado no GitHub Free. Cloud Run Jobs pode caber na franquia de
CPU/memória, mas exige billing habilitado e todo o tempo do job — inclusive
espera de rede — é contabilizado. Portanto “tende a caber no gratuito” não é
promessa de custo zero.

Referências oficiais: [Xcode Cloud](https://developer.apple.com/xcode-cloud/get-started/),
[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[Cloud Run pricing](https://cloud.google.com/run/pricing) e
[Cloud Scheduler pricing](https://cloud.google.com/scheduler/pricing).

## Registro do corte — 16/09/2026

- inventário real: run `35138670263`, commit `d9a1800`, 5.289 JPG,
  1.988.815.984 bytes e 9 diretórios;
- preservação real: run `35138670359`, draft release privado `390176961`,
  TAR asset `568607223` (1.993.523.200 bytes), SHA-256
  `c8d6e57e8fb086b2fa5124f6295f3b7fbdcdfb53c61be7067b98383d8aab8ab8`;
- restauração fora do i7 em
  `/Users/jpscoliveira/DataDrobe-Backups/i7-luna-2026-09-16`: manifesto
  `datadrobe_luna_cache_v1`, 5.289 arquivos, 1.988.815.984 bytes, 9 diretórios e
  `verified: true`;
- sonda Linux real: run `35138670304`; VTEX, Shopify, FFW e Google Trends
  válidos; Business of Fashion devolveu 403 em `robots.txt`; veredito
  `inconclusivo_ou_bloqueado` e `nao_autoriza_migracao: true`;
- workflows `325762843` (pipeline diário), `341813672` (catálogo candidato) e
  `337501439` (sonda Luna) desabilitados manualmente antes do corte;
- runner 21 do i7 removido; runner 22 do Mac pessoal removido depois do verde
  da Apple; a API passou a listar zero runners, zero job em fila e a variável
  `RUNNER_COLETA` foi removida;
- LaunchAgent `actions.runner.JogzDev-canario.mac-do-jp-xcode` desinstalado; o
  diretório do runner pessoal foi movido para a Lixeira, operação recuperável;
- Xcode Cloud: produto `4D171683-CA40-4771-BABB-23BD98D5EF61`, workflow
  `FA4DAB2E-0C26-4347-9BA7-8AD47D7C8902`. O build 1 encontrou no Xcode 27 uma
  dupla conclusão da continuação do OCR; o commit `335f576` corrigiu o defeito
  com portão thread-safe e o build 2
  (`864b4d08-d0ae-400e-b8c6-7cb22c1c98b3`) passou;
- `testes.yml` deixou de usar ambos os Macs: Python 3.11 roda em
  `ubuntu-latest`; Swift, build e UI pertencem ao Xcode Cloud.

O corte não rotacionou cegamente `SUPABASE_SECRET_KEY` ou `OPENAI_API_KEY`.
Remover os runners revogou as credenciais persistentes e impede novas entregas
de secrets, mas não prova que uma chave de job jamais foi copiada. A rotação
continua sendo defesa em profundidade; só deve ocorrer com inventário de todos
os consumidores, dupla chave, atualização verificada e revogação da antiga,
para não derrubar produção ao devolver o host.

## Fatos verificados em 16/09

- os runners 21 e 22 e a variável `RUNNER_COLETA` existiam no início da
  transição; foram removidos na ordem registrada acima;
- `pipeline-diario.yml`, `coleta-catalogo-candidato.yml` e
  `sonda-edge-luna.yml` dependiam direta ou indiretamente do i7; suas agendas
  permanecem desabilitadas enquanto não existir OP-12;
- o cache `$HOME/canario-imagens-treino`, fora do Git, alimentava a revisão
  cega e partes da avaliação da Luna; agora possui snapshot privado e
  restauração verificada fora do laboratório;
- o banco mediu 485.174.419 / 500.000.000 bytes (97,03%) em 16/09 e o portão
  bloqueia novas escritas. Não há motivo seguro para transferir uma coleta
  escrevente para outro host antes de recuperar capacidade;
- o Mac pessoal não apresentava cron do DataDrobe; o único serviço encontrado
  era o runner do GitHub, agora revogado e desinstalado;
- os sites não tratam todas as nuvens da mesma forma: Shopify, FFW, Business
  of Fashion e Google Trends já apresentaram recusas dependentes da origem.
  A sonda hospedada confirmou quatro classes e bloqueou BoF de modo seguro;
  nenhuma troca de executor é aceita sem repetir a prova no destino.

## Portões obrigatórios

### G0 — preservar antes de retirar

O workflow `inventariar-i7.yml` mede somente o cache conhecido. O artefato
contém totais, bytes, extensões e intervalo de datas; não contém nomes de
arquivo, caminhos internos, conteúdo, configuração ou segredo, e não segue
links simbólicos. A travessia usa descritores, recusa troca da raiz, não cruza
mounts e falha fechado em link, entrada especial, erro, limite de tempo ou de
quantidade. O JSON é escrito atomicamente num nome único da execução e o
artefato é tentado mesmo quando o diagnóstico bloqueia. O inventário decide a
forma de preservação — ele próprio **não é backup**:

1. cache ausente ou vazio: registrar o resultado; não inventar uma cópia;
2. cache pequeno o bastante para a cota disponível: criar arquivo privado
   temporário, manifesto SHA-256 e testar extração fora do i7;
3. cache maior que a cota: usar destino privado escolhido pelo proprietário,
   com criptografia e hash antes da devolução;
4. em todos os casos: nada é apagado do i7 por automação do projeto. A entrega
   física e a política do laboratório determinam a limpeza local.

O grupo de concorrência impede os workflows conhecidos que usam
`canario-dados`, mas não congela um processo iniciado à mão no host. Antes de
copiar, os produtores precisam estar pausados e a cópia deve ser verificada
como um snapshot separado.

**Saída:** inventário baixado, destino definido, cópia verificada e hash do
arquivo preservado. Um upload concluído sem teste de extração não fecha G0.

### G1 — provar a origem gerenciada

`sondar-origem-gerenciada.yml` executa manualmente em `ubuntu-latest`, sem
segredos, Supabase, cron, commit ou payload persistido. Ela consulta `robots.txt`
e valida em memória uma resposta limitada por classe de risco:

- Cantão / VTEX;
- Amaro / Shopify;
- FFW / WP JSON;
- Business of Fashion / RSS;
- Google Trends / sessão efêmera, `explore`, widget `TIMESERIES` e
  `multiline` com série não vazia.

A cadência é global de no máximo uma requisição por segundo; o maior entre ela,
`Crawl-delay` e `Request-rate` prevalece, e um intervalo acima do teto da sonda
faz a fonte ser pulada. `robots.txt` truncado ou inválido falha fechado. JSON,
RSS/Atom e as três etapas do Trends precisam ter a estrutura mínima esperada:
HTML de WAF, corpo vazio, parcial ou apenas um status 2xx não passa. A sonda não
segue redirecionamento e não persiste corpo, cabeçalho, cookie, request ou token.
Cookies do Trends existem só na memória da execução e são descartados ao fim.

**Saída:** relatório sanitizado por fonte e veredito explícito. Somente todas as
cinco estruturas válidas produzem `apto_para_proxima_prova`; qualquer falha,
skip ou conjunto vazio produz `inconclusivo_ou_bloqueado`. Mesmo o primeiro
veredito traz `nao_autoriza_migracao: true`: esta execução mede egresso do
GitHub, não do futuro Cloud Run, onde a prova precisa ser repetida. `403/429`,
timeout, redirecionamento ou robots inconclusivo não autoriza proxy, browser
headless nem disfarce de User-Agent.

### G2 — executor de dados reproduzível

Somente depois de G1:

1. imagem Linux fixada por digest e Python fixado por versão;
2. um coordenador explícito preserva a ordem varejo → editorial → busca →
   saúde → motor e a publicação atômica existente;
3. capacidade é medida antes de qualquer escrita e falha fechada;
4. uma tarefa, zero retry automático inicialmente, timeout e limite de memória;
5. segredos vêm do Secret Manager e não de arquivo, argumento ou imagem;
6. dry-run sem Supabase, depois banco isolado, depois produção com rollback;
7. logs não contêm respostas, tokens, URLs assinadas ou dados de usuário;
8. Scheduler tem identidade própria e só permissão para executar o job;
9. orçamento e alertas são configurados, lembrando que orçamento não é teto
   automático de gasto.

Cloud Run Jobs é o primeiro candidato porque remove administração de VM e a
estimativa de uma hora/dia cabe na franquia documentada. Criar conta, habilitar
billing ou aceitar custo continua sendo decisão explícita do proprietário.
Oracle Always Free é fallback de capacidade, não garantia: região pode não ter
instância e recurso ocioso pode ser retomado.

### G3 — CI Apple gerenciado

O Mac pessoal só deixa de ser runner depois de:

1. workflow Xcode Cloud ligado ao projeto e à equipe Apple correta;
2. scheme compartilhado encontrado e build com `Config.xcconfig` de CI sem
   chave real;
3. `swift test`, build de simulador e os sete fluxos UI offline executados;
4. destino/runtime disponível no Xcode Cloud, sem fixar o simulador local
   `DataDrobe-CI` ou o OS 26.2 como pressuposto;
5. um commit da branch produzir resultado consultável sem este Mac ligado;
6. retenção de logs/artefatos e consumo das 25 horas acompanhados.

A preparação versionada já precisa conter um `Canario.xcscheme` compartilhado,
o `ci_post_clone.sh` ao lado do projeto e o bloqueio opt-in dos dois testes UI
que leem dados reais. O clone limpo cria `Config.xcconfig` apenas a partir do
modelo público e roda os testes Swift. Como esse modelo contém placeholders, o
primeiro workflow é **somente Test na branch**: sem Archive e sem TestFlight.
Distribuição gerenciada só entra depois de provisionar as chaves públicas reais
de forma controlada e provar o build. A criação inicial do workflow ainda exige
selecionar projeto, equipe e permissão do repositório na conta Apple.

Avaliação visual da Luna com Vision é uma carga separada do CI. Ela deve virar
job Apple manual, versionado e com dataset preservado; não deve manter o Mac
pessoal como servidor só porque usa frameworks Apple.

`centroides.yml` também fica congelado como carga ML separada: além do cache
externo, sua entrada manual aceita 180 minutos enquanto o job encerra em 90.
Migrá-lo junto com CI mascararia esse contrato quebrado; ele precisa de executor,
dataset e timeout próprios. `avaliar-luna.yml` segue a mesma separação.

### G4 — corte e revogação

O corte não depende de fingir que o substituto ficou pronto em um dia. Se G2
não estiver verde, a coleta fica **pausada explicitamente** — estado honesto e
reversível, especialmente enquanto o banco bloqueia escrita.

Ordem obrigatória:

1. concluir G0 e registrar o último SHA executado no i7;
2. cancelar/aguardar qualquer job ocupado;
3. desabilitar temporariamente as três agendas que dependem do i7;
4. remover o runner ID 21 no GitHub, invalidando sua credencial;
5. confirmar pela API que o runner não aparece mais e que não há job pendente;
6. rotacionar `SUPABASE_SECRET_KEY` e `OPENAI_API_KEY`; rotacionar também os
   segredos de `market-intelligence-lab` que tenham sido entregues ao i7;
7. atualizar os destinos gerenciados e provar acesso mínimo; não reativar
   coleta enquanto o portão de capacidade estiver crítico;
8. registrar data, operador, IDs de execução e rollback no `ESTADO.md`;
9. só depois de G3, remover o runner ID 22, desinstalar seu LaunchAgent e
   retirar o diretório local de runner por uma operação recuperável.

URLs e chaves públicas não são tratadas como segredo, mas a chave secreta de
serviço do Supabase e as chaves OpenAI são. `GITHUB_TOKEN` de job é efêmero; a
credencial persistente relevante é a do próprio runner, invalidada pela remoção.

## Cronograma de 17/09

| Limite | Entrega verificável | Se não fechar |
|---|---|---|
| 11h | G0: inventário e estratégia de cópia | Não remover o runner; escalar a preservação do cache |
| 14h | Cópia + extração/hash verificadas; G1 registrado | Fontes inconclusivas ficam fora do candidato gerenciado |
| 16h | Três agendas pausadas e nenhuma run ocupada | Cancelar apenas jobs identificados; não desligar às cegas |
| 17h | Runner 21 removido e segredos sensíveis rotacionados | Não devolver uma máquina ainda autorizada no repositório |
| 17h30 | Verificação final de runners, agendas e artefatos | Registrar bloqueio e manter produção explicitamente pausada |
| 18h | i7 pode ser devolvido | G2 pode continuar depois, sem depender do equipamento |

## Rollback e definição de concluído

Desabilitar workflows é reversível; remover o runner não destrói código nem
dados, mas exige registrar outro executor para voltar a rodar. Rotação de chave
é revertida atualizando consumidores para a nova chave — a antiga não deve ser
reativada depois que o computador sai do controle do proprietário.

O **corte dos hosts**, que era o pacote com prazo de 17/09, termina quando:

- GitHub não lista runner do laboratório nem runner pessoal;
- nenhuma agenda dependente desses rótulos permanece ativa e nenhuma variável
  envia trabalho a eles;
- Apple CI executa em serviço gerenciado, a partir de checkout limpo e sem
  arquivo secreto local;
- cache da Luna tem origem, manifesto, política de retenção e restauração
  testada;
- uma máquina desligada não altera a saúde do produto.

Esses critérios foram atendidos em 16/09, ressalvada a decisão futura de
retenção do snapshot. A **substituição integral da operação de dados** continua
aberta e não deve ser confundida com o corte físico: OP-04/05/06/12 ainda
precisam entregar coleta gerenciada, alerta externo, rotação segura de secrets,
custos e quotas. Até lá, coleta pausada é o estado correto; reativar cron num
runner improvisado seria regressão, não rollback.
