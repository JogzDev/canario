-- Desfaz a troca para janela diaria. O rotulo consertado FICA.
--
-- O QUE ACONTECEU
-- ===============
--
-- Em 05/08 achei dois defeitos na perna de busca e consertei os dois de uma
-- vez. Um era real: o rotulo de semana vinha seis dias adiantado, e a §22
-- comparava periodos quase disjuntos. O outro eu inventei: concluí que a fonte
-- tinha ~10 dias de atraso e troquei a janela semanal (`today 5-y`) por uma
-- diaria de 240 dias, agregada por nos em semana ISO.
--
-- A segunda troca estava errada, por duas medicoes que fiz tarde demais:
--
-- 1. NAO HAVIA ATRASO A CORRIGIR. Contando semanas ISO fechadas -- a unidade
--    que o app usa -- as duas janelas chegam na MESMA semana (27/07, medido no
--    mesmo minuto). O atraso aparente era o proprio rotulo errado.
--
-- 2. A DIARIA APAGA TERMO PEQUENO. O Trends normaliza 0-100 pelo maior valor
--    da janela; num recorte diario o maximo e o maior DIA do maior termo, e
--    volume baixo arredonda para zero. Medido no mesmo termo:
--
--                      semanas em zero (semanal)   (diario)
--      viscose_fluido            0,9%                73,5%
--      animal_print             10,6%                88,2%
--      algodao                  54,2%                94,1%
--
--    Escrevi que o semanal "mascarava serie vazia". Era o contrario: o diario
--    apagava sinal que existe. `viscose_fluido` tem busca em 99% das semanas.
--
-- Tres termos perderam a perna de busca por causa disso. E o degrau entre as
-- duas reguas obrigou a arquivar 5 anos de historico que nao precisava sair.
--
-- O QUE ESTA MIGRACAO FAZ
-- =======================
--
-- Devolve o arquivo e remove as linhas da escala diaria. Fica um vazio de
-- 08/12/2025 ate agora nos 12 termos afetados, porque a coleta diaria
-- sobrescreveu esse trecho e o valor antigo se perdeu no upsert. O vazio se
-- fecha sozinho: a fila do coletor ordena por defasagem, entao esses 12 termos
-- vao para a frente da fila na proxima execucao.
--
-- O rotulo +7 aplicado em 20260805160000 CONTINUA VALENDO -- aquele era o
-- conserto de verdade.

-- `id` e GENERATED ALWAYS: o valor original nao pode ser reinserido sem
-- OVERRIDING SYSTEM VALUE, e nada referencia essa chave -- a unicidade que
-- importa e (termo_id, segmento, fonte, semana). Entra com id novo.
insert into public.series_semanais
  (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
select termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta
from public.series_busca_5y_legado
on conflict (termo_id, segmento, fonte, semana) do nothing;

delete from public.series_semanais
 where fonte = 'busca'
   and meta->>'granularidade' = 'diaria->semana_iso';

drop table public.series_busca_5y_legado;
