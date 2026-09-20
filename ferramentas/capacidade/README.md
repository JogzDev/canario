# Etapa 1 — capacidade do banco e prevenção de crescimento

**Roteiro preparado, NÃO executado.** Nenhuma linha deste roteiro rodou em
produção. As medições abaixo foram feitas em leitura, em 18/09/2026 entre
12:37 e 13:05 UTC, e estão em
[`anexos/capacidade_2026-09-18.json`](../../anexos/capacidade_2026-09-18.json).

## 1. Onde estamos

A cota do plano Free é a *Database size* da plataforma, que a documentação do
Supabase define como a soma de `pg_database_size` sobre **todos** os bancos do
cluster. O portão de capacidade media só o banco `postgres`.

| | bytes | % de 500 MB |
|---|---:|---:|
| `postgres` (o que o portão via) | 485.952.659 | 97,19% |
| `template0` | 7.520.783 | |
| `template1` | 7.752.851 | |
| **total (o que a cota vê)** | **501.226.293** | **100,25%** |

`default_transaction_read_only` estava `off`: o projeto ainda escreve, mas a
conta da plataforma já passou do limite. O momento em que ela liga o
somente-leitura não é observável por SQL, e o painel atualiza a métrica uma
vez por dia. O backup não libera espaço.

**O que ainda cresce com a coleta parada:** o log do pg_cron.
`canario-motor-dispatcher` roda a cada minuto; `cron.job_run_details` tem
65.834 linhas, 16,7 MB, e ganha ~360 KB por dia. O banco principal cresceu
180.224 bytes entre 02:33 e 12:37 UTC.

**O que é folga, e não dado** (dado vivo medido; reescrita estimada no
fillfactor de cada tabela):

| relação | hoje | depois de reescrita (estimado) | por quê |
|---|---:|---:|---|
| `series_semanais` | 73,8 MB heap | 33,0 MB | 2,7 milhões de updates em 29.047 linhas: o motor reescreve a série inteira a cada publicação |
| `artigos_url_key` | 42,0 MB | 22,1 MB | 828.725 updates em `artigos`, 4,7% HOT |
| `artigos` | 55,9 MB heap | 44,0 MB | idem |
| `cron.job_run_details` | 16,7 MB | ~2,5 MB com 7 dias de retenção | nada apaga o log |
| `estado_produtos_oferta_recente` | 9,1 MB | 1,9 MB | toda coleta move a entrada |
| `indices_semanais` | 17,2 MB heap | 10,6 MB | mesmo padrão de reescrita da série |

O método de estimativa de índice foi calibrado em `produto_termos_pkey`, que
não tem inchaço: 11,86 MB estimados contra 11,91 MB medidos. `produtos`
(ganho de ~6,9 MB contra a tabela mais lida do app) e os índices de
`snapshots` (que reincham com a poda diária) ficam fora de propósito.

## 2. Três tipos de ação, que não se confundem

**Remove linhas — não devolve espaço.** `delete` marca linhas como mortas; o
arquivo continua do mesmo tamanho. Só o passo 10 é deste tipo, e ele existe
para que o passo 11 tenha o que devolver.

**Devolve espaço físico.** `vacuum full` e `reindex` escrevem uma cópia nova
e apagam a velha no commit. Precisam de espaço temporário do tamanho da
cópia, e seguram lock. Passos 11 a 60.

**Preventiva.** Muda o que o banco faz a partir de agora; não devolve nada
por si. As migrations P21 a P25.

## 3. A ordem, e três dependências que ela precisa respeitar

A ordem operacional fechada é:

1. integrar a branch, enviar pelo fluxo autorizado e exigir todos os jobs do
   GitHub Actions verdes;
2. desativar os dois workflows agendados que escrevem
   (`pipeline-diario.yml` e `coleta-catalogo-candidato.yml`) e confirmar que
   ficaram desativados — hoje a coleta está barrada pelo portão, não pausada;
