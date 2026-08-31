-- A48 — os seis motivos de estampa saem da taxonomia.
--
-- POR QUE
-- =======
-- A A31 criou `motivo_estampa` com seis frutas: tomate, cereja, morango,
-- banana, abacaxi e melancia. A ideia era boa e o caso de uso era real (achar
-- a estampa de tomate da Farm em outra marca). O problema é que seis frutas
-- não são uma dimensão: são uma amostra arbitrária dela.
--
-- Medido na produção em 26/08/2026, chamando `similares_da_peca` com cada
-- motivo isolado:
--
--   cereja    24 peças, 9 marcas      tomate     12 peças, 3 marcas
--   banana    24 peças, 2 marcas      abacaxi     5 peças, 2 marcas
--   morango   22 peças, 3 marcas      melancia    0 peças, 0 marcas
--
-- Melancia é um termo aprovado que nunca casou uma peça. E o que falta é maior
-- que o que existe: não há azeitona, abacate, limão, sardinha, coração,
-- estrela nem borboleta — e as três últimas estão nomeadas dentro do
-- `palavras_en` do próprio `conversacional`, que é o guarda-chuva. Fazer
-- direito seria vocabulário aberto de motivos, com "outras frutas", legumes e
-- bichos desenhados; isso é projeto de virada de temporada, não seis linhas.
--
-- A decisão do JP em 26/08 foi "ou faz direito e completo ou não faz". Isto é
-- o "não faz".
--
-- POR QUE `reprovado` E NÃO `delete`
-- ==================================
-- Porque é o mecanismo que este projeto já tem, e ele é completo: a regra 4
-- diz que **o motor só usa `status = 'aprovado'`**, e isso é respeitado em 19
-- migrations, no coletor e no app (`Modelos.swift`: "o app só recebe
-- status='aprovado'"). Um termo reprovado some de toda consulta, de todo
-- casamento e de toda tela — sem tocar em `produto_termos`, que referencia
-- `termos(id)` sem cascata, e sem destruir a medição que justificou a
-- decisão. Se um dia a família virar vocabulário aberto de verdade, o
-- histórico de ligações ainda está aqui para ser reaproveitado.
--
-- O QUE CONTINUA DE PÉ
-- ====================
-- `conversacional` — agora exibido como **Illustrated prints** — permanece e
-- cobre a mesma família: fruta, comida, bicho desenhado. Medido no mesmo dia,
-- devolve 24 peças em 8 marcas, na mesma ordem de grandeza de `floral` e
-- `animal_print`. Nada de índice, z-score, raridade ou série histórica é
-- tocado: estes termos nasceram com `sem_perna_busca = true` e nunca entraram
-- em `series_semanais` nem no denominador de segmento algum.

begin;

update public.termos
   set status = 'reprovado',
       motivo = 'A48: familia unificada em conversacional (Illustrated prints). '
                'Seis frutas eram amostra arbitraria de uma dimensao aberta; '
                'melancia nunca casou peca alguma.'
 where dimensao = 'motivo_estampa';

-- O motor perde o desvio que existia só para eles.
--
-- A A39 fazia: se a peça tem motivo, ancore nele e relaxe a categoria. Com os
-- termos reprovados esse ramo nunca dispara — o join exige `aprovado`, então
-- `motivos` volta sempre vazio e a função cai no motor amplo. Ele poderia
-- ficar aí sem fazer mal, e é justamente por isso que sai: código que não
-- pode rodar é o que faz a próxima pessoa perder uma tarde entendendo uma
-- regra que não existe mais.
create or replace function public.similares_da_peca_amplo(
  termos text[], limite integer default 12, preco_alvo numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  estrita jsonb;
  ampliada jsonb;
  dimensao_a_relaxar text;
  termos_reduzidos text[];
  dimensoes_originais integer;
  atributos_originais integer;
begin
  select count(*)::integer, count(distinct t.dimensao)::integer
    into atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) e(id)
  join public.termos t on t.id = e.id and t.status = 'aprovado';

  estrita := public.similares_da_peca(termos, limite, preco_alvo);
  if jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) >= least(limite, 8) then
    return estrita;
  end if;

  select t.dimensao into dimensao_a_relaxar
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> 'categoria'
  group by t.dimensao
  order by array_position(
    array['estetica','comprimento','silhueta','cintura','tecido','cor','estampa'],
    t.dimensao) nulls last, min(e.posicao)
  limit 1;
  if dimensao_a_relaxar is null then return estrita; end if;

  select array_agg(e.id order by e.posicao)
    into termos_reduzidos
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> dimensao_a_relaxar;
  if cardinality(termos_reduzidos) = 0 then return estrita; end if;

  ampliada := public.similares_da_peca(termos_reduzidos, limite, preco_alvo);
  if jsonb_array_length(coalesce(ampliada->'pecas', '[]'::jsonb)) <=
     jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) then
    return estrita;
  end if;
  ampliada := jsonb_set(ampliada, '{resumo,atributos_pedidos}',
                        to_jsonb(atributos_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensoes_pedidas}',
                        to_jsonb(dimensoes_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensao_relaxada}',
                        to_jsonb(dimensao_a_relaxar), true);
  return ampliada;
end;
$function$;

revoke all on function public.similares_da_peca_amplo(text[], integer, numeric)
  from public;
grant execute on function public.similares_da_peca_amplo(text[], integer, numeric)
  to anon, authenticated;

commit;
