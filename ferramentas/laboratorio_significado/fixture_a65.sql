-- Fixture da A65: a marca 72 troca de catálogo dez dias antes do painel.
-- 7309 estreia no dia da primeira leitura do catálogo novo (mesmo estoque,
-- código novo); 7310 chega quatro dias antes do painel (lançamento de verdade).
insert into public.trocas_de_catalogo (marca_id, em, de, para, motivo)
select 72, observado_em - 10, 'vtex', 'shopify', 'laboratorio A65'
from public.observacoes_publicadas_do_painel where segmento = 'feminino_casual_br';

insert into public.produtos (id, marca_id, segmento, titulo, url, ultimo_preco_atual,
                             ultimo_preco_original, ultima_grade, primeiro_avistamento)
select v.id, 72, 'feminino_casual_br', v.titulo, 'https://lab.test/' || v.id || '/p',
       200, 200, '{"P": true}'::jsonb, o.observado_em - v.idade
from (values (7309, 'Jaqueta Napoleão Estreia', 10), (7310, 'Jaqueta Napoleão Lançamento', 4)) as v(id, titulo, idade)
cross join (select observado_em from public.observacoes_publicadas_do_painel
            where segmento = 'feminino_casual_br') o;

insert into public.estado_dos_produtos (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em)
select id, o.observado_em, true, o.observado_em
from public.produtos
cross join (select observado_em from public.observacoes_publicadas_do_painel
            where segmento = 'feminino_casual_br') o
where id in (7309, 7310);

insert into public.produto_termos (produto_id, termo_id) values (7309, 'lab_casaco'), (7310, 'lab_casaco');
