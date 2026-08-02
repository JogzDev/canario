-- §8, portao de cobertura. O documento e literal:
--
--   "pelo menos 8 marcas ativas coletando e pelo menos 30 pecas na celula
--    (termo x segmento) na semana. Abaixo disso, a interface exibe 'cobertura
--    insuficiente neste segmento' [...] SEM INDICE E SEM ESTADO."
--
-- Ate agora o app nao checava nada disso: mostrava indice sempre. Com o dado de
-- hoje, 6 celulas estao abaixo de 30 pecas (a menor tem 4) -- ou seja, o app
-- estava exibindo numero onde a regra 6 manda calar.
--
-- Marcas de papel `grupo` NAO contam: a §13 diz que sao autobenchmark do
-- cliente e "nunca contam como mercado externo nos indices".
create or replace view cobertura_por_celula
with (security_invoker = false)
as
select
  s.termo_id,
  s.segmento,
  s.semana,
  s.n_amostra                                   as pecas_na_celula,
  (select count(*) from marcas m
     where m.status_teste in ('vtex','shopify')
       and m.ativa
       and m.papel in ('nucleo','adjacente','ancora')
       and exists (select 1 from produtos p where p.marca_id = m.id)
  )                                             as marcas_externas,
  30                                            as minimo_pecas,
  8                                             as minimo_marcas,
  (s.n_amostra >= 30
   and (select count(*) from marcas m
          where m.status_teste in ('vtex','shopify') and m.ativa
            and m.papel in ('nucleo','adjacente','ancora')
            and exists (select 1 from produtos p where p.marca_id = m.id)) >= 8
  )                                             as suficiente
from series_semanais s
where s.fonte = 'varejo';

comment on view cobertura_por_celula is
  '§8: os minimos que decidem se a interface pode exibir indice e estado. Abaixo deles, "cobertura insuficiente" (regra 6).';

grant select on cobertura_por_celula to anon, authenticated;;
