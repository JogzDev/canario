-- A47: os índices de URL saem junto com a porta que os usava.
--
-- POR QUE
-- =======
--
-- Em 26/08 o banco chegou a 93,5% do teto gratuito (467.602.579 de 500.000.000
-- bytes), com 12,4 MB até o portão de 96% bloquear TODA coleta. Medindo objeto
-- por objeto, dois índices apareceram no topo da lista de desperdício:
--
--   produtos_url_lookup             8.480 kB   7 varreduras na vida inteira
--   produtos_url_lookup_segmentos  10.000 kB  13 varreduras na vida inteira
--
-- 18,5 MB -- 57% de todo o espaço livre -- para servir vinte consultas. Eles
-- existiam só para a entrada por link de produto, que saiu do app no mesmo dia
-- a pedido do JP.
--
-- Note que o da A32 já era redundante ANTES disso: o da A45 indexa os mesmos
-- `url` com um predicado que inclui `feminino_casual_br`. Os dois conviviam
-- cobrindo a mesma consulta.
--
-- O QUE CONTINUA DE PÉ
-- ====================
--
-- `produto_do_painel_por_url` NÃO é removida. A resolução de URL continua
-- funcionando -- só passa a varrer em vez de usar índice, o que é aceitável
-- porque nenhuma tela a chama hoje. Recolocar a entrada no app é recriar o
-- índice da A45 (a linha está abaixo, comentada) e reconstruir o cartão.
--
-- Medido depois: 467.651.731 -> 448.097.427 bytes, de 93,5% para 89,6%.

drop index if exists public.produtos_url_lookup;
drop index if exists public.produtos_url_lookup_segmentos;

-- Para religar, quando a entrada por link voltar ao app:
--
-- create index produtos_url_lookup_segmentos on public.produtos using btree (url)
--   where url is not null
--     and segmento = any (array['feminino_casual_br', 'catalogo_candidato_br']);
