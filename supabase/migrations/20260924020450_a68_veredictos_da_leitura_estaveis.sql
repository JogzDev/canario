-- A68: a mesma peça, o mesmo veredito.
--
-- A A67 estabilizou a interpretação, mas o verificador ainda variava: com a
-- mesma interpretação de "saia midi plissada", uma rodada confirmou 11 saias
-- e a seguinte 4, porque as "saias com pregas" ficaram ora como a peça, ora
-- como parecidas. O veredito de cada peça passa a ficar guardado junto da
-- interpretação, pelos mesmos sete dias: só peça que entrou no painel depois
-- passa de novo pelo verificador.

alter table public.interpretacoes_da_leitura
  add column if not exists veredictos jsonb not null default '{}'::jsonb;

comment on column public.interpretacoes_da_leitura.veredictos is
  'A68: produto_id -> e_a_peca | parecida | nao_e, decidido pela verificacao desta interpretacao.';
