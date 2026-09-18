-- PASSO 12 · ALTERNATIVA AOS PASSOS 10 + 11. NAO RECOMENDADA. DESARMADA.
--
-- @alvo cron.job_run_details
--
-- Escopo exato: `truncate cron.job_run_details` esvazia SO o log de execucoes
-- do pg_cron. Nao toca `cron.job` (as definicoes dos jobs, inclusive o
-- dispatcher do motor), nao reinicia a sequencia `runid` (sem RESTART
-- IDENTITY) e nao toca nenhum dado de negocio.
--
-- Consequencias:
--   - perde TODO o historico de execucoes do pg_cron: 65.811 linhas de 03/08
--     a hoje, inclusive mensagens de falha antigas;
--   - nada no projeto le esse log -- o estado das publicacoes mora em
--     `motor_execucoes` (conferido em migrations, coletor/, ferramentas/ e
--     .github/ em 18/09) --, entao nenhum portao, tela ou alerta muda;
--   - o dispatcher continua rodando; a proxima execucao grava normalmente.
--
-- Ganho: ~16,6 MB, contra ~14 MB dos passos 10 + 11. A diferenca, ~2,5 MB, e
-- uma semana de historico -- barata demais para justificar perder tudo. Por
-- isso a recomendacao e 10 + 11, e este arquivo vem DESARMADO: a primeira
-- pre-condicao recusa sempre, ate alguem editar o arquivo e trocar 'nao' por
-- 'sim' depois de uma autorizacao explicita.
--
-- Lock: ACCESS EXCLUSIVE, instantaneo. Temporario: nenhum.

do $$ begin
  if 'nao' <> 'sim' then
    raise exception 'ABORTAR: TRUNCATE e alternativa desarmada; use os passos 10 e 11';
  end if;
end $$;

-- PRE: nenhuma outra sessao segura lock na tabela. Com lock_timeout de 5 s a
-- acao nao ficaria presa, mas entrar na fila ja atrasaria quem le.
do $$ begin
  if exists (select 1 from pg_locks l
              where l.relation = 'cron.job_run_details'::regclass
                and l.pid <> pg_backend_pid()) then
    raise exception 'ABORTAR: outra sessao segura lock em cron.job_run_details';
  end if;
end $$;

-- @acao
truncate cron.job_run_details;
