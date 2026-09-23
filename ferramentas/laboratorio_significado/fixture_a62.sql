-- Fixture da A62: a curva de tamanhos só com o que está na vitrine.
--
-- A fixture base deixa `computar_curva_tamanhos` e `ordem_do_tamanho` como
-- talos. Aqui os talos saem e o `rodar.mjs` instala as versões de PRODUÇÃO,
-- extraídas das migrations e conferidas por md5: a P0 é o "antes" e a F4 é a
-- ordem da grade que a curva usa para montar as faixas.
--
-- AS DATAS SÃO RELATIVAS AO RELÓGIO DO DADO
-- =========================================
--
-- A curva ancora a semana no maior snapshot (`semana_alvo`), e a fixture da
-- A61 tem datas fixas até 08/10/2026 -- no futuro de quem roda antes disso.
-- Por isso o "hoje" da curva (H) é o maior entre o calendário e tudo o que já
-- está no banco: os snapshots desta fixture em H passam a ser o maior dia, e
-- a semana alvo é a de H em qualquer data de execução. O segmento pausado usa
-- o calendário (P = current_date - 20): fica sempre antes da janela da curva,
-- que começa no máximo 14 dias antes de H, e a mais de sete dias de hoje.
--
-- OS TRÊS SEGMENTOS
-- =================
--
-- `lab_curva` (âncora H), cinco tamanhos PP..GG por peça:
--   8201 ativa, vista em H, quebrou o G na janela              -> entra
--   8202 ofertável no estado, mas vista há 60 dias              -> sai
--   8203 vista há 8 dias (um além da tolerância)                -> sai
--   8204 vista há exatamente 7 dias                             -> entra
--   8205 esgotou DENTRO da janela, vista em H                   -> entra
--   8206 esgotada há meses e ainda listada (o caso da PatBo)    -> sai
--   8207 catálogo aposentado numa troca em H-2, vista em H-3    -> sai
--   8208 catálogo novo da mesma marca, vista em H               -> entra
--
-- `lab_curva_semanal` (âncora H-7, coleta semanal atrasada):
--   8401 vista em H-7, a âncora dele                            -> entra
--   8402 vista em H-12: 5 dias antes da âncora DELE, 12 de H    -> entra
--   8403 vista em H-15: 8 dias antes da âncora dele             -> sai
--
-- `lab_curva_pausado` (âncora P, parado há 20 dias, fora da janela da curva):
--   8301 vista em P, 8302 vista em P-8. A P0 os põe na semana nova; a A62 não
--   põe nenhum: a foto deles é de outra semana.

drop function public.computar_curva_tamanhos();
drop function public.ordem_do_tamanho(text);

-- A tabela como está em produção em 23/09/2026 (colunas, chave e RLS).
create table public.curva_tamanhos (
  id bigserial primary key,
  termo_id text references public.termos(id) on delete cascade,
  segmento text not null,
  semana date not null,
  sistema text not null,
  faixa text not null,
  rotulo text,
  n_grades integer not null,
  n_pares integer not null,
  n_indisponivel integer not null,
  n_quebrou integer not null default 0,
  share_indisponivel numeric,
  meta jsonb,
  computado_em timestamptz not null default now(),
  n_em_risco integer not null default 0,
  taxa_quebra numeric
);
create unique index curva_tamanhos_chave
  on public.curva_tamanhos (termo_id, segmento, semana, sistema, faixa, rotulo)
  nulls not distinct;
alter table public.curva_tamanhos enable row level security;
create policy curva_tamanhos_leitura on public.curva_tamanhos
  for select to anon, authenticated using (true);
grant select on public.curva_tamanhos to anon, authenticated;
grant all on public.curva_tamanhos to service_role;
grant usage on sequence public.curva_tamanhos_id_seq to service_role;

-- O relógio, congelado ANTES de qualquer snapshot desta fixture.
create temp table relogio_a62 as
select greatest(current_date,
                (select max(data) from public.snapshots),
                (select max(ultimo_avistamento_em) from public.estado_dos_produtos)) as h,
       current_date - 20 as p;

insert into public.marcas
  (id, nome, papel, segmento, status_teste, plataforma, ativa) values
  (81, 'Lab curva', 'nucleo', 'lab_curva', 'vtex', 'vtex', true),
  (82, 'Lab curva troca', 'nucleo', 'lab_curva', 'shopify', 'shopify', true),
  (83, 'Lab curva pausada', 'nucleo', 'lab_curva_pausado', 'vtex', 'vtex', true),
  (84, 'Lab curva semanal', 'nucleo', 'lab_curva_semanal', 'vtex', 'vtex', true);

-- A troca da marca 82 cai dentro da janela: sem a A61 na base, o catálogo
-- antigo, visto um dia antes dela, ainda passaria no filtro de sete dias.
insert into public.trocas_de_catalogo (marca_id, em, de, para, motivo)
select 82, h - 2, 'shopify', 'nuvemshop', 'laboratorio A62'
from relogio_a62;

