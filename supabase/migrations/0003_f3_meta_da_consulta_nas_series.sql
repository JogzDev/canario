-- §19: "Guardar a serie bruta com os metadados da consulta (intervalo, geo,
-- data da coleta), porque valores do Trends sao relativos a consulta; manter
-- intervalo e ancora consistentes entre coletas."
--
-- Sem isto o numero e literalmente incomparavel entre coletas, e a
-- rastreabilidade da regra 3 fica sem como reconstruir a consulta de origem.
alter table series_semanais
  add column meta jsonb;

comment on column series_semanais.meta is
  '§19: metadados da consulta (geo, intervalo, ancora, grupo, coletado_em). Valores do Trends sao relativos a consulta: sem isto a serie e incomparavel.';

-- Marca quais termos ficaram sem perna de busca, medido em vez de chutado (C3).
alter table termos
  add column volume_verificado_em date,
  add column volume_detalhe text;

comment on column termos.volume_verificado_em is
  'C3: data em que a coleta do Trends afericou o volume. sem_perna_busca deixa de ser `pendente` a partir daqui.';
