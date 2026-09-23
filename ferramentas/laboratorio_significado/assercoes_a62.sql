-- Asserções da A62: a curva de tamanhos só com o que está na vitrine.
--
-- Roda depois da A62, sobre a semana que a P0 deixou em `linha_de_base_a62`.
-- O primeiro bloco recalcula a curva como o motor faz (papel de serviço, sem
-- argumento) e o resultado FICA para os blocos seguintes. O `rodar.mjs`
-- também roda este arquivo contra cada mutação da A62, dentro de uma
-- transação desfeita no fim: toda mutação precisa reprovar alguma asserção.
--
-- Contas esperadas no segmento `lab_curva`, que entra com 8201, 8204, 8205 e
-- 8208 (cinco tamanhos cada):
--   pares 20; indisponíveis 7 (G da 8201, M da 8204, os cinco da 8205)
--   em risco 19 (5 + 4 + 5 + 5; o M da 8204 já começou indisponível)
--   quebrou 6 (G da 8201 e os cinco da 8205)

-- 41. Só entra o que está na vitrine.
do $$
declare f record; begin
  execute 'set local role service_role';
  perform public.computar_curva_tamanhos();
  execute 'reset role';
  select * into f from pg_temp.faixas_a62('lab_curva');
  -- 4 = ativa, vista há 7 dias, esgotada na janela, catálogo novo. Uma a mais
  -- é a morta (sem janela), a de 8 dias (janela frouxa), a esgotada há meses
  -- (vitrine de esgotados) ou a aposentada (sem a A61).
  assert f.grades = 4,
    'a base deveria ter 4 pecas e tem ' || coalesce(f.grades, 0);
  raise notice 'ok 41 a base tem as 4 pecas da vitrine: morta, 8 dias, esgotada ha meses e aposentada ficaram fora';
end $$;

-- 42. A peça que esgotou dentro da janela fica: ela é a quebra.
do $$
declare f record; begin
  select * into f from pg_temp.faixas_a62('lab_curva');
  assert f.em_risco = 19 and f.quebrou = 6,
    'a manchete perdeu quebra: em risco ' || coalesce(f.em_risco, 0)
      || ', quebrou ' || coalesce(f.quebrou, 0) || ' (esperado 19 e 6)';
  raise notice 'ok 42 taxa de quebra 6/19: quem esgotou na janela continua na conta';
end $$;

-- 43. A foto de hoje é a da vitrine, também por faixa.
do $$
declare f record; maiores numeric; begin
  select * into f from pg_temp.faixas_a62('lab_curva');
  select share_indisponivel into maiores from public.curva_tamanhos
   where segmento = 'lab_curva' and termo_id is null and rotulo is null
     and faixa = 'maiores' and semana = pg_temp.semana_a62();
  assert f.pares = 20 and f.indisponivel = 7,
    'foto de hoje errada: ' || coalesce(f.indisponivel, 0) || ' de '
      || coalesce(f.pares, 0) || ' (esperado 7 de 20)';
  -- G e GG de 8201, 8204, 8205 e 8208: G da 8201 e os dois da 8205.
  assert maiores = 37.50,
    'faixa dos maiores deveria ter 37,50% indisponivel e tem ' || coalesce(maiores::text, 'nulo');
  raise notice 'ok 43 share indisponivel 7/20, e 3/8 na faixa dos maiores';
end $$;

-- 44. A âncora é o último dia observado de CADA segmento, e a idade viaja.
do $$
declare f record; r record; ancora_ativo date; ancora_pausado date; begin
  select * into r from relogio_a62;
  select * into f from pg_temp.faixas_a62('lab_curva_pausado');
  -- Pausa não é ausência: a peça vista no último dia do segmento fica, mesmo
  -- vinte dias atrás do calendário e do outro segmento; a de oito dias antes
  -- dela sai.
  assert f.grades = 1 and f.pares = 5 and f.indisponivel = 1,
    'segmento pausado errado: ' || coalesce(f.grades, 0) || ' pecas, '
      || coalesce(f.indisponivel, 0) || ' de ' || coalesce(f.pares, 0);
  select distinct (meta->>'base_observada_em')::date into ancora_ativo
    from public.curva_tamanhos
   where segmento = 'lab_curva' and semana = pg_temp.semana_a62();
  select distinct (meta->>'base_observada_em')::date into ancora_pausado
    from public.curva_tamanhos
   where segmento = 'lab_curva_pausado' and semana = pg_temp.semana_a62();
  assert ancora_ativo = r.h and ancora_pausado = r.p,
    'a idade da base nao viaja com a linha: ' || coalesce(ancora_ativo::text, 'nulo')
      || ' e ' || coalesce(ancora_pausado::text, 'nulo');
  raise notice 'ok 44 ancora por segmento: o pausado fica com a propria data e a declara';
end $$;

-- 45. A semana alvo é substituída inteira; a semana anterior não é tocada.
do $$
declare morto integer; vivo record; antiga record; begin
  select count(*) into morto from public.curva_tamanhos
   where termo_id = 'lab_curva_morto' and semana = pg_temp.semana_a62();
  select * into vivo from pg_temp.faixas_a62('lab_curva', 'lab_curva_vivo');
  select * into antiga from public.curva_tamanhos
   where segmento = 'lab_curva' and termo_id = 'lab_curva_morto' and rotulo is null
     and faixa = 'meio' and semana = pg_temp.semana_a62() - 7;
  assert morto = 0,
    'o termo so de estoque morto ficou com ' || morto || ' linhas na semana';
  assert vivo.grades = 1,
    'o termo com uma peca viva deveria ter 1 grade e tem ' || coalesce(vivo.grades, 0);
  assert antiga.n_grades = 99 and antiga.meta = '{"publicada": true}'::jsonb,
    'a semana ja publicada foi reescrita ou apagada';
  raise notice 'ok 45 semana alvo refeita inteira; a anterior ficou como foi publicada';
end $$;

-- 46. A curva continua interna: o app lê a tabela, não roda a função.
do $$
begin
  begin
    execute 'set local role anon';
    perform public.computar_curva_tamanhos();
    execute 'reset role';
    raise exception 'anon executou computar_curva_tamanhos';
  exception when insufficient_privilege then
    execute 'reset role';
  end;
  assert not has_function_privilege('authenticated',
    'public.computar_curva_tamanhos(integer)', 'execute'),
    'authenticated executa computar_curva_tamanhos';
  raise notice 'ok 46 anon recebe 42501 na curva; so o servico a executa';
end $$;
