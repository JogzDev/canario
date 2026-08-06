-- O app baixa megabytes de prosa que ele nunca le. Duas views enxutas.
--
-- MEDIDO EM 06/08
-- ===============
--
-- Peso de 400 linhas, e quanto disso e a coluna `meta`:
--
--   series_semanais    272 kB   -- 235 kB (86%) e meta
--   indices_semanais   286 kB   -- 234 kB (82%) e meta
--   series_semanais (2000 linhas, que a aba Explorar pede)   1,5 MB
--
-- Abrindo o meta chave a chave, em 400 linhas de `indices_semanais`:
--
--   por_que                    37 kB   <- nao lido pelo app
--   pesos                      34 kB   <- nao lido
--   obs_varejo                 27 kB   <- nao lido
--   estado_indisponivel_por    17 kB   <- nao lido
--   computado_em               16 kB   <- nao lido
--   pernas_que_confirmam       12 kB   <- nao lido
--   indice_semana_anterior    7,1 kB   <- LIDO
--   pernas_acima_de_1         6,2 kB   <- LIDO
--   pernas_abaixo_de_-1       6,2 kB   <- LIDO
--
-- O app decodifica TRES escalares e recebe 234 kB. Sao frases identicas
-- repetidas em cada uma das 9 mil linhas -- a mesma explicacao, milhares de
-- vezes, pela rede, no celular de quem abre a tela.
--
-- Em `series_semanais` o desperdicio e menor mas existe: `obs` (41 kB) e
-- `obs_normalizacao` (31 kB) nao estao sequer declarados no modelo Swift.
--
-- POR QUE VIEW, E NAO APAGAR O META
-- =================================
--
-- A prosa esta la por causa da regra 3: cada numero carrega o caminho ate a
-- origem, e quem audita o banco tem que achar a explicacao junto do dado. Ela
-- fica. O que muda e o que ATRAVESSA A REDE: o app passa a ler uma projecao
-- com os campos que ele de fato decodifica, com os mesmos nomes, para o
-- Decodable nao mudar.
--
-- `security_invoker = true` desde o nascimento: as duas tabelas de base ja tem
-- policy de leitura para anon/authenticated, entao nao ha o que contornar.

create or replace view public.indices_do_app
with (security_invoker = true) as
select
  i.id, i.termo_id, i.segmento, i.semana, i.indice, i.estado,
  i.pernas_ativas, i.n_pernas, i.computado_em,
  jsonb_strip_nulls(jsonb_build_object(
    'indice_semana_anterior', i.meta -> 'indice_semana_anterior',
    'pernas_acima_de_1',      i.meta -> 'pernas_acima_de_1',
    'pernas_abaixo_de_-1',    i.meta -> 'pernas_abaixo_de_-1'
  )) as meta
from public.indices_semanais i;

comment on view public.indices_do_app is
  'Projecao de `indices_semanais` para o app: so os campos de `meta` que o Decodable le. Medido em 06/08: o meta completo pesa 234 kB em 400 linhas e o app usa 19 kB deles. A prosa continua na tabela, para auditoria (regra 3).';

create or replace view public.series_do_app
with (security_invoker = true) as
select
  s.id, s.termo_id, s.segmento, s.fonte, s.semana,
  s.valor_bruto, s.z, s.n_amostra,
  jsonb_strip_nulls(jsonb_build_object(
    'unidade',              s.meta -> 'unidade',
    'veiculos',             s.meta -> 'veiculos',
    'exemplos',             s.meta -> 'exemplos',
    'contagem_semana_crua', s.meta -> 'contagem_semana_crua',
    'metrica',              s.meta -> 'metrica',
    'n_total_sortimento',   s.meta -> 'n_total_sortimento'
  )) as meta
from public.series_semanais s;

comment on view public.series_do_app is
  'Projecao de `series_semanais` para o app: so os campos de `meta` que o Decodable le. `exemplos` e `veiculos` FICAM -- sao a regra 3 na tela ("Elle Brasil (4) e Vogue Brasil (2)"). Saem `obs` e `obs_normalizacao`, que pesam 72 kB em 400 linhas e nao estao no modelo.';

grant select on public.indices_do_app, public.series_do_app
  to anon, authenticated;
