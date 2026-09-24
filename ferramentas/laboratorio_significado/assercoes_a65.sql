-- Asserções da A65: estreia de catálogo trocado não é novidade.

-- 64. Só o lançamento de verdade conta; o resto da leitura segue igual.
do $$
declare r jsonb; f jsonb; begin
  r := public.fatos_da_leitura(array[7301, 7309, 7310]::bigint[]);
  select jsonb_object_agg(x->>'id', x) into f from jsonb_array_elements(r->'fatos') x;
  assert (f->'novidades_30d'->'provas') = '[7301, 7310]'::jsonb,
    'estreia de catalogo contou como novidade: ' || (f->'novidades_30d')::text;
  assert (f->'total'->>'pecas')::int = 3, 'a estreia saiu do total, e so devia sair das novidades';
  raise notice 'ok 64 estreia de catalogo trocado nao e novidade; lancamento depois dela e';
end $$;
