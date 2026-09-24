-- Asserções da A64: candidatas e fatos da leitura específica.

-- 60. Categoria + sinais + veto: a napoleão aparece, a cor verde militar não.
do $$
declare r jsonb; ids bigint[]; begin
  r := public.candidatas_da_leitura(array['lab_casaco'], array['Napoleão', 'abotoamento duplo', 'militar'],
                                    array['verde militar']);
  select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) into ids
  from jsonb_array_elements(r->'pecas') x;
  assert ids = array[7301, 7302, 7304, 7308]::bigint[], 'candidatas erradas: ' || coalesce(ids::text, 'nenhuma');
  assert (r->>'total')::int = 4, 'total errado: ' || (r->>'total');
  -- Quem casa dois sinais vem primeiro.
  assert (r->'pecas'->0->>'id')::bigint = 7302, 'a peca com dois sinais nao veio na frente';
  raise notice 'ok 60 napoleao entra, verde militar sai, calca e peca velha e esgotada ficam fora';
end $$;

-- 61. Sinal e texto, nunca padrao: `%` sozinho nao casa tudo, e `50%_off`
--     casa so o titulo que tem isso escrito.
do $$
declare r jsonb; begin
  begin
    perform public.candidatas_da_leitura(array['lab_casaco'], array['%%', '_']);
    raise exception 'sinal curto demais foi aceito';
  exception when sqlstate '22023' then null;
  end;
  r := public.candidatas_da_leitura(array['lab_casaco'], array['50%_off']);
  assert (r->>'total')::int = 1 and (r->'pecas'->0->>'id')::bigint = 7308,
    'o % do sinal virou coringa: ' || r::text;
  r := public.candidatas_da_leitura(array['lab_casaco'], array['jaqueta%']);
  assert (r->>'total')::int = 0, 'jaqueta% casou como padrao';
  raise notice 'ok 61 sinal com %% e _ e literal; sinal curto demais e recusado';
end $$;

-- 62. Fatos: so contam pecas ativas, e cada numero traz as provas.
do $$
declare r jsonb; f jsonb; begin
  r := public.fatos_da_leitura(array[7301, 7302, 7304, 7306, 7307]::bigint[], 250);
  select jsonb_object_agg(x->>'id', x) into f from jsonb_array_elements(r->'fatos') x;
  assert (f->'total'->>'pecas')::int = 3, 'peca velha ou esgotada entrou: ' || (f->'total')::text;
  assert (f->'preco'->>'minimo')::numeric = 180 and (f->'preco'->>'maximo')::numeric = 300
         and (f->'preco'->>'mediana')::numeric = 240, 'preco errado: ' || (f->'preco')::text;
  assert (f->'remarcadas'->>'pecas')::int = 1 and (f->'remarcadas'->>'de_cada_100')::int = 33
         and (f->'remarcadas'->>'desconto_mediano_pct')::int = 20,
    'remarcadas erradas: ' || (f->'remarcadas')::text;
  assert (f->'reposicoes_30d'->>'pecas')::int = 1 and (f->'reposicoes_30d'->'provas') = '[7301]'::jsonb,
    'reposicao da janela errada: ' || (f->'reposicoes_30d')::text;
  assert (f->'remarcacoes_30d'->>'pecas')::int = 0, 'evento fora da janela de 30 dias contou';
  assert (f->'novidades_30d'->'provas') = '[7301]'::jsonb, 'novidade errada';
  assert (f->'grade'->>'com_tamanho_esgotado')::int = 1, 'grade errada';
  assert (f->'posicao_do_preco'->>'mais_baratas')::int = 2 and (f->'posicao_do_preco'->>'mais_caras')::int = 1,
    'posicao do preco errada: ' || (f->'posicao_do_preco')::text;
  raise notice 'ok 62 fatos so com pecas ativas, cada um com as provas';
end $$;

-- 63. So a chave de servico chama.
do $$
begin
  assert not has_function_privilege('anon', 'public.candidatas_da_leitura(text[], text[], text[], integer)', 'execute'),
    'anon chama candidatas';
  assert not has_function_privilege('authenticated', 'public.fatos_da_leitura(bigint[], numeric)', 'execute'),
    'authenticated chama fatos';
  assert has_function_privilege('service_role', 'public.fatos_da_leitura(bigint[], numeric)', 'execute'),
    'a Edge Function nao chama fatos';
  raise notice 'ok 63 so a chave de servico chama a leitura';
end $$;
