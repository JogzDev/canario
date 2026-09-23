-- Linha de base da A62: o "antes" é o código de produção, e o defeito existe.
--
-- Roda depois de `fixture_a62.sql` e das duas funções que o `rodar.mjs`
-- extrai das migrations (P0 e F4). As linhas que a P0 grava aqui FICAM: são a
-- semana que a A62 encontra ao entrar, com o estoque morto dentro.

-- 39. As duas funções instaladas são as de produção, medidas em 23/09/2026.
do $$
declare curva text; ordem text; begin
  select md5(prosrc) into curva from pg_proc
   where oid = 'public.computar_curva_tamanhos(integer)'::regprocedure;
  select md5(prosrc) into ordem from pg_proc
   where oid = 'public.ordem_do_tamanho(text)'::regprocedure;
  assert curva = '265552fa6d57794bf3a9f3f3dcdad6b9',
    'o antes da curva nao e o de producao: ' || curva;
  assert ordem = 'b03adde14ef50d47ea2c31afd2fb0fb7',
    'a ordem da grade nao e a de producao: ' || ordem;
  raise notice 'ok 39 antes: curva (P0) e ordem da grade (F4) com o md5 de producao';
end $$;

-- 40. A P0 conta toda peça que já existiu: as oito do segmento ativo, as duas
--     do pausado e o termo que só tem estoque morto.
do $$
declare ativo integer; pausado integer; morto integer; begin
  perform public.computar_curva_tamanhos();
  select grades into ativo from pg_temp.faixas_a62('lab_curva');
  select grades into pausado from pg_temp.faixas_a62('lab_curva_pausado');
  select count(*) into morto from public.curva_tamanhos
   where termo_id = 'lab_curva_morto' and semana = pg_temp.semana_a62();
  assert ativo = 8, 'a P0 deveria contar as 8 pecas e contou ' || coalesce(ativo, 0);
  assert pausado = 2, 'a P0 deveria contar as 2 pausadas e contou ' || coalesce(pausado, 0);
  assert morto > 0, 'a P0 deveria dar curva ao termo so de estoque morto';
  raise notice 'ok 40 antes: a P0 conta 8 de 8 pecas, inclusive a morta, a esgotada ha meses e a aposentada';
end $$;
