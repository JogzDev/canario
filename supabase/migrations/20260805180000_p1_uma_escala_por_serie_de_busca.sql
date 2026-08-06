-- Uma serie de busca, uma escala. O historico do `today 5-y` vai para arquivo.
--
-- O PROBLEMA, MEDIDO
-- ==================
--
-- A perna de busca passou a ser montada de dado diario numa janela de 240
-- dias. O upsert sobrescreve as 34 semanas dessa janela e deixa intactas as
-- ~227 semanas anteriores, que vieram do `today 5-y`. As duas normalizacoes
-- sao diferentes -- o Trends normaliza 0-100 DENTRO de cada consulta -- e o
-- resultado e um degrau no meio da serie. Em `alfaiataria`:
--
--   2025-12-01  14.00  antigo (5-y)
--   2025-12-08   6.00  novo (diario)   <-- a costura
--   2025-12-15   3.71  novo
--   2025-12-29   0.00  novo
--
-- Nao e queda de mercado, e troca de regua. O tamanho do degrau depende do
-- volume do termo: `vestido` atravessa com +2%, `azul` com -5%, `alfaiataria`
-- com -70%, `algodao` com -95%.
--
-- POR QUE ISTO E URGENTE
-- ======================
--
-- Os pontos novos estao com z nulo: `computar_z()` ainda nao rodou depois da
-- coleta. Na proxima execucao do pipeline, a janela movel de 12 semanas da §21
-- vai atravessar a costura, ler o degrau como movimento e acender "em queda"
-- em cima de uma troca de unidade. Seria uma afirmacao sobre o mercado que o
-- mercado nao fez -- exatamente o que a regra 2 proibe.
--
-- A ESCOLHA
-- =========
--
-- Reescalar o novo para o antigo foi medido e descartado: o fator de emenda
-- erra 2,4% em `alfaiataria` e 20,8% (max 60%) em `vestido floral`, que e a
-- ancora do K7 -- a regua de todos os outros. Emendar pela ancora seria
-- carregar o maior erro no lugar de maior consequencia.
--
-- Entao: uma escala por serie. As 34 semanas da janela diaria bastam para as
-- 12 da §21, com folga de quase tres vezes.
--
-- NAO E APAGAR. As linhas antigas vao inteiras para `series_busca_5y_legado`,
-- com o motivo. Da para conferir, comparar e voltar atras -- e um `today 5-y`
-- novo sempre pode ser coletado, ao contrario do diario, que so existe para
-- os ultimos ~269 dias.

create table if not exists public.series_busca_5y_legado (
  like public.series_semanais including defaults,
  arquivado_em timestamptz not null default now(),
  motivo text
);

alter table public.series_busca_5y_legado enable row level security;

comment on table public.series_busca_5y_legado is
  'Historico da perna de busca coletado com a janela `today 5-y`, aposentado em 05/08/2026 quando a perna passou a ser montada de dado diario. Escala diferente da serie viva: nao emendar sem reescalar, e a reescala foi medida com erro de ate 60% na ancora.';

-- So dos termos que JA receberam dado novo. Termo ainda nao rotacionado
-- continua com a serie antiga inteira e coerente, e sai daqui quando chegar a
-- vez dele -- a mesma limpeza roda no coletor.
with alvos as (
  select distinct termo_id
  from public.series_semanais
  where fonte = 'busca' and meta->>'granularidade' is not null
),
antigas as (
  delete from public.series_semanais s
  using alvos a
  where s.fonte = 'busca'
    and s.termo_id = a.termo_id
    and s.meta->>'granularidade' is null
  returning s.*
)
insert into public.series_busca_5y_legado
  (id, termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta, motivo)
select id, termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta,
       'escala do today 5-y; a perna passou a ser montada de dado diario'
from antigas;
