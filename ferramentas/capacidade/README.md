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

A ordem é a aprovada:

1. medir de novo em leitura (`00_inventario.sql`);
2. revisar com vocês o roteiro e os alvos;
3. executar a recuperação com 10, 11, 20, 21, 30 e 50; medir; se a cota ainda
   estiver acima de 400 MB, ir **direto ao 60**, sem executar o 40 antes;
4. confirmar escrita liberada e pelo menos 20% de folga (passo 70);
5. passar pelo portão 80 e aplicar P21, P22, P23, P24 e P25, nessa ordem,
   pelo executor de migrations e com o papel canônico `postgres`;
6. aplicar A57 e depois A58, no mesmo rollout de backend e antes de retomar a
   coleta. A58 depende do marcador criado pela A57; não são opcionais entre
   si. A P24 é apenas a guarda temporária até a A58 materializar o denominador
   e reativar a poda com segurança;
7. executar a sonda pública das RPCs depois do refresh do schema do PostgREST;
8. rotacionar a senha administrativa pelo procedimento da seção 8;
9. retomar a coleta e observar por sete dias (passo 90, uma vez por dia);
10. só então publicar o app consumidor.

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

**P23 entra com as demais migrations, depois do passo 70.** O intervalo entre
a compactação e a prevenção custa ~360 KB por dia; este roteiro é uma única
janela operacional, não uma pausa de dias. Preservar a ordem cronológica das
migrations mantém o ledger coerente e evita tentar escrever antes de o passo
70 confirmar que o banco saiu do modo somente leitura. A P23 recusa execução
fora do papel `postgres`, que enxerga o catálogo inteiro e impede um job
homônimo de outro papel.

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
| `20` | devolve espaço | `estado_produtos_oferta_recente` | ~7,2 MB | ~2 MB | índice + share | 1–3 s |
| `21` | devolve espaço (opcional) | `estado_dos_produtos_pkey` | ~2,0 MB | ~3 MB | índice + share | 1–3 s |
| `30` | devolve espaço | `indices_semanais` | ~7,3 MB | ~11 MB | access exclusive | 2–8 s |
| `40` | alternativa parcial, não sequencial | `artigos_url_key` | ~19,9 MB | ~22 MB | índice + share | 3–15 s |
| `50` | devolve espaço | `series_semanais` | ~43,4 MB | ~36 MB | access exclusive | 5–20 s |
| `60` | devolve espaço (condicional) | `artigos` + índices | ~35,7 MB | ~70 MB | access exclusive | 10–40 s |
| `70` | leitura | folga ≥ 20% e escrita livre | — | — | nenhum | segundos |
| `80` | leitura | funções = as de 18/09 | — | — | nenhum | segundos |
| `90` | leitura | observação diária | — | — | nenhum | segundos |

**Acumulado estimado do caminho normal** a partir de 501,2 MB: 487,1 depois do
11 · 479,9 do 20 · 477,9 do 21 · 470,6 do 30 · **427,2 do 50 (85,4%)**. Meça
nesse ponto. Se a cota estiver acima de 400 MB, pule o 40 e rode o 60
diretamente: ele reescreve `artigos` e reconstrói, uma única vez,
`artigos_pkey` e `artigos_url_key`. O ganho direto estimado é ~35,7 MB e o
resultado, **391,5 MB (78,3%)**. O passo 60 recusa rodar se a meta já tiver
sido atingida.

**40 e 60 são ramos mutuamente exclusivos.** O 40 existe apenas como
alternativa parcial quando o 60 tiver sido descartado por sua janela de lock
ou por seu espaço temporário. Pelas medidas de 18/09, o 40 sozinho levaria
427,2 a ~407,3 MB e não atingiria os 20% de folga. Se ele for escolhido, rode o
70 em seguida; se o 70 falhar, pare e revise. Não execute o 60 depois: um
`VACUUM FULL artigos` reconstruiria de novo o índice que o 40 acabou de
reconstruir.

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

```bash
node ferramentas/capacidade/passo.mjs ferramentas/capacidade/00_inventario.sql --host <HOST DO POOLER DE SESSAO> --porta 5432 --usuario postgres.tbluoqpnjqsflfoclmms
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

As migrations P21 a P25 são SQL comum, sem `VACUUM`. Aplique **uma por vez,
só estes cinco arquivos e na ordem dos timestamps**, pelo executor de
migrations que registra o ledger e executa como `postgres`. Não use o editor
como atalho (ele deixa o histórico divergente) nem `supabase db push` (ele
empurraria também tudo o que ainda não foi aprovado). Se qualquer migration
encontrar o projeto em somente leitura apesar do passo 70, pare: não contorne
o erro nem aplique fora do ledger.

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

## 7. O que está provado, e onde

- **`node ferramentas/laboratorio_capacidade/rodar.mjs`** — P21, P22, P24 e
  P25 num
  PostgreSQL 17.10. As funções "de antes" são extraídas das migrations e o
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
  sem MAINTAIN é pego; o TRUNCATE vem desarmado; os snapshots não são tocados.
  Como o cluster descartável tem menos de 400 MB, a ação do 60 é extraída do
  arquivo e executada sem alteração: a prova confere que ela encolhe o heap,
  `artigos_pkey` e `artigos_url_key` de uma vez. A guarda real de 400 MB é
  testada separadamente pelo executor, e o 70 cobre tanto aprovação quanto
  rejeição da meta.
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
