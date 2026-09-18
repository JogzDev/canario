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
  assert (r->>'total_eventos')::int = 240,
    'total de eventos deveria ser 240 e veio ' || (r->>'total_eventos');
  assert (r->'marcas'->0->>'marca') = 'Grande',
    'a marca com mais pecas deveria abrir a lista';
  assert (r->'marcas'->0->>'pecas')::int = 200,
    'Grande deveria ter 200 pecas distintas e veio '
      || (r->'marcas'->0->>'pecas');
  raise notice 'ok 1  janela inteira: 208 pecas, 240 eventos, sem teto de 120';
end $$;

-- 2. Produto que voltou duas vezes conta uma vez; o evento extra conta.
do $$
declare g jsonb; begin
  g := public.resumo_de_eventos('reposicao', 7, 6)->'marcas'->0;
  assert (g->>'pecas')::int = 200 and (g->>'eventos')::int = 232,
    'Grande deveria ser 200 pecas em 232 eventos e veio '
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

  -- Termo frequente: o total conta a populacao, a lista e amostra. Sao as
  -- duas coisas que a capa confundia.
  r := public.buscar_referencia_editorial('promo', 1);
  assert (r->>'total')::int = 2,
    'o total deveria contar as 2 materias e veio ' || (r->>'total');
  assert jsonb_array_length(r->'materias') = 1,
    'a lista deveria respeitar o limite de 1 e veio '
      || jsonb_array_length(r->'materias');

  -- Barra DENTRO de uma expressao valida: o caso que o teste curto nao
  -- alcancava. Sem escapar a barra, `ilike` a consome como escape e a busca
  -- passa a procurar outra coisa.
  r := public.buscar_referencia_editorial('barra \ no', 5);
  assert (r->>'total')::int = 1,
    'barra escapada deveria achar 1 e achou ' || (r->>'total');
  assert (r->'materias'->0->>'url') = 'https://ex.example/curinga',
    'a materia achada deveria ser a que tem a barra no titulo';

  -- Controle negativo: `_` do usuario e sublinhado, nao "qualquer caractere".
  r := public.buscar_referencia_editorial('barra _ no', 5);
  assert (r->>'total')::int = 0,
    'o sublinhado nao pode voltar a ser curinga e achou ' || (r->>'total');
  raise notice 'ok 10 busca editorial: recorte, caixa, curinga, limite, barra';
end $$;

-- 11. Snapshot antigo nao conta como oferta de hoje (P17).
do $$
declare n int; begin
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 15 and marca_id = 1;
  -- 3 pecas abandonadas ha 30 dias continuam `ofertavel` no estado. Sob a
  -- regra antiga (`s.data <= alvo`, sem piso) elas entrariam e o denominador
  -- seria 403.
  assert n = 400,
    'o denominador de D0 deveria ignorar o catalogo morto e veio ' || n;
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 30 and marca_id = 1;
  assert n = 3,
    'no dia em que foram vistas, as 3 contam; vieram ' || coalesce(n::text, 'nulo');
  raise notice 'ok 11 snapshot antigo: 400 em D0, 3 no dia proprio';
end $$;

-- 12. Exemplo e vitrine: uma peca, um cartao.
do $$
declare g jsonb; distintas int; begin
  g := public.resumo_de_eventos('reposicao', 7, 6)->'marcas'->0;
  assert jsonb_array_length(g->'exemplos') = 6,
    'deveriam vir 6 exemplos e vieram ' || jsonb_array_length(g->'exemplos');
  select count(distinct e->>'peca') into distintas
  from jsonb_array_elements(g->'exemplos') e;
  assert distintas = 6,
    'as 2 pecas que repuseram tres vezes ocupariam 4 cartoes; distintas: '
      || distintas;
  raise notice 'ok 12 exemplos: 6 cartoes, 6 pecas diferentes';
end $$;

-- 13. Recomputar corrige para baixo: grupo que zera sai da tabela.
do $$
declare tocadas int; existe boolean; n int; begin
  update public.snapshots set ofertavel = false
   where data = current_date - 15 and produto_id between 1001 and 1010;
  tocadas := public.computar_sortimento_diario(current_date - 15);
  select exists (select 1 from public.sortimento_diario
                  where data = current_date - 15 and marca_id = 2) into existe;
  assert not existe,
    'a marca que zerou deveria sair da tabela, nao virar denominador fantasma';
  assert tocadas = 1,
    'a recomputacao deveria declarar 1 linha tocada e declarou ' || tocadas;

  update public.snapshots set ofertavel = true
   where data = current_date - 15 and produto_id between 1001 and 1010;
  perform public.computar_sortimento_diario(current_date - 15);
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 15 and marca_id = 2;
  assert n = 10, 'a marca deveria voltar com 10 e voltou com '
    || coalesce(n::text, 'nulo');
  raise notice 'ok 13 grupo que zera sai; volta quando volta a existir';
end $$;

-- 14. Reexecutar o mesmo dia nao escreve nada (P11).
do $$
declare tocadas int; begin
  tocadas := public.computar_sortimento_diario(current_date - 15);
  assert tocadas = 0,
    'reexecutar um dia estavel deveria escrever 0 linhas e escreveu ' || tocadas;
  raise notice 'ok 14 reexecucao: 0 linhas escritas';