3. medir de novo em leitura (`00_inventario.sql`);
4. executar 10 e 11; imediatamente rodar o preflight 13, aplicar P23 pelo
   executor de migrations e conferir a pós-condição 14, para o log não voltar
   a crescer;
5. executar 20, 21, 30 e 50; rodar o passo 55 e seguir exatamente um ramo:
   nenhum, somente 40, ou somente 60;
6. confirmar escrita liberada e pelo menos 20% de folga (passo 70);
7. passar pelo portão 80 e aplicar P21, P22, P24 e P25, nessa ordem. Rodar 82;
8. rodar 85, aplicar A57 e depois A58 e rodar 87, no mesmo rollout de backend
   e antes de retomar a
   coleta. A58 depende do marcador criado pela A57; não são opcionais entre
   si. A P24 é apenas a guarda temporária até a A58 materializar o denominador
   e reativar a poda com segurança;
9. executar a sonda pública das RPCs depois do refresh do schema do PostgREST;
10. rotacionar a senha administrativa pelo procedimento da seção 8;
11. reativar os dois workflows, disparar/acompanhar a primeira coleta saudável
    e observar por sete dias (passo 90, uma vez por dia);
12. só então publicar o app consumidor.

**P22 não precisa vir antes da compactação — mas precisa vir antes da
retomada.** Com a coleta parada o motor não roda, e nada reescreve
`series_semanais`. Na primeira publicação depois da retomada, sem a P22, o
motor reescreve até ~46,7 mil linhas e começa a comer os ~43 MB que o passo
50 devolve. Aplicá-la com o banco no limite é seguro: substitui três funções,
alguns KB de catálogo, sem tocar em linha nenhuma. Não mudei a ordem; só
registro que ela não é uma restrição.

**P25 é a mesma proteção para `indices_semanais`.** O passo 30 recupera cerca
de 7,3 MB, mas a função antiga acumulou 610.443 updates em apenas 9.897
linhas. Sem a P25, essa folga começaria a ser consumida outra vez na primeira
publicação. O laboratório prova reexecução idêntica com zero updates, mudança
real restrita às linhas afetadas, remoção da leitura sem base e equivalência
do recálculo completo.

**P23 entra imediatamente depois do passo 11.** Depois de apagar e compactar
o log não faz sentido deixá-lo voltar a crescer ~360 KB por dia enquanto o
restante da recuperação acontece. Os passos 13 e 14 mostram o antes e o
depois; a própria migration repete as travas e faz agendamento, reativação,
pós-condição e ledger na mesma transação. Ela recusa execução fora do papel
`postgres`, que enxerga o catálogo inteiro e impede um job homônimo de outro
papel. Se o banco ainda recusar escrita nesse ponto, o roteiro para; não se
contorna o bloqueio.

**P24 é uma guarda temporária até a A58.** A primeira publicação do motor
chama `podar_snapshots(21)`, cujo corte é de calendário: medido em
18/09, ela apagaria **202.050 das 254.736 linhas de snapshot — 16 dos 22
dias** (12/08 a 27/08). É a única fonte do denominador que a A58 reconstrói.
A P24 faz a poda devolver 0 enquanto `sortimento_diario` não existir. O
A57 e A58 entram nessa ordem e no mesmo rollout antes da retomada. A58
materializa o denominador e torna a guarda inerte; assim o custo potencial de
~2,7 MB por dia com a coleta rodando não vira parte do plano. O app consumidor
espera os sete dias de observação.

## 4. Os passos

Cada arquivo tem no cabeçalho: tipo, alvo exato, ganho estimado e de onde ele
vem, espaço temporário, lock, duração esperada e critério de abortamento.

