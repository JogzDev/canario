# Backup nativo e restauração verificada

As ferramentas e a prova do backup estão integradas a este repositório. A
worktree usada durante a investigação foi apenas um isolamento temporário e
não é necessária para restaurar ou verificar o arquivo existente. Não aplicar
migrations nem fazer manutenção em produção sem seguir o roteiro de capacidade
e avaliar as limitações abaixo.

## Prova real concluída em 18/09/2026

Às 08:59:35 BRT, a restauração do backup real terminou com exit 0 e resultado
`VERIFICADO_NO_ESCOPO_DECLARADO`: 57 tabelas nos schemas `auth`, `public`, `storage`
e `supabase_migrations`, com conteúdo, catálogo, permissões e sequences conferidos.

- Destino: `/Users/jpscoliveira/backups/datadrobe-2026-09-18T02-14-22.054Z-6b15f9`.
- Relatório: `restauracao-1789732775050.json` dentro desse destino.
- Archive: `banco.dump`, 27.774.292 bytes.
- SHA-256: `6906927eb188658d4e1b6880672d3b324afe757df66d798baa035abaaf357686`.

A verificação usou o modo `verify-existing`, comparando o conteúdo restaurado
com um snapshot único posterior ao dump (11:54:32 UTC), como declarado no
relatório. As assinaturas de todas as tabelas coincidiram. Nenhuma alteração
foi feita em produção. O backup não libera espaço nem autoriza manutenção:
capacidade e dependências fora da prova ainda precisam do roteiro revisado.
Não iniciar nova exportação para retomar as tentativas antigas já superadas.

## Ferramentas preparadas

Postgres.app 2.9.6, PostgreSQL **17.11**, instalado para este usuário em:

`~/.local/share/datadrobe-tools/Postgres.app/Contents/Versions/17/bin`