insert into public.produtos (id, marca_id, segmento, titulo, url, ultima_grade)
select v.id, v.marca, v.segmento, v.titulo, 'https://lab.example/' || v.id, v.grade::jsonb
from (values
  (8201, 81, 'lab_curva', 'Ativa',
   '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (8202, 81, 'lab_curva', 'Morta ha 60 dias',
   '{"PP": true, "P": false, "M": false, "G": false, "GG": false}'),
  (8203, 81, 'lab_curva', 'Vista ha 8 dias',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": false}'),
  (8204, 81, 'lab_curva', 'Vista ha 7 dias',
   '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  (8205, 81, 'lab_curva', 'Esgotou na janela',
   '{"PP": false, "P": false, "M": false, "G": false, "GG": false}'),
  (8206, 81, 'lab_curva', 'Esgotada ha meses, ainda listada',
   '{"PP": false, "P": false, "M": false, "G": false, "GG": false}'),
  (8207, 82, 'lab_curva', 'Catalogo aposentado',
   '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (8208, 82, 'lab_curva', 'Catalogo novo',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8301, 83, 'lab_curva_pausado', 'Pausada vista na ancora',
   '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  (8302, 83, 'lab_curva_pausado', 'Pausada vista 8 dias antes',
   '{"PP": false, "P": false, "M": false, "G": false, "GG": true}'),
  (8401, 84, 'lab_curva_semanal', 'Semanal vista na ancora',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8402, 84, 'lab_curva_semanal', 'Semanal vista 5 dias antes da ancora',
   '{"PP": true, "P": false, "M": true, "G": true, "GG": true}'),
  (8403, 84, 'lab_curva_semanal', 'Semanal vista 8 dias antes da ancora',
   '{"PP": false, "P": false, "M": false, "G": false, "GG": true}')
) v(id, marca, segmento, titulo, grade);

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em)
select v.id, v.visto, v.ofertavel, v.visto
from relogio_a62 r
cross join lateral (values
  (8201, r.h, true),
  (8202, r.h - 60, true),
  (8203, r.h - 8, true),
  (8204, r.h - 7, true),
  (8205, r.h, false),
  (8206, r.h, false),
  (8207, r.h - 3, true),
  (8208, r.h, true),
  (8301, r.p, true),
  (8302, r.p - 8, true),
  (8401, r.h - 7, true),
  (8402, r.h - 12, true),
  (8403, r.h - 15, true)
) v(id, visto, ofertavel);

-- A janela da curva vai de (segunda de H) - 7 a H: H-7 está sempre dentro,
-- qualquer que seja o dia da semana de H.
insert into public.snapshots (produto_id, data, ofertavel, grade_por_tamanho)
select v.id, v.data, v.ofertavel, v.grade::jsonb
from relogio_a62 r
cross join lateral (values
  (8201, r.h - 7, true, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8201, r.h, true, '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (8202, r.h - 60, true, '{"PP": true, "P": false, "M": false, "G": false, "GG": false}'),
  (8203, r.h - 20, true, '{"PP": true, "P": true, "M": true, "G": true, "GG": false}'),
  (8204, r.h - 7, true, '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  -- Estava inteira no início da janela e esgotou: é a quebra.
  (8205, r.h - 7, true, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8205, r.h, false, '{"PP": false, "P": false, "M": false, "G": false, "GG": false}'),
  -- Esgotou há um mês; o batimento semanal do coletor segue gravando a
  -- página esgotada, então há snapshot DENTRO da janela, mas sem oferta.
  (8206, r.h - 30, true, '{"PP": true, "P": false, "M": false, "G": false, "GG": false}'),
  (8206, r.h - 3, false, '{"PP": false, "P": false, "M": false, "G": false, "GG": false}'),
  (8207, r.h - 7, true, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8207, r.h - 3, true, '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (8208, r.h - 1, true, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (8301, r.p, true, '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  (8302, r.p - 8, true, '{"PP": false, "P": false, "M": false, "G": false, "GG": true}')
) v(id, data, ofertavel, grade);

-- Dois termos: um com uma peça viva e uma morta, outro só com a morta. O
-- segundo prova que a combinação que só existia no estoque morto sai da
-- semana, em vez de ficar com o número velho.
insert into public.termos (id, rotulo, dimensao, status, papel) values
  ('lab_curva_vivo', 'Termo com peca viva', 'lab_a62', 'aprovado', 'atributo'),
  ('lab_curva_morto', 'Termo so de estoque morto', 'lab_a62', 'aprovado', 'atributo');
insert into public.produto_termos (produto_id, termo_id) values
  (8201, 'lab_curva_vivo'), (8202, 'lab_curva_vivo'), (8202, 'lab_curva_morto');

-- Leituras da curva para as asserções: a semana alvo e a soma das três faixas
-- (linhas sem rótulo) de um segmento, no total ou num termo.
create function pg_temp.semana_a62() returns date
language sql stable as $$
  select max(data) - ((extract(isodow from max(data)))::int - 1) from public.snapshots;
$$;

create function pg_temp.faixas_a62(p_segmento text, p_termo text default null)
returns table (grades integer, pares integer, indisponivel integer,
               em_risco integer, quebrou integer)
language sql stable as $$
  select max(n_grades), sum(n_pares)::int, sum(n_indisponivel)::int,
         sum(n_em_risco)::int, sum(n_quebrou)::int
  from public.curva_tamanhos
  where segmento = p_segmento and termo_id is not distinct from p_termo
    and rotulo is null and semana = pg_temp.semana_a62();
$$;

-- Uma semana já publicada do termo que hoje só tem estoque morto. A
-- combinação dele não volta na semana nova -- é exatamente a linha que um
-- `delete` sem o filtro de semana levaria junto. Ela é história e fica.
insert into public.curva_tamanhos
  (termo_id, segmento, semana, sistema, faixa, rotulo, n_grades, n_pares,
   n_indisponivel, n_em_risco, n_quebrou, share_indisponivel, meta)
select 'lab_curva_morto', 'lab_curva', (r.h - ((extract(isodow from r.h))::int - 1)) - 7,
       'letra', 'meio', null, 99, 99, 99, 99, 9, 100, '{"publicada": true}'::jsonb
from relogio_a62 r;