| passo | tipo | alvo | ganho estimado | temporário | lock | duração |
|---|---|---|---:|---:|---|---|
| `00` | leitura | inventário | — | — | nenhum | segundos |
| `10` | remove linhas | `cron.job_run_details` | 0 | 0 | row exclusive | segundos |
| `11` | devolve espaço | `cron.job_run_details` | ~14,1 MB | ~3 MB | access exclusive | 1–3 s |
| `12` | alternativa desarmada | `cron.job_run_details` | ~16,6 MB | 0 | access exclusive | instante |
| `13/14` | leitura | preflight/pós-condição P23 | — | — | nenhum | segundos |
| `20` | devolve espaço | `estado_produtos_oferta_recente` | ~7,2 MB | ~2 MB | índice + share | 1–3 s |
| `21` | devolve espaço (opcional) | `estado_dos_produtos_pkey` | ~2,0 MB | ~3 MB | índice + share | 1–3 s |
| `30` | devolve espaço | `indices_semanais` | ~7,3 MB | ~11 MB | access exclusive | 2–8 s |
| `40` | ramo condicional | `artigos_url_key` | ~19,9 MB | ~22 MB | índice + share | 3–15 s |
| `50` | devolve espaço | `series_semanais` | ~43,4 MB | ~36 MB | access exclusive | 5–20 s |
| `55` | leitura | decide nenhum/40/60 | — | — | nenhum | segundos |
| `60` | devolve espaço (condicional) | `artigos` + índices | ~35,7 MB | ~70 MB | access exclusive | 10–40 s |
| `70` | leitura | folga ≥ 20% e escrita livre | — | — | nenhum | segundos |
| `80` | leitura | funções = as de 18/09 | — | — | nenhum | segundos |
| `82` | leitura | P21–P25 + job + ledger | — | — | nenhum | segundos |
| `85/87` | leitura | antes/depois de A57/A58 | — | — | nenhum | segundos |
| `90` | leitura | observação diária | — | — | nenhum | segundos |

**Acumulado estimado do caminho normal** a partir de 501,2 MB: 487,1 depois do
11 · 479,9 do 20 · 477,9 do 21 · 470,6 do 30 · **427,2 do 50 (85,4%)**. Meça
nesse ponto. O passo 55 mede de verdade: se já houver ≤400 MB, nenhum ramo;
se o ganho estimado do índice bastar, somente 40; caso contrário, somente 60.
Pelas medidas de 18/09, a decisão esperada é 60: ele reescreve `artigos` e
reconstrói, uma única vez, `artigos_pkey` e `artigos_url_key`, levando a cota
estimada a **391,5 MB (78,3%)**.

**40 e 60 são ramos mutuamente exclusivos por código, não só por instrução.**
Cada arquivo recalcula a decisão e recusa o ramo incorreto; ambos também
recusam se o índice já carrega o rastro de uma reconstrução. O 60 conserva
ainda um segundo freio: ganho físico total estimado abaixo de 15% exige nova
decisão. Se o resultado real não alcançar 400 MB, pare e revise; não rode o
outro ramo em seguida.

**Duração** é estimativa: a leitura sequencial medida foi de 73,8 MB em 0,42 s
(`series_semanais`) e 55,9 MB em 1,8 s (`artigos`); reescrever custa algumas
vezes a leitura. O teto real é o `statement_timeout` de 180 s de cada passo —
se estourar, a transação desfaz tudo e a tabela fica como estava.

**Temporário e disco.** A cópia nova existe junto com a velha até o commit, e
o WAL dela vai para `pg_wal`, fora da cota mas dentro do disco de 1 GB. Cada
passo confere, antes da ação, que cota + WAL + 2 × temporário cabe em
900 MB (hoje: 501 + 134 + 140 no pior passo = 775).

## 5. Critérios de interrupção

Qualquer um destes para o roteiro. Nenhum é resolvido apagando dado.

- uma pré-condição falha — o executor sai com código 1 **antes** da ação;
- a ação estoura `lock_timeout` (5 s) ou `statement_timeout` (180 s);
- o alvo não encolhe (`VACUUM` sem permissão pula a tabela com um aviso e
  sai com sucesso — o executor transforma isso em erro);
- um passo devolve menos da metade do ganho estimado: parar e revisar a
  estimativa antes do próximo;
- o WAL passa de 400 MB: esperar um checkpoint (5 min) e medir de novo;
- aparece erro no app ou na coleta durante a janela;
- `80` acusa função diferente da medida em 18/09: a migration substituiria
  algo que ninguém revisou;
