-- Fixture do laboratório de significado (A57/A58).
--
-- POR QUE ESTE ARQUIVO EXISTE
-- ===========================
--
-- O portão de contratos do `teste_migrations.py` procura trechos de texto nas
-- migrations. Isso pega contrato apagado; não pega `JOIN` errado, denominador
-- tirado da data errada nem JSON inválido. Aqui as duas RPCs rodam num
-- PostgreSQL 17.10 de verdade, sobre dados desenhados para que cada defeito
-- conhecido apareça como falha.
--
-- O QUE ESTE LABORATÓRIO NÃO PROVA
-- ================================
--
-- `ordem_do_tamanho` e `grade_em_texto` entram como versões mínimas: a
-- formatação da grade não é assunto destas duas RPCs e continua provada pelos
-- testes do app. `url_publica_produto` é copiada fiel (P7), porque o link é
-- uma das coisas que a A57 corrige.
--
-- AS DATAS SÃO RELATIVAS
-- ======================
--
-- `D0 = current_date - 15` simula o que está acontecendo de verdade: coleta
-- parada há duas semanas. As funções olham `current_date`, então datas fixas
-- fariam o teste mudar de resultado com o passar dos dias.

create role anon nologin;
create role authenticated nologin;
-- A coleta e o motor falam com o banco por este papel. Ele existe aqui porque
-- `grant execute ... to service_role` e parte do que esta sob teste: sem o
-- grant, a funcao existe e nao roda.
create role service_role nologin;

create table public.marcas (
  id bigint primary key,
  nome text not null unique,
  papel text
);

create table public.produtos (
  id bigint primary key,
  marca_id bigint not null references public.marcas(id),
  segmento text,
  titulo text,
  url text,
  imagem_url text,
  ultimo_preco_atual numeric,
  ultimo_preco_original numeric,
  ultima_grade jsonb,
  ultimo_snapshot_em date
);

create table public.estado_dos_produtos (
  produto_id bigint primary key references public.produtos(id) on delete cascade,
  ultimo_avistamento_em date not null,
  ofertavel boolean not null,
  ultimo_snapshot_em date not null
);

create table public.eventos (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  tipo text not null,
  data date not null,
  detalhe jsonb
);
create index eventos_produto_tipo_data_id_idx
  on public.eventos (produto_id, tipo, data, id);
create index eventos_tipo_data_id_idx on public.eventos (tipo, data desc, id desc);

create table public.snapshots (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  data date not null,
  ofertavel boolean,
  unique (produto_id, data)
);

create table public.termos (
  id text primary key,
  rotulo text,
  dimensao text not null,
  status text not null default 'aprovado'
);

create table public.produto_termos (
  produto_id bigint not null references public.produtos(id) on delete cascade,
  termo_id text not null references public.termos(id),
  origem text default 'titulo',
  primary key (produto_id, termo_id)
);

create table public.artigos (
  id bigint generated always as identity primary key,
  veiculo text,
  url text unique,
  titulo text,
  data_pub date,
  publico_editorial text not null default 'neutro'
);

-- Copiada da P7: é parte do que a A57 corrige.
create or replace function public.url_publica_produto(url text, marca text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select case
    when url is null then null
    when marca = 'Maria Filo'
     and url like 'https://mariafilo.vtexcommercestable.com.br/%'
      then null
    else url
  end;
$function$;

-- Versões mínimas: a grade não é assunto das RPCs sob teste.
create or replace function public.ordem_do_tamanho(rotulo text)
returns table (rotulo text, sistema text, ordem integer)
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select rotulo, 'letra'::text, 1;
$function$;

create or replace function public.grade_em_texto(grade jsonb)
returns jsonb
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'degraus', (select count(*) from jsonb_each(coalesce(grade, '{}'::jsonb))),
    'disponiveis', (select count(*) from jsonb_each(coalesce(grade, '{}'::jsonb)) t
                     where t.value = 'true'::jsonb));
$function$;

-- MARCAS
--
-- Grande  : 500 produtos, 200 com reposição na janela  -> catálogo grande
-- Pequena : 10 produtos, 8 com reposição               -> catálogo pequeno
-- Candidata: 5 produtos em `catalogo_candidato_br`, observados DEPOIS do
--            painel; existem para provar que a âncora de frescor de um
--            segmento não reprova o outro.
insert into public.marcas (id, nome, papel) values
  (1, 'Grande', 'ancora'),
  (2, 'Pequena', 'nucleo'),
  (3, 'Candidata', 'nucleo');

insert into public.produtos (id, marca_id, segmento, titulo, url, imagem_url,
                             ultimo_preco_atual, ultimo_preco_original,
                             ultima_grade, ultimo_snapshot_em)
