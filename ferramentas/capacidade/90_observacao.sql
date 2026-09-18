-- PASSO 90 · SO LEITURA. Uma vez por dia, durante a janela de observacao.
--
-- A janela existe para MEDIR o crescimento com a coleta de volta, a
-- prevencao e o backend A57/A58 ja publicados, antes de liberar o app
-- consumidor. Este passo imprime o que mudou e sai com erro se um criterio de
-- parada for atingido. O erro e o sinal para parar a coleta e trazer os
-- numeros para revisao -- nunca para apagar dado.

do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
begin
  -- 85% e a faixa de aviso do portao. Chegar la durante a observacao
  -- significa que o crescimento come a folga em semanas, nao meses.
  if cota > 425000000 then
    raise exception 'PARAR: cota % bytes passou de 85%% durante a observacao', cota;
  end if;
  raise notice 'cota % bytes (% do limite)', cota,
    round(100.0 * cota / 500000000, 1) || '%';
end $$;

-- O que cada frente cresceu. Compare com a saida do dia anterior.
select now() as medido_em,
       (select sum(pg_database_size(oid)) from pg_database)::bigint as cota_bytes,
       pg_total_relation_size('public.series_semanais') as series_semanais,
       pg_total_relation_size('public.snapshots') as snapshots,
       pg_total_relation_size('public.produtos') as produtos,
       pg_total_relation_size('public.artigos') as artigos,
       pg_total_relation_size('public.indices_semanais') as indices_semanais,
       pg_total_relation_size('cron.job_run_details') as log_do_cron,
       (select count(*) from public.snapshots) as linhas_de_snapshots,
       (select n_tup_upd from pg_stat_all_tables
         where relid = 'public.series_semanais'::regclass) as updates_acumulados_series,
       (select n_tup_upd from pg_stat_all_tables
         where relid = 'public.indices_semanais'::regclass) as updates_acumulados_indices,
       (select count(*) from cron.job_run_details) as linhas_do_log;

-- A prova de que P22 e P25 estao funcionando: o que a ultima publicacao do motor
-- escreveu em cada caminho. Numeros proximos do tamanho da serie inteira
-- (29 mil em computar_z ou 9,9 mil em computar_indice) significam que a
-- prevencao correspondente nao esta ativa.
select execucao, status, concluido_em, resultado
from public.motor_execucoes
order by concluido_em desc nulls last
limit 3;