- durante a observação, `90` acusa cota acima de 85% (425 MB).

## 6. Como executar, quando autorizado

A ação só é enviada com `--executar`. Sem ele, o passo roda as
pré-condições em transação somente leitura e imprime `ENSAIO`.

```bash
LAB=~/.canario/laboratorio-capacidade
mkdir -p "$LAB" && cp ferramentas/laboratorio_capacidade/package*.json "$LAB/"
(cd "$LAB" && npm install --no-audit --no-fund)
```

Depois de integrar/enviar a branch e ver todos os jobs verdes, congele as duas
fontes agendadas de escrita. Isso é obrigatório: hoje elas estão **barradas**
pela capacidade, não desativadas, e voltariam sozinhas assim que a folga
aparecesse.

```bash
gh workflow disable pipeline-diario.yml
gh workflow disable coleta-catalogo-candidato.yml
gh workflow list --all
```

Prepare apenas endereço e usuário; a senha continua sendo pedida sem eco a
cada comando e não entra em variável nem histórico.

```bash
CAP_HOST='<HOST DO POOLER DE SESSAO>'
CAP_USER='postgres.tbluoqpnjqsflfoclmms'
CAP=(node ferramentas/capacidade/passo.mjs --host "$CAP_HOST" --porta 5432 --usuario "$CAP_USER")
```

Sequência exata da janela:

```bash
"${CAP[@]}" ferramentas/capacidade/00_inventario.sql

"${CAP[@]}" ferramentas/capacidade/10_log_do_cron_apagar_antigos.sql --executar
"${CAP[@]}" ferramentas/capacidade/11_log_do_cron_compactar.sql --executar
"${CAP[@]}" ferramentas/capacidade/13_confere_p23_antes.sql
"${CAP[@]}" --migracao supabase/migrations/20260917202000_p23_retencao_do_log_do_cron.sql --executar
"${CAP[@]}" ferramentas/capacidade/14_confere_p23_depois.sql

"${CAP[@]}" ferramentas/capacidade/20_reindex_estado_produtos_oferta_recente.sql --executar
"${CAP[@]}" ferramentas/capacidade/21_reindex_estado_dos_produtos_pkey.sql --executar
"${CAP[@]}" ferramentas/capacidade/30_vacuum_full_indices_semanais.sql --executar
"${CAP[@]}" ferramentas/capacidade/50_vacuum_full_series_semanais.sql --executar
"${CAP[@]}" ferramentas/capacidade/55_decide_40_ou_60.sql
```

Leia a linha `DECISAO 40/60` e execute **uma só** das alternativas indicadas:

```bash
# somente se a decisão disser PASSO 40
"${CAP[@]}" ferramentas/capacidade/40_reindex_artigos_url_key.sql --executar

# OU somente se a decisão disser PASSO 60
"${CAP[@]}" ferramentas/capacidade/60_vacuum_full_artigos_CONDICIONAL.sql --executar
```

Depois do ramo (ou de `NENHUM`):

```bash
"${CAP[@]}" ferramentas/capacidade/70_confere_folga.sql
"${CAP[@]}" ferramentas/capacidade/80_confere_antes_das_migrations.sql

"${CAP[@]}" --migracao supabase/migrations/20260917200000_p21_uso_do_banco_mede_a_cota.sql --executar
"${CAP[@]}" --migracao supabase/migrations/20260917201000_p22_series_sem_reescrita_identica.sql --executar
"${CAP[@]}" --migracao supabase/migrations/20260917203000_p24_poda_espera_o_denominador.sql --executar
"${CAP[@]}" --migracao supabase/migrations/20260917204000_p25_indices_sem_reescrita_identica.sql --executar
"${CAP[@]}" ferramentas/capacidade/82_confere_prevencao.sql

"${CAP[@]}" ferramentas/capacidade/85_confere_antes_da_a57_a58.sql
"${CAP[@]}" --migracao supabase/migrations/20260917210000_a57_frescor_ancorado_no_dado.sql --executar
"${CAP[@]}" --migracao supabase/migrations/20260917211000_a58_significado_da_capa_e_busca_editorial.sql --executar
"${CAP[@]}" ferramentas/capacidade/87_confere_depois_da_a57_a58.sql
```

