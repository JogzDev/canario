-- O app precisa dos eventos da §27 ("reposições da semana: é o sinal mais
-- forte"), mas NAO pode ler `produtos`, `marcas` nem `snapshots` -- sao tabelas
-- cruas e ficam fora do alcance da chave publishable.
--
-- Esta view entrega so o que a tela mostra: marca, peca, tipo e detalhe. Sem
-- preco de custo, sem id interno, sem nada que nao apareca em tela.
create or replace view eventos_da_semana
with (security_invoker = false)
as
select
  e.id,
  e.tipo,
  e.data,
  (e.data - ((extract(isodow from e.data)::int) - 1))  as semana,
  m.nome                                              as marca,
  m.papel                                             as papel_da_marca,
  p.titulo                                            as peca,
  p.url                                               as url_da_peca,   -- regra 3: rastreabilidade
  p.segmento,
  e.detalhe
from eventos e
join produtos p on p.id = e.produto_id
join marcas   m on m.id = p.marca_id
where p.segmento is not null;

comment on view eventos_da_semana is
  '§27: reposições e remarcações da semana para a aba Explorar. Expõe só o que a tela mostra; tabelas cruas seguem fechadas.';

grant select on eventos_da_semana to anon, authenticated;;