select n, 1, 'feminino_casual_br', 'Peça grande ' || n,
       'https://grande.example/p/' || n, 'https://grande.example/i/' || n || '.jpg',
       200, 250, '{"M": true}'::jsonb,
       -- Congelada de propósito: é a coluna que a A27 abandonou e a A57 para
       -- de consultar. Se alguém voltar a lê-la, o link desaparece.
       current_date - 40
from generate_series(1, 500) n;

insert into public.produtos (id, marca_id, segmento, titulo, url, imagem_url,
                             ultimo_preco_atual, ultimo_preco_original,
                             ultima_grade, ultimo_snapshot_em)
select 1000 + n, 2, 'feminino_casual_br', 'Peça pequena ' || n,
       'https://pequena.example/p/' || n, 'https://pequena.example/i/' || n || '.jpg',
       500, 500, '{"M": true}'::jsonb, current_date - 40
from generate_series(1, 10) n;

insert into public.produtos (id, marca_id, segmento, titulo, url, imagem_url,
                             ultimo_preco_atual, ultimo_preco_original,
                             ultima_grade, ultimo_snapshot_em)
select 2000 + n, 3, 'catalogo_candidato_br', 'Candidata ' || n,
       'https://candidata.example/p/' || n, null,
       300, 300, '{"M": true}'::jsonb, current_date - 40
from generate_series(1, 5) n;

-- PECAS DE CATALOGO MORTO
--
-- Tres pecas da Grande vistas uma vez, 30 dias atras, e nunca mais. Sob a
-- regra antiga (`s.data <= alvo`, sem piso) elas contariam como ofertaveis
-- para sempre e inflariam o denominador de todo dia posterior. Sob a P17 o
-- snapshot vale sete dias: elas contam no dia delas e em mais nenhum.
insert into public.produtos (id, marca_id, segmento, titulo, url, imagem_url,
                             ultimo_preco_atual, ultimo_preco_original,
                             ultima_grade, ultimo_snapshot_em)
select 600 + n, 1, 'feminino_casual_br', 'Peça abandonada ' || n,
       'https://grande.example/p/x' || n, null,
       100, 100, '{"M": true}'::jsonb, current_date - 40
from generate_series(1, 3) n;

-- ESTADO ATUAL
--
-- Painel visto em D0 = current_date - 15 (a pausa). Candidatas vistas em
-- D0 + 10, bem mais perto de hoje: com uma âncora única, D0+10-7 = D0+3
-- reprovaria o painel inteiro outra vez.
insert into public.estado_dos_produtos (produto_id, ultimo_avistamento_em,
                                        ofertavel, ultimo_snapshot_em)
select id, current_date - 15, true, current_date - 15
from public.produtos
where segmento = 'feminino_casual_br' and id not between 601 and 603;

-- O estado das abandonadas ainda diz `ofertavel`: e exatamente assim que o
-- catalogo morto entra numa contagem que le o estado em vez do observado.
insert into public.estado_dos_produtos (produto_id, ultimo_avistamento_em,
                                        ofertavel, ultimo_snapshot_em)
select id, current_date - 30, true, current_date - 30
from public.produtos where id between 601 and 603;

insert into public.estado_dos_produtos (produto_id, ultimo_avistamento_em,
                                        ofertavel, ultimo_snapshot_em)
select id, current_date - 5, true, current_date - 5
from public.produtos where segmento = 'catalogo_candidato_br';

-- SNAPSHOTS
--
-- O denominador sai daqui, não do estado de hoje: em D0 a Grande tinha 400
-- ofertáveis (100 fora do ar) e o estado atual diz 500. Se a função voltar a
-- contar o estado, a taxa muda e o teste falha.
insert into public.snapshots (produto_id, data, ofertavel)
select n, current_date - 15, n <= 400
from generate_series(1, 500) n;

insert into public.snapshots (produto_id, data, ofertavel)
select 600 + n, current_date - 30, true from generate_series(1, 3) n;

insert into public.snapshots (produto_id, data, ofertavel)
select 1000 + n, current_date - 15, true from generate_series(1, 10) n;

insert into public.snapshots (produto_id, data, ofertavel)
select 2000 + n, current_date - 5, true from generate_series(1, 5) n;

-- EVENTOS DE REPOSIÇÃO
--
-- Grande: 200 produtos distintos na janela e 232 eventos -- 30 produtos
-- voltaram duas vezes dentro da própria janela e 2 deles voltaram três.
-- Acima dos 120 da amostra antiga de propósito.
insert into public.eventos (produto_id, tipo, data, detalhe)
select n, 'reposicao', current_date - 15 - (n % 7),
       jsonb_build_object('tamanhos', jsonb_build_array('M', 'G'))
