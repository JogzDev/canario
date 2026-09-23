-- Fixture da A61: o que a troca de catálogo precisa e a fixture base não tem.
--
-- A fixture base nasceu para a A57/A58 e deixa como talos os passos do motor
-- que não estavam sob teste. A A61 muda três deles de verdade -- eventos,
-- denominador e série de varejo --, então aqui entram as colunas e a tabela
-- que as versões reais leem, com as restrições de `marcas` como estão em
-- produção antes da A61.
--
-- As datas são FIXAS, ao contrário da fixture base: nenhuma das três funções
-- olha `current_date`, e a troca da Amaro que a A61 registra é de 23/09/2026.
-- O cenário é o real: catálogo antigo visto até terça 22/09, catálogo novo a
-- partir de quarta 23/09, semana de segunda 21/09.

alter table public.marcas add column plataforma text;
alter table public.marcas add constraint marcas_plataforma_check
  check (plataforma in ('vtex', 'shopify'));
alter table public.marcas add constraint marcas_status_teste_check
  check (status_teste in ('pendente', 'vtex', 'shopify', 'falhou', 'nao_se_aplica'));

alter table public.snapshots
  add column preco_atual numeric,
  add column preco_original numeric,
  add column grade_por_tamanho jsonb;

alter table public.termos add column papel text;

create table public.series_semanais (
  termo_id text not null,
  segmento text not null,
  fonte text not null,
  semana date not null,
  valor_bruto numeric,
  z numeric,
  n_amostra integer,
  meta jsonb,
  primary key (termo_id, segmento, fonte, semana)
);
grant all on public.series_semanais to service_role;

insert into public.marcas
  (id, nome, papel, segmento, status_teste, plataforma, ativa) values
  (7, 'Amaro', 'nucleo', 'feminino_casual_br', 'shopify', 'shopify', true),
  (71, 'Controle sem troca', 'nucleo', 'feminino_casual_br', 'vtex', 'vtex', true);

-- Um termo só destas duas marcas: a série dele mede exatamente a presença
-- delas, sem o ruído das 515 peças da fixture base.
insert into public.termos (id, rotulo, dimensao, status, papel) values
  ('lab_a61', 'Termo do laboratório A61', 'lab_a61', 'aprovado', 'atributo');

insert into public.produtos (id, marca_id, segmento, titulo, url) values
  -- catálogo antigo da Amaro
  (7001, 7, 'feminino_casual_br', 'Antigo visto na terca', 'https://amaro.com/products/a'),
  (7002, 7, 'feminino_casual_br', 'Antigo sumido em 01/09', 'https://amaro.com/products/b'),
  -- catálogo novo da Amaro
  (7101, 7, 'feminino_casual_br', 'Novo', 'https://amaro.com/produtos/a/'),
  -- a loja de controle perde uma peça de verdade
  (7201, 71, 'feminino_casual_br', 'Controle sumido em 01/09', 'https://controle.test/b/p');

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em) values
  (7001, date '2026-09-22', true, date '2026-09-22'),
  (7002, date '2026-09-01', true, date '2026-09-01'),
  (7101, date '2026-10-08', true, date '2026-10-08'),
  (7201, date '2026-09-01', true, date '2026-09-01');

insert into public.snapshots
  (produto_id, data, ofertavel, preco_atual, preco_original, grade_por_tamanho) values
  (7001, date '2026-09-15', true, 100, 100, '{"P": true}'),
  (7001, date '2026-09-22', true, 100, 100, '{"P": true}'),
  (7002, date '2026-09-01', true, 80, 80, '{"P": true}'),
  (7101, date '2026-09-23', true, 100, 100, '{"P": true}'),
  (7101, date '2026-09-30', true, 100, 100, '{"P": true}'),
  (7101, date '2026-10-07', true, 100, 100, '{"P": true}'),
  (7201, date '2026-09-01', true, 90, 90, '{"P": true}');

insert into public.produto_termos (produto_id, termo_id) values
  (7001, 'lab_a61'), (7002, 'lab_a61'), (7101, 'lab_a61');

-- As duas marcas coletando com volume em 08/10: 16 dias depois da troca, a
-- regra K1 (14 dias ausente com a marca coletando) já teria disparado.
insert into public.saude (data, fonte, marca_id, visitados, alertas) values
  (date '2026-10-08', 'varejo', 7, 360, null),
  (date '2026-10-08', 'varejo', 71, 100, null);
