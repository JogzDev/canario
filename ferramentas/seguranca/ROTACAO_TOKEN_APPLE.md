# A59 — cifragem do token de revogação Apple

Estado em 21/09/2026: **preparada e testada localmente; não aplicada nem
publicada**. Este procedimento não faz parte da janela atual de observação.

## Por que há duas formas de linha

A50 já guarda o refresh token fora do app, com `FORCE RLS` e leitura somente
pela `service_role`, mas o valor está em claro na tabela. A59 acrescenta
AES-256-GCM na Edge Function, nonce aleatório de 96 bits, tag de 128 bits e o
`user_id` como dado autenticado. O banco recebe apenas texto cifrado, nonce,
versão e nome do algoritmo. A chave fica nos secrets das Edge Functions, não
no banco, no app ou no repositório. A versão numérica permite trocar a chave
sem impedir a leitura de linhas cifradas pela versão anterior.

A migration preserva o formato A50 **temporariamente**: se a função antiga
receber um login entre a atualização do schema e a publicação da função nova,
ele não falha. A função nova só grava o formato cifrado. Linhas existentes
continuam legíveis e o próximo login Apple as converte, mesmo quando a Apple
não emite outro refresh token. Isso não cifra quem nunca voltar a entrar; para
fechar o controle de segurança por completo será necessário um backfill
administrativo, ensaiado e auditado, após a implantação. Até lá, o controle 5
permanece **parcial**.

## Portões antes da produção

1. Encerrar a observação de sete dias e aprovar explicitamente a janela.
2. Conferir backup restaurável, capacidade, estado das migrations e a ausência
   de deploy concorrente. Não usar `supabase db push` indiscriminadamente.
3. Conferir que as duas Edge Functions publicadas ainda operam com A50 e que
   a exclusão de conta responde `apple_revocation` sem imprimir o token.
4. Gerar uma chave aleatória de **32 bytes**, codificada em Base64, em ambiente
   controlado; não colar valor no chat, shell history, arquivo versionado ou
   log. Definir `APPLE_REFRESH_TOKEN_KEY_V1` e
   `APPLE_REFRESH_TOKEN_KEY_VERSION=1` nos secrets das Edge Functions. Validar
   apenas presença e comprimento decodificado; nunca ler a chave em log.
5. Aplicar **somente** A59, verificar colunas, constraint, `FORCE RLS` e
   privilégios. O laboratório `node ferramentas/laboratorio_apple/rodar.mjs`
   já prova esses pontos num PostgreSQL 17.10 isolado.
6. Publicar `registrar-credencial-apple` e `excluir-conta` de modo coordenado;
   não publicar nenhuma antes de A59. Validar login Apple de uma conta de
   teste e exclusão de outra conta de teste, incluindo o retorno de revogação
   ou a orientação manual. Nunca usar token real em fixture/log.
7. Medir apenas contagens de linhas legadas, cifradas e inválidas. Não anunciar
   “tokens cifrados” enquanto existir qualquer linha com `refresh_token`
   em claro. Preparar backfill com contagem antes/depois, idempotência,
   interrupção e retomada; executar em janela separada. O código de backfill
   ainda **não** existe, portanto a implantação completa não está liberada.

Se a chave não estiver disponível, o registro recusa a gravação antes de
consumir o authorization code. A exclusão da conta **não** fica bloqueada:
ela retorna `manual_required` para a revogação Apple, mantém a purga de dados
e orienta o caminho oficial no app. Isso é um fallback de privacidade, não uma
prova de revogação automática.

## Rotação posterior

Criar `APPLE_REFRESH_TOKEN_KEY_V2`, validar 32 bytes e só então apontar
`APPLE_REFRESH_TOKEN_KEY_VERSION=2`. Manter V1 enquanto qualquer linha
`versao_chave=1` existir. Novos logins recifram com V2; backfill versionado
deve cuidar das contas inativas. Remover V1 apenas após contagem zero, prova
de recuperação com V2, backup e janela de rollback definida. Apagar V1 antes
disso faz a revogação automática daquelas linhas cair para `manual_required`.

## Evidência local

- `deno check`, oito testes de criptografia e `deno audit` verdes.
- Laboratório PostgreSQL: legado preservado, conversão, cinco formas inválidas
  rejeitadas, privilégios e `FORCE RLS` preservados.
- Nenhuma migration, função ou secret desta A59 foi enviado a produção.