O host está no painel em *Connect → Session pooler*. A porta 6543 (pooler de
transação) é recusada pelo executor: ali `set lock_timeout` não sobrevive até
o comando seguinte. A senha é pedida no terminal, sem eco, e não entra em
argumento, variável, arquivo nem saída.

Por que não o editor SQL: `VACUUM` não roda dentro de bloco de transação, e o
editor manda o script como um bloco — `set lock_timeout = '5s'; vacuum full
t;` falha inteiro (medido no PostgreSQL 17.10 do laboratório). Sem
`lock_timeout` na mesma sessão, um `VACUUM FULL` esperando lock entra na fila
e trava todas as leituras que chegam depois dele.

O executor aceita somente arquivos canônicos de `supabase/migrations`, aplica
um por vez e grava SQL + versão no ledger na mesma transação. Não use o editor
como atalho nem `supabase db push`, que empurraria também o que não faz parte
desta janela. Se qualquer migration encontrar somente-leitura, pare: não
contorne o erro nem aplique fora do ledger.

Depois da P23, confira em `cron.job` que existe exatamente uma linha ativa
chamada `canario-retencao-do-log-do-cron`, no banco atual e sob `postgres`.
Depois do primeiro horário agendado, confirme uma execução `succeeded` em
`cron.job_run_details`; essa é a prova operacional que o laboratório local,
sem a extensão `pg_cron`, não consegue fabricar.

Depois de A57/A58 e do refresh do schema do PostgREST, dispare o workflow
manual `Sonda pública do backend A57/A58` (ou rode localmente
`python3 coletor/sonda_significado_publico.py`). Ele usa a publishable key do
app, faz três leituras mínimas e exige os contratos de
`similares_da_peca_amplo_v2`, `resumo_de_eventos` e
`buscar_referencia_editorial`. Qualquer 404/PGRST202 ou campo ausente bloqueia
a retomada; não espere o app publicado descobrir uma migration incompleta.
Esse verde comprova **contrato**, não frescor, cobertura nem liberação do app.

```bash
gh workflow run sonda-significado.yml
SONDA_RUN_ID="$(gh run list --workflow sonda-significado.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$SONDA_RUN_ID" --exit-status
```

Só depois da sonda verde, rotacione a senha conforme a seção 8. Em seguida:

```bash
gh workflow enable pipeline-diario.yml
gh workflow enable coleta-catalogo-candidato.yml
gh workflow run pipeline-diario.yml
```

Acompanhe a primeira execução até o fim. Durante sete dias, uma vez por dia:

```bash
"${CAP[@]}" ferramentas/capacidade/90_observacao.sql
```

O pipeline diário tem uma segunda prova, depois do motor: a sonda com
`--exigir-publicacao --data-operacional "$DATA_OPERACIONAL"`. Essa data vem do
início da coleta, preservada mesmo que a execução atravesse a meia-noite.
Ela exige que similares e resumo de eventos declarem o mesmo dia publicado,
igual ou posterior ao esperado. Reexecução de dia já publicado pode passar
mesmo com `observacoes_publicadas=0`; o contador de alterações não é o gate.
A busca editorial não carrega o marco diário e fica fora desse modo: um
timeout dela não pode transformar painel publicado em falso negativo. Seu
contrato continua obrigatório na sonda manual das três RPCs descrita acima.

O relatório `publicacao-painel.json` acompanha a run inclusive quando falha:
saída 0 significa a verificação solicitada aprovada; 1, falha de leitura ou
contrato; 2, publicação esperada não comprovada (antiga, ausente ou leituras
divergentes). O alerta diário só encerra o incidente com essa prova verde.
Não há retry de coleta, mudança de coorte nem escrita pela sonda. O modo
manual `sonda-significado.yml` continua sendo somente teste de contrato.

