-- A69: oito pecas com remarcacao entre dez observadas na semana. Somente
-- quatro estavam ofertaveis no ultimo dia: A58 dizia 200%, A69 diz 80%.
insert into public.marcas
  (id, nome, papel, segmento, status_teste, ativa) values
  (95, 'Lab taxa da semana', 'nucleo', 'feminino_casual_br', 'vtex', true),
  (96, 'Lab sem fotos', 'nucleo', 'feminino_casual_br', 'vtex', true);

insert into public.produtos (id, marca_id, segmento, titulo, url)
select 9500 + n, 95, 'feminino_casual_br', 'Peca ' || n,
       'https://lab.example/taxa/' || n
from generate_series(1, 10) n;

insert into public.produtos (id, marca_id, segmento, titulo, url)
values (9601, 96, 'feminino_casual_br', 'Peca sem foto',
        'https://lab.example/sem-foto');

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ultimo_snapshot_em, ofertavel)
select id, current_date - 15,
       case when id <= 9504 then current_date - 15
            when id = 9508 then current_date - 40
            else current_date - 21 end,
       id <= 9504
from public.produtos where marca_id = 95;

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ultimo_snapshot_em, ofertavel)
values (9601, current_date - 15, current_date - 40, false);

insert into public.snapshots (produto_id, data, ofertavel)
select id, current_date - 21, id <= 9504
from public.produtos where marca_id = 95 and id <> 9508;

insert into public.snapshots (produto_id, data, ofertavel)
select id, current_date - 15, true
from public.produtos where marca_id = 95 and id <= 9504;

insert into public.eventos (produto_id, tipo, data, detalhe)
select id, 'remarcacao', current_date - 15 - (id % 7)::int, '{}'::jsonb
from public.produtos where marca_id = 95 and id <= 9508;

-- Mesmo produto em dois dias: oito pecas, nove eventos.
insert into public.eventos (produto_id, tipo, data, detalhe)
values (9501, 'remarcacao', current_date - 15, '{}'::jsonb),
       (9501, 'reposicao', current_date - 15, '{}'::jsonb),
       (9601, 'remarcacao', current_date - 15, '{}'::jsonb);

select public.computar_sortimento_diario(current_date - 15);
