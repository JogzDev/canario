-- P8: parar de reescrever a linha inteira de produto todo dia para mudar preço.
--
-- Medido em 18/08/2026: a linha média de `produtos` tem 1.079 bytes, dos quais
-- 769 (60,8%) são `descricao`. A coleta diária faz UPDATE em ~53 mil produtos
-- mudando apenas ultimo_preco_atual, ultimo_preco_original, ultima_grade e
-- ultimo_snapshot_em -- cerca de 58 bytes. Como o Postgres versiona a linha
-- inteira, cada update descarta a versão antiga e escreve uma nova. Foi assim
-- que o banco saiu de 279 MB para 468 MB em três dias, e VACUUM FULL só adia:
-- em 15/08 ele liberou 182 MB que voltaram em 72 horas.
--
-- `fillfactor = 70` reserva folga na página para a versão nova caber junto da
-- antiga -- o HOT update. Isso só é possível porque nenhuma coluna volátil é
-- indexada: os três índices de `produtos` cobrem id, (marca_id, id_externo) e
-- segmento, todos estáveis. Com HOT, a versão antiga é liberada na própria
-- página e reaproveitada, em vez de virar página nova no fim do arquivo.
--
-- Ensaio de 18/08, 5.000 linhas reescritas mudando só coluna volátil:
--   4.995 de 5.000 updates foram HOT (99,9%)
--   o heap cresceu 8.192 bytes -- uma página -- em vez de ~2 MB
--
-- Custo: fillfactor 70 deixa a tabela ~1,43x maior de forma permanente,
-- +44 MiB aqui. Paga-se uma vez, contra ~60 MB por dia.
--
-- `toast_tuple_target = 512` foi mantido por ser inofensivo, mas NÃO teve o
-- efeito esperado e isso fica registrado para ninguém repetir a hipótese: o
-- Postgres comprime antes de mover para fora da linha, e a `descricao`
-- comprimida já cabe no alvo. O TOAST ficou em 3,4 MiB. Quem for tentar de
-- novo precisa de STORAGE EXTERNAL, que desliga a compressão e troca ~60 MB
-- de disco por menos reescrita -- conta que hoje não fecha.
--
-- Reverter: alter table public.produtos set (fillfactor = 100,
-- toast_tuple_target = 2032); vacuum full public.produtos;

alter table public.produtos set (toast_tuple_target = 512, fillfactor = 70);

comment on table public.produtos is
  'Catálogo e estado atual. Armazenamento afinado em P8: fillfactor 70 dá folga na página para HOT update, porque a coleta diária atualiza preço e grade em ~53 mil linhas e nenhuma coluna volátil é indexada.';
