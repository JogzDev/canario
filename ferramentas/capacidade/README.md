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
por si. As migrations P21 a P24.

## 3. A ordem, e três dependências que ela precisa respeitar

A ordem é a aprovada:

1. medir de novo em leitura (`00_inventario.sql`);
2. revisar com vocês o roteiro e os alvos;
3. autorizar e executar a menor recuperação segura (passos 10 a 60);
4. confirmar escrita liberada e pelo menos 20% de folga (passo 70);
5. aplicar a prevenção (passo 80, depois P21, P22, P23 e P24);
6. retomar a coleta e observar (passo 90, uma vez por dia);
7. só então A57/A58 no backend, e depois o app consumidor.

**P22 não precisa vir antes da compactação — mas precisa vir antes da
retomada.** Com a coleta parada o motor não roda, e nada reescreve
`series_semanais`. Na primeira publicação depois da retomada, sem a P22, o
motor reescreve até ~46,7 mil linhas e começa a comer os ~43 MB que o passo
50 devolve. Aplicá-la com o banco no limite é seguro: substitui três funções,
alguns KB de catálogo, sem tocar em linha nenhuma. Não mudei a ordem; só
registro que ela não é uma restrição.

**P23 fica na etapa 5, como a ordem manda, e o intervalo custa ~360 KB por
dia.** Se entre a recuperação e a prevenção passarem dias, vale aplicar a P23
junto com o passo 11. É uma decisão de vocês.

**P24 é um conflito que a ordem tinha, e eu não posso resolver em
silêncio.** A etapa 6 retoma a coleta antes da A58. A primeira publicação do
motor chama `podar_snapshots(21)`, cujo corte é de calendário: medido em
18/09, ela apagaria **202.050 das 254.736 linhas de snapshot — 16 dos 22
dias** (12/08 a 27/08). É a única fonte do denominador que a A58 reconstrói.
A P24 faz a poda devolver 0 enquanto `sortimento_diario` não existir. Custo
com a coleta rodando: ~2,7 MB por dia (11.579 linhas/dia; ~148 bytes de heap
e ~95 de índice cada), ~19 MB por semana. As alternativas sem custo mudam a
ordem ou o pacote — manter a coleta parada até a A58, ou aplicar antes só a
parte da A58 que cria `sortimento_diario` — e por isso ficam com vocês.

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
| `40` | devolve espaço | `artigos_url_key` | ~19,9 MB | ~22 MB | índice + share | 3–15 s |
| `50` | devolve espaço | `series_semanais` | ~43,4 MB | ~36 MB | access exclusive | 5–20 s |
| `60` | devolve espaço (condicional) | `artigos` | ~15,8 MB | ~70 MB | access exclusive | 10–40 s |
| `70` | leitura | folga ≥ 20% e escrita livre | — | — | nenhum | segundos |
| `80` | leitura | funções = as de 18/09 | — | — | nenhum | segundos |
| `90` | leitura | observação diária | — | — | nenhum | segundos |

**Acumulado estimado** a partir de 501,2 MB: 487,1 depois do 11 · 479,9 do 20 ·
477,9 do 21 · 470,6 do 30 · 450,7 do 40 · **407,3 do 50 (81,5%)** · **391,5 do
60 (78,3%)**. A meta de 20% de folga (≤ 400 MB) **depende do passo 60**: sem
ele a estimativa para em 18,5%. O passo 60 recusa rodar se o 70 já passar.

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

As migrations P21 a P24 são SQL comum, sem `VACUUM`, e podem ir pelo editor
ou pelo `apply_migration`, **uma por vez, só estes quatro arquivos** —
nunca `supabase db push`, que empurraria também tudo o que ainda não foi
aprovado.

## 7. O que está provado, e onde

- **`node ferramentas/laboratorio_capacidade/rodar.mjs`** — P21, P22 e P24 num
  PostgreSQL 17.10. As funções "de antes" são extraídas das migrations e o
  hash de cada uma é conferido contra o medido em produção; a linha de base
  prova que o código de hoje reescreve 100% das linhas; as asserções provam,
  caminho por caminho, primeira escrita, reexecução com zero linhas
  reescritas e mudança real com só as linhas necessárias — pelo retorno da
  função, pelo contador da transação e pelo `ctid` — e que recalcular do zero
  dá a mesma tabela.
- **`node ferramentas/capacidade/teste_roteiro.mjs`** — cada passo pelo mesmo
  executor que rodaria em produção, conectado como um papel sem superusuário
  no formato do `postgres` do Supabase: ensaio não escreve; cada ação
  encolhe o alvo sem perder linha; cada pré-condição aborta antes da ação;
  `VACUUM` sem MAINTAIN é pego; o TRUNCATE vem desarmado; os snapshots não
  são tocados.
- **Não provado:** tempo e espaço reais de produção (as tabelas do
  laboratório são pequenas e o disco é outro) e a P23, porque o pg_cron não
  existe no PostgreSQL embutido — ela tem só o portão de texto.

## 8. Rotação da senha administrativa

Depois da etapa 1 concluída e antes da A57/A58. Nunca no meio de um passo,
nunca durante um dump.

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
