-- Fixture da A64: a leitura específica procura peças pelo nome.
--
-- Um cenário da jaqueta napoleão, com datas RELATIVAS ao dia publicado do
-- painel que o laboratório deixou (a janela de sete dias da A57 é a regra
-- sob teste). A marca 72 existe só para isto.

create extension if not exists unaccent;
alter table public.produtos add column if not exists primeiro_avistamento date;

insert into public.marcas (id, nome, papel, segmento, status_teste, plataforma, ativa)
values (72, 'Leitura Lab', 'nucleo', 'feminino_casual_br', 'vtex', 'vtex', true);

insert into public.termos (id, rotulo, dimensao, status, papel) values
  ('lab_casaco', 'Casaco (lab)', 'categoria', 'aprovado', 'atributo'),
  ('lab_calca', 'Calça (lab)', 'categoria', 'aprovado', 'atributo');

-- 7301 napoleão de verdade; 7302 casa dois sinais; 7303 é a COR verde militar;
-- 7304 militar sem ser cor; 7305 calça fora da categoria; 7306 saiu da
-- vitrine antes da janela; 7307 esgotada; 7308 título com `%` literal.
insert into public.produtos (id, marca_id, segmento, titulo, url, ultimo_preco_atual,
                             ultimo_preco_original, ultima_grade, primeiro_avistamento)
select v.id, 72, 'feminino_casual_br', v.titulo, 'https://lab.test/' || v.id || '/p',
       v.preco, v.original, v.grade::jsonb, o.observado_em - v.idade
from (values
  (7301, 'Jaqueta Napoleão Botões Dourados', 300::numeric, 300::numeric, '{"P": true, "M": false}', 5),
  (7302, 'Jaqueta Napoleão Abotoamento Duplo', 240, 300, '{"P": true, "M": true}', 60),
  (7303, 'Jaqueta Utilitária Verde Militar', 200, 200, '{"P": true}', 60),
  (7304, 'Jaqueta Militar Azul', 180, 180, '{"P": true}', 60),
  (7305, 'Calça Napoleão Alfaiataria', 150, 150, '{"P": true}', 60),
  (7306, 'Jaqueta Napoleão Antiga', 500, 500, '{"P": true}', 90),
  (7307, 'Jaqueta Napoleão Esgotada', 350, 350, '{"P": false}', 60),
  (7308, 'Jaqueta 50%_off Napoleão', 100, 100, '{"P": true}', 60)
) as v(id, titulo, preco, original, grade, idade)
cross join (select observado_em from public.observacoes_publicadas_do_painel
            where segmento = 'feminino_casual_br') o;

insert into public.estado_dos_produtos (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em)
select p.id,
       case when p.id = 7306 then o.observado_em - 20 else o.observado_em end,
       p.id <> 7307,
       o.observado_em
from public.produtos p
cross join (select observado_em from public.observacoes_publicadas_do_painel
            where segmento = 'feminino_casual_br') o
where p.id between 7301 and 7308;

insert into public.produto_termos (produto_id, termo_id)
select id, case when id = 7305 then 'lab_calca' else 'lab_casaco' end
from public.produtos where id between 7301 and 7308;

-- Uma reposição dentro da janela de 30 dias e uma fora dela.
insert into public.eventos (produto_id, tipo, data, detalhe)
select 7301, 'reposicao', observado_em - 3, '{}'::jsonb
from public.observacoes_publicadas_do_painel where segmento = 'feminino_casual_br'
union all
select 7302, 'remarcacao', observado_em - 45, '{}'::jsonb
from public.observacoes_publicadas_do_painel where segmento = 'feminino_casual_br';
