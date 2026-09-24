-- Asserções da A66: atributos da taxonomia na busca da leitura.

-- 65. O atributo pedido é exigido; o sinal continua filtrando por cima.
do $$
declare r jsonb; ids bigint[]; begin
  r := public.candidatas_da_leitura(array['lab_casaco'], array['lab_midi'],
                                    array['napoleao', 'militar'], array['verde militar']);
  select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) into ids
  from jsonb_array_elements(r->'pecas') x;
  assert ids = array[7302, 7304]::bigint[], 'atributo nao filtrou: ' || coalesce(ids::text, 'nenhuma');
  raise notice 'ok 65 so as pecas com o atributo midi da taxonomia';
end $$;

-- 66. Sem sinal de texto, categoria + atributo bastam; sem os dois, recusa.
do $$
declare r jsonb; begin
  r := public.candidatas_da_leitura(array['lab_casaco'], array['lab_midi'], '{}');
  assert (r->>'total')::int = 2, 'busca so pela taxonomia falhou: ' || r::text;
  begin
    perform public.candidatas_da_leitura(array['lab_casaco'], '{}', '{}');
    raise exception 'busca sem sinal e sem atributo foi aceita';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'ok 66 taxonomia sozinha basta; sem sinal nem atributo, recusa';
end $$;

-- 67. A assinatura da A64 saiu, e a nova so a chave de servico chama.
do $$
begin
  assert to_regprocedure('public.candidatas_da_leitura(text[], text[], text[], integer)') is null,
    'a versao da A64 continuou no banco';
  assert not has_function_privilege('anon', 'public.candidatas_da_leitura(text[], text[], text[], text[], integer)', 'execute'),
    'anon chama candidatas';
  assert has_function_privilege('service_role', 'public.candidatas_da_leitura(text[], text[], text[], text[], integer)', 'execute'),
    'a Edge Function nao chama candidatas';
  raise notice 'ok 67 uma assinatura so, e so a chave de servico';
end $$;