from generate_series(1, 200) n;

insert into public.eventos (produto_id, tipo, data, detalhe)
select n, 'reposicao', current_date - 15,
       jsonb_build_object('tamanhos', jsonb_build_array('P'))
from generate_series(1, 30) n;

-- Duas pecas voltaram uma TERCEIRA vez no mesmo dia, com os ids mais altos da
-- janela. Elas sao a armadilha dos exemplos: sem `distinct on (produto_id)`,
-- duas pecas ocupam quatro dos seis cartoes da marca.
insert into public.eventos (produto_id, tipo, data, detalhe)
select p, 'reposicao', current_date - 15,
       jsonb_build_object('tamanhos', jsonb_build_array('GG'))
from unnest(array[29, 30]) p;

-- 10 desses produtos já tinham voltado ANTES da janela: são as "repetidas".
insert into public.eventos (produto_id, tipo, data, detalhe)
select n, 'reposicao', current_date - 40, '{}'::jsonb
from generate_series(1, 10) n;

insert into public.eventos (produto_id, tipo, data, detalhe)
select 1000 + n, 'reposicao', current_date - 15 - (n % 3),
       jsonb_build_object('tamanhos', jsonb_build_array('M'))
from generate_series(1, 8) n;

-- TAXONOMIA E LIGAÇÕES
--
-- 20 produtos do painel são vestido + preto. As candidatas ganham outros
-- termos: elas existem para mexer na data, não na contagem.
insert into public.termos (id, rotulo, dimensao) values
  ('vestido', 'Vestido', 'categoria'),
  ('preto', 'Preto', 'cor'),
  ('saia', 'Saia', 'categoria');

insert into public.produto_termos (produto_id, termo_id)
select n, t from generate_series(1, 20) n,
  unnest(array['vestido', 'preto']) t;

insert into public.produto_termos (produto_id, termo_id)
select 2000 + n, 'saia' from generate_series(1, 5) n;

-- ARTIGOS
--
-- Um título com a expressão exata do teste do JP, um em caixa alta, um
-- masculino (fora do recorte do painel) e um com `%`, `_` e barra, que só é
-- achado se a expressão do usuário for tratada como dado.
insert into public.artigos (veiculo, url, titulo, data_pub, publico_editorial) values
  ('Refinery29', 'https://ex.example/napoleon',
   'The Napoleon Jacket Is Making A Comeback This Fall', current_date - 17, 'feminino'),
  ('Vogue', 'https://ex.example/caixa',
   'NAPOLEON EM CAIXA ALTA', current_date - 18, 'neutro'),
  ('GQ', 'https://ex.example/masculino',
   'The Napoleon Jacket for men', current_date - 19, 'masculino'),
  ('Elle', 'https://ex.example/curinga',
   'Promo 50%_off com barra \ no titulo', current_date - 20, 'feminino'),
  ('Elle', 'https://ex.example/outro',
   'Promo 50 qualquer off sem curinga', current_date - 21, 'feminino');

-- O MOTOR, O SUFICIENTE PARA PROVAR A ORDEM
-- =========================================
--
-- `computar_motor` e o unico lugar onde a poda acontece, e a A58 encaixa a
-- reconstrucao do denominador imediatamente antes dela. Os sete passos de
-- calculo entram como talos: o que esta sob teste e a ORDEM, nao a aritmetica
-- deles, que tem testes proprios. `podar_snapshots` vem copiada fiel da A42,
-- porque apagar o cru de verdade e o que torna a ordem observavel.
create or replace function public.computar_eventos() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_serie_varejo() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_serie_editorial() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_z() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_indice() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_curva_tamanhos() returns integer
  language sql as $function$ select 0; $function$;
create or replace function public.computar_raridade() returns integer
  language sql as $function$ select 0; $function$;

create or replace function public.podar_snapshots(p_retencao_dias integer default 21)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  removidas integer := 0;
begin
  if p_retencao_dias < 21 then
    raise exception 'retencao de snapshots abaixo do piso seguro de 21 dias';
  end if;

  delete from public.snapshots
  where data < (current_date - p_retencao_dias);
  get diagnostics removidas = row_count;
  return removidas;
end;
$function$;

grant execute on function public.podar_snapshots(integer) to service_role;
grant usage on schema public to service_role, anon;
-- No Supabase, `service_role` tem acesso pleno as tabelas e passa por cima da
-- RLS. `podar_snapshots` roda como INVOKER: sem este grant ela falharia aqui
-- por um motivo que nao existe em producao, e o teste mediria o laboratorio.
grant all on all tables in schema public to service_role;
