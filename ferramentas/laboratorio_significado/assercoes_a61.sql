-- Asserções da A61: troca de catálogo sem inventar eventos.
--
-- Roda depois da A60 e de `fixture_a61.sql`. Cada caso que escreve desfaz o
-- que fez com o erro de controle LAB01; uma asserção que falha levanta outro
-- código e derruba o laboratório.

-- 34. A troca da Amaro foi registrada e só o catálogo antigo aposentou.
do $$
declare aposentados bigint[]; data_troca date;
begin
  select array_agg(produto_id order by produto_id), max(aposentado_em)
    into aposentados, data_troca
    from public.produtos_de_catalogo_aposentado;
  assert aposentados = array[7001, 7002]::bigint[],
    'aposentados errados: ' || coalesce(aposentados::text, 'nenhum');
  assert data_troca = date '2026-09-23', 'data da troca errada: ' || data_troca;
  raise notice 'ok 34 so o que nao foi visto desde 23/09 aposentou; o catalogo novo e a outra loja ficaram';
end $$;

-- 35. Mudar de endereço não é sair de linha; sumir de verdade continua sendo.
do $$
declare da_amaro integer; do_controle integer; begin
  begin
    execute 'set local role service_role';
    perform public.computar_eventos();
    execute 'reset role';
    select count(*) into da_amaro from public.eventos e
      join public.produtos p on p.id = e.produto_id
     where p.marca_id = 7 and e.tipo = 'saida_de_linha';
    select count(*) into do_controle from public.eventos e
      join public.produtos p on p.id = e.produto_id
     where p.marca_id = 71 and e.tipo = 'saida_de_linha';
    assert da_amaro = 0,
      'catalogo aposentado virou saida de linha: ' || da_amaro;
    assert do_controle = 1,
      'a regra K1 deixou de valer para quem saiu de verdade: ' || do_controle;
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 35 a troca nao gera saida de linha; a loja de controle continua gerando';
end $$;

-- 36. O denominador não conta a marca duas vezes depois da troca.
do $$
declare na_terca integer; na_quarta integer; begin
  select pecas_ofertadas into na_terca
    from public.sortimento_observado(date '2026-09-22') where marca_id = 7;
  select pecas_ofertadas into na_quarta
    from public.sortimento_observado(date '2026-09-23') where marca_id = 7;
  assert na_terca = 1, 'na terca o catalogo antigo era o sortimento: ' || coalesce(na_terca, 0);
  assert na_quarta = 1,
    'na quarta a Amaro contou os dois catalogos: ' || coalesce(na_quarta, 0);
  raise notice 'ok 36 terca conta o antigo, quarta conta so o novo';
end $$;

-- 37. Na semana da troca a série vê um catálogo só; a semana anterior fica igual.
do $$
declare da_troca integer; anterior integer; begin
  begin
    perform public.computar_serie_varejo();
    select n_amostra into da_troca from public.series_semanais
     where termo_id = 'lab_a61' and fonte = 'varejo' and semana = date '2026-09-21';
    select n_amostra into anterior from public.series_semanais
     where termo_id = 'lab_a61' and fonte = 'varejo' and semana = date '2026-09-14';
    assert da_troca = 1,
      'semana da troca pesou a Amaro em dobro: ' || coalesce(da_troca, 0);
    assert anterior = 1,
      'a semana anterior perdeu o catalogo que era o real: ' || coalesce(anterior, 0);
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 37 semana de 21/09 so com o catalogo novo; 14/09 intacta';
end $$;

-- 38. As restrições aceitam a Nuvemshop e continuam recusando o resto; a
--     tabela e a view não vazam para o app.
do $$
begin
  begin
    update public.marcas set plataforma = 'nuvemshop', status_teste = 'nuvemshop'
     where id = 7;
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  begin
    update public.marcas set plataforma = 'magento' where id = 7;
    raise exception 'plataforma desconhecida foi aceita';
  exception when check_violation then null;
  end;
  assert not has_table_privilege('anon', 'public.trocas_de_catalogo', 'select'),
    'anon le trocas_de_catalogo';
  assert not has_table_privilege('anon', 'public.produtos_de_catalogo_aposentado', 'select'),
    'anon le a view de aposentados';
  assert has_table_privilege('service_role', 'public.produtos_de_catalogo_aposentado', 'select'),
    'o motor nao le a view de aposentados';
  raise notice 'ok 38 nuvemshop aceita, plataforma desconhecida recusada, nada exposto ao app';
end $$;
