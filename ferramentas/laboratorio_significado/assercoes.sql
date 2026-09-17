-- Asserções do laboratório de significado (A57/A58).
--
-- Cada bloco falha com mensagem própria. A ordem é a dos defeitos conhecidos:
-- amostra truncada, produto repetido, exemplo virando contagem, denominador da
-- data errada, pausa virando ausência, segmento contaminando segmento e
-- expressão do usuário virando padrão de busca.

-- 1. A janela inteira, não uma amostra de 120.
do $$
declare r jsonb; begin
  r := public.resumo_de_eventos('reposicao', 7, 6);
  assert (r->>'total_pecas')::int = 208,
    'total de pecas deveria ser 208 e veio ' || (r->>'total_pecas');
  assert (r->>'total_eventos')::int = 238,
    'total de eventos deveria ser 238 e veio ' || (r->>'total_eventos');
  assert (r->'marcas'->0->>'marca') = 'Grande',
    'a marca com mais pecas deveria abrir a lista';
  assert (r->'marcas'->0->>'pecas')::int = 200,
    'Grande deveria ter 200 pecas distintas e veio '
      || (r->'marcas'->0->>'pecas');
  raise notice 'ok 1  janela inteira: 208 pecas, 238 eventos, sem teto de 120';
end $$;

-- 2. Produto que voltou duas vezes conta uma vez; o evento extra conta.
do $$
declare g jsonb; begin
  g := public.resumo_de_eventos('reposicao', 7, 6)->'marcas'->0;
  assert (g->>'pecas')::int = 200 and (g->>'eventos')::int = 230,
    'Grande deveria ser 200 pecas em 230 eventos e veio '
      || (g->>'pecas') || '/' || (g->>'eventos');
  -- 10 produtos ja tinham voltado antes da janela.
  assert (g->>'pecas_repetidas')::int = 10,
    'repetidas deveria ser 10 e veio ' || (g->>'pecas_repetidas');
  raise notice 'ok 2  repeticao: produto distinto conta uma vez, evento conta sempre';
end $$;

-- 3. Exemplos são amostra e não mexem no total.
do $$
declare g jsonb; begin
  g := public.resumo_de_eventos('reposicao', 7, 6)->'marcas'->0;
  assert jsonb_array_length(g->'exemplos') = 6,
    'deveriam vir 6 exemplos e vieram ' || jsonb_array_length(g->'exemplos');
  assert (g->>'pecas')::int = 200,
    'a contagem nao pode seguir o teto de exemplos';
  g := public.resumo_de_eventos('reposicao', 7, 12)->'marcas'->0;
  assert jsonb_array_length(g->'exemplos') = 12 and (g->>'pecas')::int = 200,
    'dobrar os exemplos nao pode mudar a contagem';
  raise notice 'ok 3  exemplos: 6 e 12 exemplos, sempre 200 pecas';
end $$;

-- 4. O denominador é o sortimento OBSERVADO no fim da janela.
do $$
declare g jsonb; r jsonb; begin
  r := public.resumo_de_eventos('reposicao', 7, 6);
  g := r->'marcas'->0;
  assert (r->>'denominador_em')::date = current_date - 15,
    'denominador deveria ser datado no fim da janela e veio '
      || coalesce(r->>'denominador_em', 'nulo');
  -- Em D0 a Grande tinha 400 ofertaveis; o estado de hoje diz 500.
  assert (g->>'pecas_ofertadas')::int = 400,
    'denominador deveria ser 400 (observado) e veio '
      || coalesce(g->>'pecas_ofertadas', 'nulo');
  assert (g->>'por_mil_ofertadas')::numeric = 500.0,
    'taxa deveria ser 500,0 por mil e veio '
      || coalesce(g->>'por_mil_ofertadas', 'nulo');
  raise notice 'ok 4  denominador: 400 observados em D0, nao 500 de hoje';
end $$;

-- 5. Sem denominador daquele dia, a taxa se cala em vez de usar outro dia.
do $$
declare g jsonb; r jsonb; begin
  delete from public.sortimento_diario where data = current_date - 15;
  r := public.resumo_de_eventos('reposicao', 7, 6);
  g := r->'marcas'->0;
  assert r->>'denominador_em' is null,
    'sem linha do dia, denominador_em deveria ser nulo';
  assert g->>'pecas_ofertadas' is null and g->>'por_mil_ofertadas' is null,
    'sem denominador a taxa nao pode ser calculada';
  assert (g->>'pecas')::int = 200,
    'a contagem absoluta continua existindo sem denominador';
  -- devolve o estado anterior para os proximos blocos
  perform public.computar_sortimento_diario(current_date - 15);
  raise notice 'ok 5  ausencia de denominador e declarada, nao substituida';
