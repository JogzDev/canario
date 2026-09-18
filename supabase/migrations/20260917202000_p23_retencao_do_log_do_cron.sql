-- P23: o log do pg_cron deixa de crescer para sempre.
--
-- POR QUE
-- =======
--
-- `canario-motor-dispatcher` roda a cada minuto (P0, 03/08/2026) e cada
-- execucao grava uma linha em `cron.job_run_details`. Nada apaga essas linhas.
-- Medido em 18/09/2026, em leitura:
--
--   65.811 linhas, de 03/08 a 18/09     16.670.720 bytes
--   1.440 linhas por dia                 ~360 KB por dia
--
-- E o crescimento que continua com a coleta PARADA. Entre 02:33 e 12:37 UTC
-- de 18/09 o banco principal cresceu 180.224 bytes -- ~430 KB por dia no
-- mesmo ritmo, compativel com os ~360 KB/dia deste log somados ao que o
-- autovacuum e as estatisticas escrevem.
--
-- Nada no projeto le esse log -- o estado das publicacoes vive em
-- `motor_execucoes` (conferido em supabase/migrations, coletor/, ferramentas/ e
-- .github/ em 18/09). Ele e diagnostico do pg_cron, e diagnostico de mais de
-- uma semana nao responde pergunta nenhuma que `motor_execucoes` nao responda.
--
-- O QUE ESTE JOB FAZ
-- ==================
--
-- Uma vez por dia, as 04:17 UTC -- fora da janela do pipeline, que comeca as
-- 06:00 UTC --, apaga:
--
--   execucoes bem-sucedidas com mais de 7 dias
--   qualquer execucao com mais de 30 dias
--
-- Falha fica quatro vezes mais tempo porque e a que alguem vai querer ler.
-- Execucao em andamento tem `end_time` nulo e nunca e apagada.
--
-- Regime esperado: ~10 mil linhas, ~2,5 MB.
--
-- O QUE ESTE JOB NAO FAZ
-- ======================
--
-- `delete` nao devolve espaco fisico: ele libera paginas para a propria tabela
-- reusar. Os 16,7 MB que ja existem so voltam com uma acao fisica unica
-- (TRUNCATE ou VACUUM FULL da tabela), que esta no roteiro da etapa 1 com
-- escopo, lock e consequencia -- e nao aqui. Esta migration e so a prevencao:
-- sem ela, qualquer limpeza volta a crescer ~11 MB por mes.
--
-- `cron.schedule` com nome atualiza o job se ele ja existir, entao reaplicar
-- esta migration nao duplica nada.

select cron.schedule(
  'canario-retencao-do-log-do-cron',
  '17 4 * * *',
  $$delete from cron.job_run_details
     where end_time < now() - interval '7 days'
       and status = 'succeeded';
    delete from cron.job_run_details
     where end_time < now() - interval '30 days';$$
);
