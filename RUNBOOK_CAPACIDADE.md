# Capacidade e retomada do pipeline — 16/09/2026

Este guia registra diagnóstico e procedimento. **Não é autorização de execução
destrutiva, mudança de plano ou deploy.** Estado vigente em `ESTADO.md`.

## 1. O que realmente parou

O Actions está disparando o pipeline. As 14 execuções agendadas de 03 a 16/09
falharam; a última verde foi em 02/09 (`33618011684`). A coleta bloqueia ao
atingir 96% do limite configurado e não chega ao motor que executaria a retenção.

- [Execução de 16/09](https://github.com/JogzDev/canario/actions/runs/35085125578):
  485.125.267 / 500.000.000 bytes, aproximadamente 97%.
- [Incidente #24](https://github.com/JogzDev/canario/issues/24): aberto em 03/09
  e atualizado diariamente. Existe alerta; faltou um caminho de recuperação.
- Os dois runners estavam online e ociosos. Em 16/09 o primeiro job começou
  quatro segundos após a criação da execução: não há evidência de fila do runner
  como causa dessa falha.
- O cron está em 06:00 UTC, mas as execuções recentes foram criadas entre 09:37
  e 11:13 UTC. Esse atraso de disparo é outro problema; medir separadamente,
  sem atribuir toda a diferença a congestionamento sem prova.

GitHub admite atrasos em eventos agendados e só os executa na branch padrão.
Uma correção apenas nesta branch não muda o agendamento de produção.
[Documentação do Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

## 2. Fotografia de produção, somente leitura

Medição: **16/09/2026, 13:40 UTC**. PostgreSQL 17.6, projeto
`ACTIVE_HEALTHY`, `default_transaction_read_only=off`.

| Recurso | Medição | Interpretação |
|---|---:|---|
| Banco PostgreSQL | 485.174.419 bytes | 97,03% do limite configurado |
| Limite usado pela RPC | 500.000.000 bytes | Constante da aplicação, não leitura do billing |
| Margem até esse limite | 14.825.581 bytes | Não equivale a espaço físico livre confirmado do disco |
| Liberar para ficar abaixo de 96% | 5.174.420 bytes | Mínimo matemático, não margem operacional sustentável |
| Liberar para ficar abaixo de 85% | 60.174.420 bytes | Meta de margem, não promessa de bytes recuperáveis |
| Storage | 18 objetos / 7.472.925 bytes | Fotos não são o gargalo |
| Último motor concluído | 02/09/2026 11:13 UTC | Dados não se tornam atuais por o endpoint responder |
| Snapshots | 254.736, de 12/08 a 02/09 | Não inventar observações dos dias sem coleta |

O plano comercial não foi confirmado no billing. “500 MB” aqui significa o
limite configurado para o Free. Uma contratação não atualiza automaticamente
essa constante: limite real e portão precisam ser conciliados conscientemente.

### Maiores relações (tabela + índices)

| Relação | Bytes |
|---|---:|
| artigos | 105.668.608 |
| produtos | 85.598.208 |
| series_semanais | 79.085.568 |
| snapshots | 72.155.136 |
| produto_termos | 37.945.344 |
| eventos | 28.082.176 |
| estado_dos_produtos | 20.045.824 |
| indices_semanais | 18.718.720 |
| cron.job_run_details | 15.900.672 |

`artigos_url_key` ocupa 41.951.232 bytes, com 639.641 varreduras registradas.
Tamanho não o torna dispensável. Não remover índices úteis para passar no portão.

## 3. Causas estruturais

1. **Retenção depende do fluxo bloqueado.** `coleta.yml` testa capacidade antes
   de escrever; `computar_motor()` poda snapshots só após todos os consumidores.
   Quando a coleta falha, a saúde bloqueia o motor, e a retenção não é executada.
2. **Logs crescem mesmo sem coleta.** O dispatcher roda a cada minuto e acumula
   registros em `cron.job_run_details`, sem retenção encontrada no repositório.
   São 62.993 execuções desde 03/08, 19.544 desde 03/09; as tuplas destas últimas
   somam 4.065.152 bytes, antes de índices/páginas. É contribuição medida,
   compatível com boa parte do crescimento durante o incidente, não uma
   decomposição exata de todos os bytes do banco.
3. **Há caminhos de reescrita desnecessária.** A29 atualiza classificação mesmo
   sem alteração semântica e substitui a perna editorial inteira. A30 atualiza
   `meta.computado_em` no varejo. Reduzir esse churn exige comparação de conteúdo
   e teste de equivalência, não simplesmente remover timestamps.
4. **Recuperação Shopify podia ser pulada.** O job não declarava `always()`:
   o sucesso implícito dos ancestrais impedia o retry justamente após falha.
   Corrigir isso sem verificar capacidade criaria tentativa inútil com banco cheio.

## 4. O que esta primeira fatia corrige

- Diagnóstico de capacidade JSON, mantendo bloqueio inclusivo em 96%.
- Valores ausentes, inválidos ou consulta falha negam permissão de escrita.
- Folga, excesso e distância dos limiares expressos em bytes decimais.
- Recuperação Shopify só é elegível com saúde explicitamente falsa, capacidade
  verificada permitindo escrita e execução não cancelada.
- Testes de limites, RPC inválida, CLI anterior, saída Actions e condições de jobs.

Isso **não libera espaço**, não ativa produção e não garante recuperação de
todas as fontes. Não afrouxa saúde, capacidade ou publicação para obter verde.

## 5. Sequência segura de recuperação

### A — preservar e medir

1. Capturar novamente tamanho, maiores relações, plano real, disco físico,
   últimos watermarks e estado de filas; confirmar ausência de manutenção concorrente.
2. Preparar backup privado recuperável e ensaiar restauração isolada. Banco,
   objetos do Storage e configurações Auth/Edge são superfícies diferentes.
3. Medir páginas reutilizáveis/inchaço antes de escolher compactação. `pgstattuple`
   não está instalado; zero tuplas mortas estimadas não prova ausência de páginas
   vazias. Não instalar extensão como efeito colateral de consulta read-only.

### B — escolher margem sustentável

**Caminho gerenciado recomendado:** confirmar preço e plano da organização e,
com decisão financeira explícita, considerar Supabase Pro. O preço anunciado é
a partir de US$25/mês, com 8 GB de disco por projeto; compute, projetos adicionais,
impostos e extras dependem da contratação. Confirmar limite efetivo e ajustar o
portão da aplicação com teste e rollout controlado. A ampliação compra margem;
não substitui retenção nem correção de reescritas.
[Preços oficiais](https://supabase.com/pricing).

**Caminho sem contratação:** escolher alvos pequenos, arquivar/verificar logs
operacionais e ensaiar recuperação física com espaço e janela de locks medidos.
Nenhuma remoção foi executada. Mesmo recuperar todos os 15,9 MB de logs deixaria
o banco por volta de 93,9%, apenas cerca de 6 MB abaixo do bloqueio. Não chamar
isso de solução sustentável nem prometer recuperação gratuita definitiva.

`DELETE` geralmente permite reutilizar páginas, não devolve automaticamente o
tamanho ao sistema. `VACUUM FULL` exige cópia e lock exclusivo. **Não executar
compactação de uma tabela de ~79 MB com apenas a margem lógica acima sem provar
espaço físico suficiente e compatibilidade operacional.**
[PostgreSQL: manutenção](https://www.postgresql.org/docs/17/routine-vacuuming.html).

### C — remover a dependência circular

1. Política de retenção de logs independente da coleta: sucessos recentes,
   falhas úteis, arquivo verificado e limite de volume; retenções aprovadas.
2. Manutenção com lock próprio, dry-run, limite de tempo e de linhas por lote.
3. Snapshots: decidir corte pelo último ciclo consumido/publicado e preservar
   fronteiras semanais e estados-âncora necessários aos consumidores.
4. Testar interrupção, repetição, mais de 14 dias sem coleta e ausência de motor.
   Manutenção não pode publicar índices de um dia incompleto.
5. Corrigir escrita idêntica e medir crescimento por ciclo, não apenas logo após
   uma limpeza. Não alterar o cron do dispatcher sem medir latência de publicação.

Hoje `current_date - 21` tornaria 170.978 snapshots elegíveis. Eles já foram
consumidos pelo motor de 02/09; **não são comprovadamente dados inéditos**.
O risco é recortar a semana de 24/08 em 26/08 e depois recomputá-la parcialmente.
É risco de desenho, não perda já comprovada. Nenhuma poda por idade foi feita.

### D — retomar e provar

1. Publicar a correção operacional apenas em janela/escopo autorizados, mantendo
   binário, dados privados e método do app entregue intactos.
2. Executar ciclo controlado completo, com capacidade antes/depois, saúde de
   cada fonte, publicação atômica, logs e contagens verificadas.
3. Marcar a lacuna de coleta como lacuna; não preenchê-la com zero nem backfill
   que finja ter observado disponibilidade/preço naquela data.
4. Observar o próximo disparo agendado e crescimento em ciclos posteriores.
5. Acrescentar monitor independente para job ausente, freshness e capacidade.
   Um workflow dependente do mesmo runner não detecta confiavelmente sua queda.
6. Em falha de rollout, suspender novas escritas da fatia e restaurar o código
   anterior. Restore de dados só a partir do backup validado e com impacto nas
   escritas posteriores explicitamente tratado; não é um botão genérico de rollback.

## 6. Permanecer ou migrar

A evidência atual não justifica migrar Storage nem trocar toda a plataforma.
Auth, `auth.uid()`, RLS, RPC/PostgREST, Storage privado, cron e Edge Functions são
dependências reais. Outro PostgreSQL herda retenção e churn se o desenho ficar igual.

OP-07 compara Supabase gerenciado, PostgreSQL gerenciado alternativo, arquitetura
híbrida e self-hosted pelo custo total, portabilidade, restauração e carga de operação.
Só iniciar OP-08 depois de critério de saída, destino, custo e ensaio definidos.
[Limites e tamanho do banco](https://supabase.com/docs/guides/platform/database-size).

## 7. Consultas reproduzíveis, somente leitura

Executar individualmente com cliente autenticado, sem imprimir segredos. Não
incluir dados pessoais nem resultados brutos do Closet em relatórios públicos.
Usar `BEGIN READ ONLY; SET LOCAL statement_timeout='5s';` antes de cada consulta
e `COMMIT;` após ela. Em timeout, fazer `ROLLBACK`, não retirar o limite.

```sql
SELECT now() AS measured_at,
       pg_database_size(current_database()) AS database_bytes,
       current_setting('default_transaction_read_only') AS default_read_only;
```

```sql
SELECT schemaname, relname, pg_total_relation_size(relid) AS total_bytes,
       pg_relation_size(relid) AS heap_bytes, pg_indexes_size(relid) AS index_bytes,
       n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 25;
```

```sql
SELECT count(*) AS objects,
       coalesce(sum((metadata->>'size')::bigint),0) AS bytes FROM storage.objects;
```

```sql
SELECT count(*) AS rows, min(start_time) AS oldest, max(start_time) AS newest
FROM cron.job_run_details;
```

```sql
SELECT status, count(*) AS rows, max(concluido_em) AS last_finished
FROM public.motor_execucoes GROUP BY status;
```

```sql
SELECT fonte, count(*) AS rows, min(semana) AS oldest_week,
       max(semana) AS newest_week FROM public.series_semanais GROUP BY fonte;
```

O diagnóstico leve da RPC também pode ser consultado com
`python3 coletor/verificar_capacidade_banco.py --json`, usando configuração
autorizada no ambiente. Retorno 1 em capacidade crítica/indisponível é intencional.