end $$;

-- 6. A janela é explícita: um dia devolve um dia.
do $$
declare r jsonb; begin
  r := public.resumo_de_eventos('reposicao', 1, 6);
  assert (r->>'de')::date = current_date - 15
     and (r->>'ate')::date = current_date - 15,
    'janela de 1 dia deveria comecar e terminar no ultimo dia coletado';
  assert (r->>'dias_desde_o_fim')::int = 15,
    'a idade do dado deveria ser 15 dias e veio ' || (r->>'dias_desde_o_fim');
  -- 30 produtos repuseram no ultimo dia; 200 na semana.
  assert (r->>'total_pecas')::int < 208,
    'a janela de um dia nao pode devolver a semana inteira';
  raise notice 'ok 6  janela explicita, com idade declarada';
end $$;

-- 7. Coleta pausada devolve dado com idade, não ausência.
do $$
declare r jsonb; resumo jsonb; begin
  r := public.similares_da_peca(array['vestido', 'preto'], 5);
  resumo := r->'resumo';
  assert (resumo->>'n_similares')::int = 20,
    'similares deveria achar as 20 pecas do painel e veio '
      || (resumo->>'n_similares');
  assert (resumo->>'observado_em')::date = current_date - 15,
    'o resumo deveria declarar a data observada';
  assert (resumo->>'dias_desde_a_observacao')::int = 15,
    'o resumo deveria declarar 15 dias de idade e veio '
      || (resumo->>'dias_desde_a_observacao');
  assert (r->'pecas'->0->>'visto_em')::date = current_date - 15,
    'cada peca deveria carregar a data que a sustenta';
  raise notice 'ok 7  pausa de coleta: 20 similares com 15 dias declarados';
end $$;

-- 8. Segmento com data mais nova não reprova o outro.
do $$
declare resumo jsonb; begin
  -- As candidatas foram vistas em current_date - 5, dez dias depois do
  -- painel. Com uma ancora unica, o painel inteiro cairia.
  resumo := public.similares_da_peca(array['vestido', 'preto'], 5)->'resumo';
  assert (resumo->>'n_similares')::int = 20,
    'a ancora do catalogo candidato nao pode derrubar o painel medido';
  resumo := public.similares_da_peca(array['saia'], 5)->'resumo';
  assert (resumo->>'n_similares')::int = 5,
    'as candidatas continuam encontraveis pela propria data e veio '
      || (resumo->>'n_similares');
  raise notice 'ok 8  ancora por segmento: 20 do painel, 5 candidatas';
end $$;

-- 9. O link da loja sai do estado que o coletor escreve.
do $$
declare eventos jsonb; com_link int; begin
  eventos := public.eventos_recentes('reposicao', 50);
  select count(*) into com_link
  from jsonb_array_elements(eventos) e
  where e->>'url_da_peca' is not null;
  assert com_link = 50,
    'o link deveria vir dos 50 eventos e veio em ' || com_link
      || ' -- a coluna congelada de produtos esta 40 dias atras';
  raise notice 'ok 9  link da loja lido de estado_dos_produtos';
end $$;

-- 10. A expressão do usuário é dado, nunca padrão.
do $$
declare r jsonb; begin
  r := public.buscar_referencia_editorial('Napoleon Jacket', 5);
  assert (r->>'total')::int = 1,
    'a expressao exata deveria achar 1 materia (a masculina fica fora) e achou '
      || (r->>'total');
  assert (r->'materias'->0->>'veiculo') = 'Refinery29',
    'a materia deveria ser a do recorte feminino';

  r := public.buscar_referencia_editorial('napoleon', 5);
  assert (r->>'total')::int = 2,
    'busca sem caixa deveria achar 2 e achou ' || (r->>'total');

  r := public.buscar_referencia_editorial('50%_off', 5);
  assert (r->>'total')::int = 1,
    'com % e _ escapados, a busca deveria achar 1 e achou ' || (r->>'total');

  r := public.buscar_referencia_editorial('\', 5);
  assert (r->>'buscavel')::boolean = false and (r->>'total')::int = 0,
    'expressao curta nao e buscavel';

  r := public.buscar_referencia_editorial('napoleon', 999);
  assert jsonb_array_length(r->'materias') <= 10,
    'o limite deveria ser aparado em 10';
  raise notice 'ok 10 busca editorial: recorte, caixa, curinga, limite';
end $$;
