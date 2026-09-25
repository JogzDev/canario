-- Asserções da A68: a curva mede a janela que observou.
--
-- O primeiro bloco recalcula a curva como o motor faz (papel de serviço, sem
-- argumento) e o resultado FICA para os blocos seguintes. O `rodar.mjs`
-- também roda este arquivo contra cada mutação da A68, dentro de uma
-- transação desfeita no fim: toda mutação precisa reprovar alguma asserção.
-- As contas esperadas estão em `fixture_a68.sql`.

-- 80. O estado do início é a última foto até o primeiro dia observado.
do $$
declare f record; begin
  execute 'set local role service_role';
  perform public.computar_curva_tamanhos();
  execute 'reset role';
  select * into f from pg_temp.faixas_a62('lab_janela');
  -- 9101 esgotou o G em H-2. A foto de antes é de H-8, que pode cair fora da
  -- janela nominal; a regra nova não depende disso.
  assert f.quebrou = 1,
    'a quebra do G no meio da janela sumiu: ' || coalesce(f.quebrou, 0) || ' (esperado 1)';
  raise notice 'ok 80 o G que esgotou no meio da janela conta: o inicio e a ultima foto ate o primeiro dia observado';
end $$;

-- 81. Só entra em risco quem estava no início, visto e com foto recente.
do $$
declare f record; begin
  select * into f from pg_temp.faixas_a62('lab_janela');
  -- 5 da 9101 + 4 da 9107. Uma a mais é a 9102 (foto de sete dias antes do
  -- início), a 9103 (nova), a 9104 (vista antes do início), ou o M da 9107
  -- (esgotou no próprio dia do início, antes da janela contar).
  assert f.grades = 5 and f.em_risco = 9,
    'em risco errado: ' || coalesce(f.em_risco, 0) || ' em ' || coalesce(f.grades, 0)
      || ' pecas (esperado 9 em 5)';
  raise notice 'ok 81 em risco 9: foto velha, peca nova, peca sumida antes do inicio e tamanho ja esgotado no inicio ficam fora';
end $$;

-- 82. Marca com um dia só de coleta não tem janela: nada dela entra em risco.
do $$
declare f record; j jsonb; begin
  select * into f from pg_temp.faixas_a62('lab_janela_um_dia');
  select pg_temp.janela_a68('lab_janela_um_dia') into j;
  -- É o catálogo candidato em 21/09: a peça está na base (a foto de hoje
  -- vale), mas com uma coleta não há o que comparar.
  assert f.grades = 1 and f.em_risco = 0 and f.quebrou = 0,
    'marca de uma coleta so entrou na taxa: ' || coalesce(f.em_risco, 0) || ' em risco, '
      || coalesce(f.quebrou, 0) || ' quebras';
  assert j is null or j = 'null'::jsonb,
    'segmento sem janela declarou uma: ' || j::text;
  raise notice 'ok 82 marca com uma coleta so: fica na base, fora da taxa, sem janela declarada';
end $$;

-- 83. Dia adiado, truncado ou parcial não é observação.
do $$
declare f record; j jsonb; r record; begin
  select * into r from relogio_a62;
  select * into f from pg_temp.faixas_a62('lab_janela_parcial');
  select pg_temp.janela_a68('lab_janela_parcial') into j;
  assert f.em_risco = 5 and f.quebrou = 0,
    'dia nao saudavel contou como observado: ' || coalesce(f.quebrou, 0)
      || ' quebras em ' || coalesce(f.em_risco, 0) || ' (esperado 0 em 5)';
  assert (j->>'fim')::date = r.h - 3,
    'a janela do segmento parcial deveria terminar em H-3 e termina em ' || coalesce(j->>'fim', 'nulo');
  raise notice 'ok 83 adiado, truncado e parcial nao estendem a janela: ela termina na ultima coleta saudavel';
end $$;

-- 84. A janela observada viaja com a linha, igual em todo o segmento.
do $$
declare j jsonb; n integer; r record; begin
  select * into r from relogio_a62;
  select count(distinct meta->'janela_observada') into n
    from public.curva_tamanhos
   where segmento = 'lab_janela' and semana = pg_temp.semana_a62();
  select pg_temp.janela_a68('lab_janela') into j;
  assert n = 1, 'o segmento declarou ' || n || ' janelas diferentes';
  assert (j->>'inicio')::date = r.h - 5 and (j->>'fim')::date = r.h
     and (j->>'dias')::int = 5 and (j->>'marcas')::int = 1,
    'janela declarada errada: ' || coalesce(j::text, 'nula')
      || ' (esperado H-5..H, 5 dias, 1 marca)';
  raise notice 'ok 84 janela observada em meta: inicio, fim, dias e marcas da coleta real, nao os 14 nominais';
end $$;

-- 85. As semanas já publicadas continuam como foram publicadas.
do $$
declare antiga record; begin
  select * into antiga from public.curva_tamanhos
   where segmento = 'lab_curva' and termo_id = 'lab_curva_morto' and rotulo is null
     and faixa = 'meio' and semana = pg_temp.semana_a62() - 7;
  assert antiga.n_grades = 99 and antiga.meta = '{"publicada": true}'::jsonb,
    'a A68 reescreveu uma semana ja publicada';
  raise notice 'ok 85 semana publicada intocada: a janela nova vale da semana corrente em diante';
end $$;
