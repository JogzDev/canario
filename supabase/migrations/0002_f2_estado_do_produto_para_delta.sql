-- B3 + gravação em lote: estado atual do produto na própria linha de produtos,
-- para o delta diário ser comparação direta (O(1)) sem varrer snapshots.
alter table produtos
  add column ultimo_preco_atual    numeric(10,2),
  add column ultimo_preco_original numeric(10,2),
  add column ultima_grade          jsonb,
  add column ultimo_snapshot_em    date;

comment on column produtos.ultima_grade is
  'Último estado conhecido da grade. O delta (B3) compara o coletado com isto; snapshot só quando muda ou no batimento semanal.';
