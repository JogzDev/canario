# Backup lógico e restauração isolada

**Porta de saída da etapa 1 do plano fechado.** Nenhuma migration é aplicada em
produção antes deste procedimento terminar verde.

O plano gratuito do Supabase não oferece backup baixável pelo painel; o caminho
documentado é o dump lógico pelo CLI, restaurado em destino isolado
([backups](https://supabase.com/docs/guides/platform/backups),
[dump e restauração](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)).

## A senha é sua e não passa por mim

Nenhum comando aqui recebe senha em argumento, em URI ou em variável escrita em
arquivo: o CLI pergunta no prompt e o `psql`/`pg_dump` leem de `PGPASSWORD`
exportado pela sua própria sessão. Não cole a senha no chat, no histórico do
shell nem na URI de conexão.

## 0. Ferramentas (esta máquina não tem `brew`, `pg_dump` nem Docker)

O `gh` já vive em `~/.local/bin`; o CLI do Supabase entra do mesmo jeito, por
binário solto, sem gerenciador de pacotes:

```bash
mkdir -p ~/.local/bin && cd /tmp && \
curl -fsSL -o supabase.tar.gz "https://github.com/supabase/cli/releases/latest/download/supabase_darwin_arm64.tar.gz" && \
tar -xzf supabase.tar.gz supabase && mv supabase ~/.local/bin/ && \
chmod +x ~/.local/bin/supabase && ~/.local/bin/supabase --version
```

O destino da restauração **não precisa de instalação**: é o PostgreSQL 17.10 do
pacote `@embedded-postgres`, a mesma versão maior da produção, que já roda neste
projeto no laboratório do radar. Cluster descartável, socket próprio, sem porta
de rede.

## 1. Dump (você roda, com a senha no prompt)

A string de conexão está no painel do Supabase em *Project Settings → Database →
Connection string → URI*. Copie a URI **sem** a senha, deixando `[YOUR-PASSWORD]`
no lugar; o CLI pergunta.

```bash
export PATH="$HOME/.local/bin:$PATH"
cd ~/Canario
mkdir -p ~/backups/datadrobe-$(date +%F) && cd ~/backups/datadrobe-$(date +%F)

supabase db dump --db-url "postgresql://postgres.tbluoqpnjqsflfoclmms:[YOUR-PASSWORD]@<HOST>:5432/postgres" -f papeis.sql --role-only
supabase db dump --db-url "postgresql://postgres.tbluoqpnjqsflfoclmms:[YOUR-PASSWORD]@<HOST>:5432/postgres" -f schema.sql
supabase db dump --db-url "postgresql://postgres.tbluoqpnjqsflfoclmms:[YOUR-PASSWORD]@<HOST>:5432/postgres" -f dados.sql --use-copy --data-only
```

Confira o tamanho antes de seguir: o banco tem **485.649.555 bytes** medidos em
17/09/2026, então os três arquivos somam centenas de MB. Dump de poucos KB é
dump falhado.

```bash
ls -lh papeis.sql schema.sql dados.sql
```

## 2. Restauração isolada e verificação (eu rodo)

```bash
node ferramentas/backup/restaurar_isolado.mjs \
  --dump ~/backups/datadrobe-AAAA-MM-DD \
  --modulos ~/Canario-produto/ferramentas/laboratorio_radar/node_modules
```

O script:

1. sobe um PostgreSQL 17.10 descartável, só com socket local;
2. cria os papéis do Supabase que o dump espera (`anon`, `authenticated`,
   `service_role`, `supabase_admin`) e os esquemas de plataforma;
3. aplica `papeis.sql`, `schema.sql` e `dados.sql`, ignorando **apenas** o que
   não existe fora do Supabase (as extensões `pg_cron` e `supabase_vault`, e o
   que depende delas) — cada linha ignorada é impressa, nunca escondida;
4. compara o resultado com `anexos/contagens_producao_2026-09-17.json`: linha
   por linha das 21 tabelas, número de funções e de políticas de RLS;
5. termina em `RESTAURACAO VERDE` ou lista a primeira divergência.

Exceção conhecida e declarada: `pg_cron` e `supabase_vault` são objetos de
plataforma, não dados. Eles não restauram num PostgreSQL comum e, por isso, o
agendamento do cron e os segredos do vault **não** fazem parte desta prova. O
que a prova cobre é schema, dados, funções e políticas do `public`.

## 3. Só então

Com a restauração verde, a ordem do plano fechado é:

1. purgar `cron.job_run_details` (~15 MB, 64.789 linhas de log);
2. `reindex` do `artigos_url_key` (40 MB medidos contra ~19 MB de um índice
   novo);
3. compactar da menor para a maior (`series_semanais` 70 MB → 21 MB de dado
   vivo; `produtos` 73 → 45; `artigos` 53 → 40; `snapshots` 48 → 35);
4. impedir a reescrita sem mudança em `computar_z`;
5. medir de novo e observar o crescimento por sete dias.

As migrations A57 e A58 entram na mesma janela do aplicativo que as consome,
depois disso — nunca antes.
