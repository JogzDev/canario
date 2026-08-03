-- O statement_timeout e armado ANTES de entrar na funcao. Configura-lo apenas
-- no `create function ... set` nao muda o timer do comando do pg_cron que ja
-- comecou. O SET separado abaixo vale para o SELECT seguinte na mesma sessao,
-- sem alterar o timeout global do role postgres nem das APIs.

select cron.schedule(
  'canario-motor-dispatcher',
  '* * * * *',
  $$set statement_timeout = '900s';
    select public.executar_proxima_publicacao_motor();$$
);

comment on function public.executar_proxima_publicacao_motor() is
  'Dispatcher unico do pg_cron; o comando agenda 900s antes de iniciar a transacao.';