**Compatibilidade com o supervisor temporário:** ele interrompe futuras
coletas quando o pipeline termina em falha. Portanto, publicar este gate
enquanto a Animale continua adiada fará a ausência de atualização aparecer
como falha e poderá acionar essa interrupção. Resolver capacidade/cobertura
ou revisar explicitamente a política de acompanhamento antes do rollout;
não remover o gate nem considerar os dias parciais como sete dias saudáveis.

## 7. O que está provado, e onde

- **`node ferramentas/laboratorio_capacidade/rodar.mjs`** — P21, P22, P24 e
  P25 num PostgreSQL 17.10. As funções "de antes" vêm das migrations e, quando
  produção diverge do histórico, de uma captura explícita em `producao/`; o
  hash de cada uma é conferido contra o medido em produção; a linha de base
  prova que o código de hoje reescreve 100% das linhas; as asserções provam,
  caminho por caminho, primeira escrita, reexecução com zero linhas
  reescritas e mudança real com só as linhas necessárias — pelo retorno da
  função, pelo contador da transação e pelo `ctid` — e que recalcular do zero
  dá a mesma tabela.
- **`node ferramentas/capacidade/teste_roteiro.mjs`** — os arquivos pelo mesmo
  executor que rodaria em produção, conectado como um papel sem superusuário
  no formato do `postgres` do Supabase: ensaio não escreve; cada ação encolhe
  o alvo sem perder linha; cada pré-condição aborta antes da ação; `VACUUM`
  sem MAINTAIN é pego; o TRUNCATE vem desarmado; os snapshots não são tocados;
  os três ramos de 55/40/60 são exercitados pelo próprio executor; migration e
  ledger entram juntos ou não entram; ensaio não grava e reaplicação é
  recusada.
- **`node ferramentas/laboratorio_significado/rodar.mjs`** — executa P24,
  A57 e A58 na ordem real, roda o passo 87 e depois as 24 asserções de
  significado. Isso prova também os hashes por assinatura, a convivência v1/v2,
  o backfill do denominador, o marcador publicado e os privilégios públicos.
- **Não provado:** tempo e espaço reais de produção (as tabelas do
  laboratório são pequenas e o disco é outro) e a execução da P23, porque o
  pg_cron não existe no PostgreSQL embutido. A P23 tem portão estrutural que
  exige pré-condições, agendamento idempotente, reativação e pós-condição
  atômica; o comportamento real do serviço só se confirma na aplicação.

## 8. Rotação da senha administrativa

Depois das migrations preventivas e do rollout de backend A57/A58, e antes de
retomar a coleta. Nunca no meio de um passo, nunca durante um dump.

1. **Inventariar os consumidores.** Neste repositório nada lê a senha do
   banco (conferido em 18/09): os workflows usam `SUPABASE_URL` e
   `SUPABASE_SECRET_KEY`, e as Edge Functions usam chaves de API. Os
   consumidores conhecidos são operacionais e digitam a senha num prompt: o
   procedimento de backup do Codex e este executor. Falta inventariar o que
   está fora do repositório: clientes locais (TablePlus, DBeaver, `.pgpass`),
   gerenciadores de senha, a worktree do Codex e qualquer segredo de CI fora
   deste repositório.
2. **Gerar** a senha nova num gerenciador de senhas e trocá-la no painel
   (*Database → Settings*). Ela não entra em chat, código, documentação,
   commit ou log.
3. **Esperar o efeito conhecido:** segundo a documentação, os serviços
   gerenciados (PostgREST, pooler) passam a usar a senha nova sem
   indisponibilidade, mas o pooler compartilhado pode recusar com `28P01`
   por alguns segundos. Conferir por conexão direta antes de concluir que a
   senha está errada, e não trocar de novo em seguida.
4. **Atualizar** cada consumidor do inventário e confirmar que a coleta e o
   motor continuam verdes — eles não dependem da senha, e essa conferência
   prova isso.
5. **Registrar** a data da rotação no `ESTADO.md`. Só a data.