end $$;

-- 15. Quem chama e a chave de servico; `anon` nao alcanca.
do $$
declare tocadas int; begin
  execute 'set local role service_role';
  tocadas := public.computar_sortimento_diario(current_date - 15);
  execute 'reset role';
  assert tocadas = 0,
    'service_role deveria executar a reconstrucao e devolveu ' || tocadas;

  begin
    execute 'set local role anon';
    perform public.computar_sortimento_diario(current_date - 15);
    execute 'reset role';
    assert false, 'anon nao pode reconstruir o denominador';
  exception when insufficient_privilege then
    execute 'reset role';
  end;
  raise notice 'ok 15 service_role executa; anon recebe 42501';
end $$;

-- 16. O motor grava o denominador do dia e so entao poda o cru.
do $$
declare r jsonb; n int; fora int; begin
  select count(*) into fora from public.snapshots
   where data < current_date - 21;
  assert fora = 3, 'o laboratorio deveria ter 3 snapshots fora da retencao e tem '
    || fora;

  -- Apaga o denominador do dia mais novo para ver o motor grava-lo.
  delete from public.sortimento_diario where data = current_date - 5;

  execute 'set local role service_role';
  r := public.computar_motor();
  execute 'reset role';

  assert (r->>'computar_sortimento_diario')::int = 1,
    'o motor deveria gravar 1 linha de denominador e gravou '
      || coalesce(r->>'computar_sortimento_diario', 'nulo');
  assert (r->>'snapshots_removidos')::int = 3,
    'o motor deveria podar os 3 snapshots fora da retencao e podou '
      || coalesce(r->>'snapshots_removidos', 'nulo');
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 5 and segmento = 'catalogo_candidato_br';
  assert n = 5,
    'o denominador do dia mais novo deveria existir depois do motor e veio '
      || coalesce(n::text, 'nulo');

  -- Dia ja podado nao e reconstruivel: recomputar nao pode apagar o historico.
  assert public.computar_sortimento_diario(current_date - 30) = 0,
    'recomputar um dia sem cru deveria sair sem tocar em nada';
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 30 and marca_id = 1;
  assert n = 3,
    'o denominador de um dia podado foi apagado por uma recomputacao';
  raise notice 'ok 16 motor: denominador gravado, cru podado, historico intacto';
end $$;

-- 17. Coleta recente sem eventos devolve zero na janela, nao a semana antiga.
do $$
declare r jsonb; begin
  update public.estado_dos_produtos ep set ultimo_avistamento_em = current_date
  from public.produtos p
  where p.id = ep.produto_id
    and p.segmento = 'feminino_casual_br'
    and ep.ultimo_avistamento_em = current_date - 15;

  r := public.resumo_de_eventos('reposicao', 7);
  assert (r->>'ate')::date = current_date
     and (r->>'de')::date = current_date - 6,
    'a janela deveria seguir a observacao do painel e veio '
      || (r->>'de') || '..' || (r->>'ate');
  assert (r->>'total_pecas')::int = 0 and (r->>'total_eventos')::int = 0,
    'sem evento na janela, a resposta e zero -- nao a semana do ultimo evento';
  assert (r->>'dias_desde_o_fim')::int = 0,
    'a idade do dado deveria ser 0 e veio ' || (r->>'dias_desde_o_fim');

  -- Janela COMUM: um tipo que nunca teve evento nenhum responde a mesma
  -- janela, em vez de nao responder.
  r := public.resumo_de_eventos('saida_de_linha', 7);
  assert (r->>'ate')::date = current_date and (r->>'total_pecas')::int = 0,
    'os tres tipos deveriam compartilhar a janela do painel';

  -- O passado continua consultavel, mas so quando alguem pede por ele.
  r := public.resumo_de_eventos('reposicao', 7, 6, current_date - 15);
  assert (r->>'total_pecas')::int = 208,
    'com ate explicito, a janela antiga deveria voltar com 208 e veio '
      || (r->>'total_pecas');

  update public.estado_dos_produtos ep set ultimo_avistamento_em = current_date - 15
  from public.produtos p
  where p.id = ep.produto_id
    and p.segmento = 'feminino_casual_br'
    and ep.ultimo_avistamento_em = current_date;
  raise notice 'ok 17 coleta recente sem eventos: zero na janela comum';
end $$;

-- 18. Noite vermelha nao deixa buraco: o motor alcanca o dia que faltou.
do $$
declare tocadas int; n int; begin
  delete from public.sortimento_diario where data = current_date - 15;
  -- Sem argumento: o dia mais novo e todo dia observado sem linha.
  tocadas := public.computar_sortimento_diario();
  assert tocadas = 2,
    'deveriam voltar as 2 linhas do dia que faltava e voltaram ' || tocadas;
  select pecas_ofertadas into n from public.sortimento_diario
   where data = current_date - 15 and marca_id = 1;
  assert n = 400, 'o dia recuperado deveria ter 400 e veio '
    || coalesce(n::text, 'nulo');
  assert public.computar_sortimento_diario() = 0,
    'com tudo em dia, a chamada sem argumento nao escreve nada';
  raise notice 'ok 18 dia que faltou e reconstruido antes da poda alcanca-lo';
end $$;