Origem: [release oficial](https://github.com/PostgresApp/PostgresApp/releases/tag/v2.9.6).
O asset `Postgres-2.9.6-17.dmg` teve seu SHA-256 comparado com o digest publicado
pela API do GitHub:

`b38bb00b8c8702a568270aab85995c550f7f93d1503b818efdc5ff9a519b7168`

Assinatura verificada com `codesign --verify --deep --strict`; Gatekeeper aceitou
como `Notarized Developer ID`, equipe `ZF84SJ5A3G`. Não é necessário Homebrew,
Docker, abrir o app gráfico ou iniciar um serviço permanente.

## Nova captura — somente se houver necessidade explícita

O backup real descrito acima já está concluído e restaurado. **Não rode uma
nova captura para continuar a etapa atual.** As instruções desta seção ficam
como procedimento de recuperação para uma necessidade futura, depois de
confirmar que o arquivo existente não atende ao objetivo.

Abra `iniciar_backup.command` no Terminal. Ele usa a conexão sem senha já salva
no projeto original em `supabase/.temp/pooler-url`, limitada ao session pooler
5432 do projeto esperado. Digite a senha atual do banco no prompt sem eco.

O procedimento não solicita senha no chat nem a grava em URI, argumentos do processo, arquivos ou histórico.
É mantida em memória e passada aos filhos PostgreSQL por ambiente. Não é
recuperável da chave publicável do aplicativo. A ferramenta não troca a senha.

O processo:

1. abre uma transação de leitura com snapshot exportado;
2. captura o catálogo e configura somente sua sessão de leitura para até dez minutos por consulta;
3. testa a leitura de `public.artigos` (a tabela em que a exportação real falhou),
   com teto local de seis minutos; só prossegue se o teste concluir;
4. executa `pg_dump --format=custom` antes das verificações de conteúdo e depois
   captura contagens/assinaturas SHA-256 no mesmo snapshot, com progresso por tabela;
5. preserva archive, inventário e manifesto fora do Git, em `~/backups/datadrobe-*`;
6. cria um cluster PostgreSQL descartável, acessível apenas por socket local;
7. restaura os schemas presentes entre `public`, `auth`, `storage` e
   `supabase_migrations`, preservando papéis/owners/ACLs, mas sem permitir login;
8. compara catálogo e dados e encerra o cluster local.

Diretório de backup: `0700`. Arquivos: `0600`. O dump contém dados pessoais e
credenciais de aplicação existentes nas tabelas; não compartilhar nem versionar.
O dump original é preservado se a restauração falhar. Não há filtragem silenciosa
de erros SQL. Qualquer dependência ausente reprova o ensaio para investigação.

O timeout é ajustado com `SET` apenas nas conexões desta ferramenta. Defaults de
produção e papéis `anon`/`authenticated` permanecem intactos. A primeira tentativa
de 17/09 falhou na verificação anterior ao dump por `statement_timeout`; a pasta
daquela tentativa ficou vazia. O ensaio agora inclui um default local de 1 ms
para verificar a sobreposição da sessão antes de tentar produção novamente.

A segunda tentativa foi interrompida pela checagem de configuração da sessão,
ainda antes do dump. O modo somente leitura agora também é configurado por
`SET` explícito, além de `PGOPTIONS`, e o timeout é comparado numericamente em
milissegundos. O ensaio passou sem opções de inicialização, reproduzindo um
pooler que não as propaga. Falhas futuras deixam `falha-*.json` com mensagem
sanitizada no destino; não é necessário expor o Terminal ou credenciais.

A quarta tentativa autenticou e confirmou a sessão de leitura, mas falhou
durante `COPY` de `public.artigos`. O archive parcial não é restaurável e não
constitui backup. A versão antiga perdeu a linha seguinte do erro. Agora os
diagnósticos privados `diagnostico-artigos.json` e `diagnostico-pg_dump.json`
preservam stderr (até 1 MB, com truncamento declarado), horários e motivo de
interrupção local, sem salvar senha, ambiente, argumentos, stdin ou stdout.
Podem conter contexto de linhas do banco: não compartilhar esses logs brutos.

Importante: os dez minutos de `statement_timeout` se aplicam às consultas psql
desta ferramenta. O próprio `pg_dump` redefine os timeouts SQL para zero; para
ele o limite é **local**, seis minutos no teste focal e quinze no dump completo.
Isso não altera defaults da produção. Não atribuir a falha anterior a timeout
ou ao pooler sem a mensagem do servidor ou os logs correspondentes.

Para repetir apenas a restauração:

```sh
node ferramentas/backup/backup_nativo.mjs restore --dest /caminho/absoluto/do/backup
```

Se o dump terminou com exit0, mas a verificação de conteúdo perdeu a conexão,
não é necessário exportar tudo novamente:

```sh
node ferramentas/backup/backup_nativo.mjs verify-existing --dest /caminho/absoluto/do/backup
```

Esse modo valida a leitura integral do archive, confirma que a estrutura e as
sequences não mudaram e calcula SHA-256 de cada linha no próprio servidor. Só
transfere contagem, quatro somas exatas e quatro XORs dos segmentos64bits dos
hashes. A representação usada é `record_out` (`r::text`), que distingue SQL NULL
de JSON null e preserva limites inferiores de arrays, diferente de row_to_json.
Isso evita reenviar centenas de MB pela conexão instável. Não usa sort
nem CTE materializado; a mesma assinatura é calculada no restore local. Todas
as leituras compartilham um único snapshot novo, limitado a 60 min. O manifesto
declara explicitamente que a comparação usou um snapshot **posterior ao dump**;
só há aprovação se todas as assinaturas forem iguais. Divergência não é
ignorada ou atribuída automaticamente a "mudanças normais". Logs privados e
hashes parciais não constituem aprovação. O método anterior em blocos `ctid`
continua testado, mas não é o caminho padrão dessa recuperação.

`restaurar_isolado.mjs` é um alias para o modo `restore`; o parser antigo de
SQL/COPY foi retirado. O formato esperado agora é `banco.dump` +
`manifesto.json`, não três arquivos SQL avulsos.

## O que a prova significa

Um resultado `VERIFICADO_NO_ESCOPO_DECLARADO` prova conteúdo e definições dos
schemas declarados restaurados do arquivo real. Compara tabelas, colunas,
constraints, índices, views, funções, triggers, políticas RLS e ACLs catalogadas.
O conteúdo de cada tabela usa contagem e soma/XOR de SHA-256 por linha, sem
ordenação pesada em produção. O hash do archive também é verificado. O estado
das sequences/identity é comparado; se mudar durante a captura (não é MVCC), o
processo preserva o dump e reprova a prova para repetição sem gravações.

A comparação usa a ordem lógica das colunas ativas, não as lacunas físicas de
`attnum` deixadas por `DROP COLUMN`/`DROP ATTRIBUTE`. O dump lógico não preserva
essas lacunas. Nomes, ordem efetiva, tipos, defaults e permissões continuam
comparados; teste negativo confirma que trocar a ordem lógica reprova o ensaio.

Continuam fora da prova operacional:

- bytes das imagens e demais objetos do Storage (o dump contém metadados);
- funcionamento de Auth, PostgREST, provedores Apple/e-mail e Edge Functions;
- execução de cron e leitura de segredos Vault/extensões indisponíveis localmente;
- configurações de plataforma e senhas de login dos papéis;
- recuperação completa do projeto Supabase e cópia em outra máquina.

As extensões indisponíveis aparecem no relatório. Funções que dependam delas
podem ser preservadas como definição sem terem sua execução comprovada. Nunca
interpretar o ensaio como autorização automática para produção.

## Ensaio sem credencial de produção

```sh
node ferramentas/backup/testar_backup.mjs
```

Cria origem e destino locais reais; exercita dump/restauração, Unicode e COPY,
chaves estrangeiras, índices, RLS, funções, triggers e ACLs. Também prova que
conteúdo divergente e hash adulterado são rejeitados. Não lê produção.

Em 17/09/2026, o ensaio passou em PostgreSQL 17.11: seis tabelas, 12 mil linhas
de peças fictícias, catálogo/dados/sequences iguais; os dois casos negativos
também foram rejeitados. Esse ensaio usa fixtures; a prova real está registrada
separadamente no início deste documento.

`node ferramentas/backup/testar_diagnostico.mjs` usa processos e credenciais
fictícios para provar preservação de stderr multilinha, redação de senha,
permissão0600 e identificação do timeout local. O teste focal de `artigos`
também faz parte do ensaio integral com PostgreSQL real local.

Referências: [pg_dump 17](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore 17](https://www.postgresql.org/docs/17/app-pgrestore.html),
[limites dos backups Supabase](https://supabase.com/docs/guides/platform/backups).
