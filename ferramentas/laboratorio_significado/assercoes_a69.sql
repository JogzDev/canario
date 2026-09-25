-- 94. Taxa nao ultrapassa 100% e usa a mesma janela do numerador.
do $$
declare r jsonb; m jsonb; begin
  select public.resumo_de_eventos('remarcacao', 7, 12, current_date - 15) into r;
  select v into m from jsonb_array_elements(r->'marcas') v
   where v->>'marca' = 'Lab taxa da semana';
  assert m is not null, 'A69: marca de teste ausente';
  assert (m->>'pecas')::int = 8 and (m->>'eventos')::int = 9,
    'A69: numerador duplicou produto ou perdeu evento: ' || m::text;
  assert (m->>'pecas_ofertadas')::int = 4
     and (m->>'por_mil_ofertadas')::numeric = 2000,
    'A69: o caso antigo de 200%% nao foi reproduzido: ' || m::text;
  assert (m->>'pecas_observadas')::int = 10
     and (m->>'por_mil_observadas')::numeric = 800,
    'A69: oito de dez observadas devem dar 80%%: ' || m::text;
  raise notice 'ok 94 oito de dez observadas: 80%% em vez de 200%% do ultimo dia';
end $$;

-- 95. A populacao observada e identica para tipos de movimento distintos.
do $$
declare r jsonb; m jsonb; begin
  select public.resumo_de_eventos('reposicao', 7, 12, current_date - 15) into r;
  select v into m from jsonb_array_elements(r->'marcas') v
   where v->>'marca' = 'Lab taxa da semana';
  assert (m->>'pecas_observadas')::int = 10
     and (m->>'por_mil_observadas')::numeric = 100,
    'A69: tipos receberam denominadores diferentes: ' || m::text;
  raise notice 'ok 95 reposicao e remarcacao compartilham o mesmo denominador semanal';
end $$;

-- 96. Evento isolado sem snapshots nao finge ter cobertura do sortimento.
do $$
declare r jsonb; m jsonb; begin
  select public.resumo_de_eventos('remarcacao', 7, 12, current_date - 15) into r;
  select v into m from jsonb_array_elements(r->'marcas') v
   where v->>'marca' = 'Lab sem fotos';
  assert m is not null and m->>'pecas_observadas' is null
     and m->>'por_mil_observadas' is null,
    'A69: evento sem snapshot ganhou denominador ficticio: ' || m::text;
  raise notice 'ok 96 sem snapshot no periodo, taxa nula';
end $$;
