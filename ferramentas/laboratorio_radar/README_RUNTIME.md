# PostgreSQL descartável do Radar

Este diretório instala somente dependências locais de teste. O executável cria
um PostgreSQL real por invocação, aplica a A51 e encerra o servidor no `finally`.
Os dados sintéticos são removidos depois de sucesso; em falha o servidor é
encerrado e o caminho do diagnóstico fica impresso no terminal.

## Preparação reproduzível

Requer Node 24 e Python 3.9 ou superior. O Mac do projeto já possui ambos. O
runtime distribuído pelo Codex também oferece Node 24, mas seu caminho pessoal
não é codificado no projeto.

```sh
cd ferramentas/laboratorio_radar
npm ci --no-audit --no-fund
node executar.mjs
```

`npm ci` é a única etapa que precisa baixar dependências. `package-lock.json`
fixa versões e integridades. Os binários são PostgreSQL **17.10**, distribuídos
por `@embedded-postgres/*` **17.10.0-beta.17**; o sufixo pertence ao pacote de
distribuição. `pg` é fixado em **8.23.0**. As plataformas preparadas são macOS
arm64, macOS x64 e Linux x64; o npm instala o pacote opcional correspondente.
Nenhum serviço, usuário do sistema ou instalação global é criado.

O `postinstall` do distribuidor recompõe os symlinks dos binários. Por isso
`--ignore-scripts` impede o bootstrap de funcionar. Não use `npm update`, tags
`latest`, intervalos de versão ou `npm install --force` para executar a suíte.
Atualização de dependência exige mudar o lock e conferir de novo a versão real.

## Interface da suíte

As entradas são caminhos relativos à raiz deste checkout, mesmo quando o comando
é iniciado neste diretório:

```sh
node ferramentas/laboratorio_radar/executar.mjs \
  --fixture ferramentas/laboratorio_radar/gerar_fixture.py \
  --sql ferramentas/laboratorio_radar/schema_admissao.sql \
  --sql ferramentas/laboratorio_radar/teste_admissao.sql \
  --harness ferramentas/laboratorio_radar/teste_concorrencia.mjs
```

O runner aplica os papéis sintéticos `anon`, `authenticated`, `service_role`,
o stub mínimo de `public.termos` e a A51 original. Depois executa o gerador Python
com `--destination-id <UUID>`. O objeto JSON de stdout fica disponível aos SQLs
em `current_setting('lab.fixture')::jsonb`, e o UUID em
`current_setting('lab.destination_id')`. Cada `--sql` é enviado como um bloco;
o arquivo deve definir os limites transacionais necessários ao seu teste.

O harness JavaScript exporta `executar({admin, fixture, connectWriter,
destinationId, database})`. `connectWriter()` abre uma conexão autenticada nova
com `datadrobe_lab_writer`, com senha aleatória desta invocação. Isso permite
testar concorrência real sem herdar privilégios da conexão administrativa.

## Isolamento e alcance da prova

O cluster tem diretório e socket privados (`0700`), autenticação SCRAM e
`listen_addresses=''`: nenhuma interface TCP fica aberta. O nome do banco começa
com `datadrobe_lab_`; antes de aplicar SQL, o runner confirma nome e conexão por
socket. Nenhuma URL externa de banco é aceita. Subprocessos recebem um ambiente
explícito sem credenciais ou variáveis de Supabase, OpenAI e PostgreSQL.

O administrador temporário existe apenas para montar o schema e testar ACLs. A
identidade operacional da admissão usa o papel restrito definido pelo schema.
Em sucesso, o resumo inclui versão real, UUID, testes executados e duração. Em
falha, os artefatos de diagnóstico permanecem no diretório temporário identificado
por `owner.json`. Eles contêm somente material sintético desta suíte.

Esta prova cobre PostgreSQL, constraints, funções, transações e RLS da fundação.
Ela não atesta PostgREST, GoTrue, Edge Functions nem equivalência da versão do
PostgreSQL da produção, que não é consultada por este runner.

Fontes do distribuidor: [repositório do embedded-postgres](https://github.com/leinelissen/embedded-postgres),
[pacote de binários Darwin arm64](https://www.npmjs.com/package/@embedded-postgres/darwin-arm64).
Configuração do servidor: [documentação PostgreSQL](https://www.postgresql.org/docs/17/app-postgres.html).
