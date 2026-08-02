-- A chave primaria de produto_termos e (produto_id, termo_id, origem), otima
-- para "quais atributos esta peca tem" e inutil para a pergunta do §29, que e
-- a inversa: "quais pecas tem estes atributos".
--
-- Sem este indice a busca de similares varre as 167 mil ligacoes. O app le como
-- `anon`, cujo statement_timeout e de 3 SEGUNDOS -- entao aqui a diferenca nao
-- e de conforto, e de funcionar ou nao.
create index if not exists produto_termos_por_termo
  on public.produto_termos (termo_id, produto_id);

-- O `segmento` entra em toda consulta de painel como filtro.
create index if not exists produtos_segmento
  on public.produtos (segmento) where segmento is not null;;
