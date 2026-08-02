-- O app precisa da taxonomia para existir:
--   * §29 e §27 exibem o ROTULO ("Lilás e roxo"), nunca o id;
--   * §11 exige que a barra de busca traduza a string do usuario em termos via
--     rotulos e SINONIMOS -- "a barra de busca do app nunca vira filtro de texto
--     cru" -- e sem ler a taxonomia isso e impossivel;
--   * §27 agrupa por dimensao e precisa saber se ela e exclusiva (selecao unica
--     ou multipla no formulario).
--
-- A politica libera SO o que esta aprovado, o que e a regra inviolavel 4 escrita
-- em RLS: linha com status diferente de `aprovado` nao chega ao app de jeito
-- nenhum, nem por engano de consulta.
--
-- Feito por policy em vez de view com direitos de dono: assim a restricao vive
-- no banco e vale para qualquer caminho de leitura, e nao depende de o app
-- lembrar de filtrar.
grant select on termos to anon, authenticated;

create policy "app le apenas termos aprovados"
  on termos for select
  to anon, authenticated
  using (status = 'aprovado');

comment on policy "app le apenas termos aprovados" on termos is
  'Regra inviolavel 4 em RLS: o motor e o app so usam taxonomia aprovada.';;
