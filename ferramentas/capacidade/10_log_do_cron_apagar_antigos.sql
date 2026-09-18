-- PASSO 10 · REMOVE LINHAS. NAO DEVOLVE ESPACO FISICO.
--
-- @alvo cron.job_run_details
--
-- Alvo: `cron.job_run_details`, o log do pg_cron. Dono: supabase_admin; o
-- papel postgres tem DELETE (medido em 18/09).
--
-- O que faz: apaga as execucoes bem-sucedidas com mais de 7 dias e qualquer
-- execucao com mais de 30 -- a mesma regra que a P23 agenda para todo dia.
-- Em 18/09: 65.811 linhas, 16.670.720 bytes, 1.440 linhas por dia.
--
-- O que NAO faz: devolver espaco. `delete` marca as linhas como mortas; o
-- arquivo continua do mesmo tamanho ate o passo 11. Ganho fisico: zero.
--
-- Lock: ROW EXCLUSIVE, o mesmo das escritas do proprio pg_cron. Nao bloqueia
-- ninguem. Duracao esperada: segundos (60 mil linhas, sem indice alem da PK).
-- Espaco temporario: nenhum; WAL de ate ~17 MB (imagens das paginas tocadas).
--
-- Abortar se: o executor acusar lock ou tempo esgotado. Repetir e seguro:
-- a segunda vez apaga zero.

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
delete from cron.job_run_details
 where (end_time < now() - interval '7 days' and status = 'succeeded')
    or end_time < now() - interval '30 days';
