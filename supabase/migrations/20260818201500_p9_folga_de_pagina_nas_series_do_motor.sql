-- P9: o mesmo remédio da P8 nas duas tabelas que o motor reescreve.
--
-- Medido em 18/08/2026, com os contadores acumulados de pg_stat_user_tables:
--
--   series_semanais    1.769.255 updates, apenas  7,5% HOT
--   indices_semanais     396.269 updates, apenas  1,9% HOT
--
-- São ~70 updates por linha em series_semanais, que tem 25.676 linhas: o motor
-- reescreve a série inteira a cada publicação. Com fillfactor 100 não há folga
-- na página, então cada reescrita vira página nova e a antiga só é liberada
-- como espaço solto. Por isso a tabela aparecia com 16,9 MiB de dado vivo
-- dentro de 48,2 MiB de heap.
--
-- HOT é possível nas duas porque os índices cobrem apenas identidade e chave
-- natural -- id, (termo_id, segmento, fonte, semana) e (termo_id, segmento,
-- semana) -- enquanto o motor atualiza colunas de valor, não indexadas.
--
-- Resultado após VACUUM FULL: series_semanais 48,2 -> 26,6 MiB, já contando a
-- folga de 30% que o fillfactor reserva.
--
-- produto_termos fica de fora de propósito: lá são 8,6 milhões de inserts
-- contra 8,4 milhões de deletes -- o motor reconstrói a tabela em vez de
-- atualizar. fillfactor não ajuda nesse padrão; quem cuida é o autovacuum.

alter table public.series_semanais set (fillfactor = 70);
alter table public.indices_semanais set (fillfactor = 70);

comment on table public.series_semanais is
  'Séries por fonte e semana. fillfactor 70 desde a P9: o motor reescreve a série inteira a cada publicação e sem folga na página cada reescrita virava página nova.';
