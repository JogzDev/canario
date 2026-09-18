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
-- No Supabase este papel tem BYPASSRLS. Reproduzir isso aqui importa agora
-- que o motor escreve o marcador de observacao publicado diretamente, dentro
-- da mesma transacao dos demais calculos.
create role service_role nologin bypassrls;

create table public.marcas (
  id bigint primary key,
  nome text not null unique,
  papel text,
  segmento text,
  status_teste text not null default 'vtex',
  ativa boolean not null default true
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

create table public.saude (
  id bigint generated always as identity primary key,
  data date not null,
  fonte text not null,
  marca_id bigint references public.marcas(id),
  visitados integer,
  alertas jsonb,
  unique nulls not distinct (data, fonte, marca_id)
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
insert into public.marcas
  (id, nome, papel, segmento, status_teste, ativa) values
  (1, 'Grande', 'ancora', 'feminino_casual_br', 'vtex', true),
  (2, 'Pequena', 'nucleo', 'feminino_casual_br', 'shopify', true),
  (3, 'Candidata', 'nucleo', 'catalogo_candidato_br', 'vtex', true),
  -- Sem produto de proposito: fica inativa nos casos normais e entra na
  -- assercao 23 para provar que expectativa nao pode nascer de produtos.
  (4, 'Nova sem produtos', 'nucleo', 'feminino_casual_br', 'vtex', false);

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

-- Um lote parcial MAIS NUMEROSO que o resto do painel salta 14 dias. A
-- heuristica anterior (maior count, mais novo no empate) escolheria este dia
-- como seed, apesar de a Pequena nao ter sido coletada por inteiro.
update public.estado_dos_produtos
   set ultimo_avistamento_em = current_date - 1
 where produto_id between 201 and 500;

-- Sete dias positivos formam a base do mesmo portao de volume usado pelo
-- coletor. A Pequena cai de 100 para 10 no lote parcial mais novo: ainda e um
-- numero positivo e nao traz alerta de erro/truncamento, mas e so 10% da sua
-- media. Isso prova que o seed nao confunde "respondeu" com "veio inteiro".
insert into public.saude (data, fonte, marca_id, visitados, alertas)
select current_date - dias, 'varejo', marca_id, 100, null
from generate_series(2, 8) dias
cross join unnest(array[1::bigint, 2::bigint]) marca_id;

-- A prova persistida que autoriza os dois marcadores iniciais. O motor exige
-- uma linha publicavel por marca ativa do segmento na mesma data candidata.
insert into public.saude (data, fonte, marca_id, visitados, alertas) values
  (current_date - 15, 'varejo', 1, 500, null),
  (current_date - 15, 'varejo', 2, 10, null),
  (current_date - 5, 'varejo', 3, 5, null),
  (current_date - 1, 'varejo', 1, 300, null),
  (current_date - 1, 'varejo', 2, 10, null);

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

-- AS FUNCOES QUE OS APARELHOS JA INSTALADOS CHAMAM
-- ================================================
--
-- Copiadas fiel da A40 e da A48, sem uma virgula de diferenca. Elas entram
-- aqui porque a A57 deixou de substitui-las: o comportamento delas e agora
-- parte do contrato sob teste. Com a coleta parada ha 15 dias, `v1` devolve
-- ZERO -- que e exatamente o defeito de producao, e exatamente o que um app
-- nao atualizado espera continuar recebendo ate ser atualizado.
create or replace function public.similares_da_peca(termos text[],
                                                    limite integer default 12,
                                                    preco_alvo numeric default null)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with entrada as (
    select e.termo_id, min(e.posicao) as primeira_posicao,
           min(t.dimensao) as dimensao
    from unnest(coalesce($1, '{}'::text[])) with ordinality e(termo_id, posicao)
    join public.termos t
      on t.id = e.termo_id and t.status = 'aprovado'
    group by e.termo_id
    order by min(e.posicao)
    limit 12
  ), parametros as (
    select count(*)::int as pedidos,
           count(distinct dimensao)::int as dimensoes_pedidas,
           greatest(1, ceil(0.7 * count(distinct dimensao))::int) as minimo_base,
           least(greatest(coalesce($2, 12), 1), 24) as teto,
           coalesce(array_agg(termo_id order by primeira_posicao)
             filter (where dimensao = 'categoria'), '{}'::text[]) as categorias
    from entrada
  ), casamentos as (
    select pt.produto_id,
           count(distinct pt.termo_id)::int as em_comum,
           count(distinct e.dimensao)::int as dimensoes_em_comum,
           array_agg(distinct pt.termo_id) as termos_em_comum,
           bool_or(e.dimensao = 'categoria') as tem_categoria
    from public.produto_termos pt
    join entrada e on e.termo_id = pt.termo_id
    group by pt.produto_id
  ), elegiveis as (
    select c.*
    from casamentos c
    join public.produtos p on p.id = c.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    cross join parametros par
    where p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em >= current_date - 7
      and (cardinality(par.categorias) = 0 or c.tem_categoria)
  ), nivel_escolhido as (
    select coalesce(max(nivel) filter (where existe), 1)::int as minimo
    from parametros par
    cross join lateral generate_series(par.minimo_base, 1, -1) nivel
    cross join lateral (
      select exists(select 1 from elegiveis e
                    where e.dimensoes_em_comum >= nivel) as existe
    ) x
  ), candidatos as (
    select e.*
    from elegiveis e cross join nivel_escolhido n
    where e.dimensoes_em_comum >= n.minimo
  ), sim as (
    select p.id, p.titulo,
           public.url_publica_produto(p.url, m.nome) as url,
           p.imagem_url as imagem,
           p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as preco_de, p.ultima_grade,
           m.nome as marca, m.papel as papel_da_marca,
           c.em_comum, c.dimensoes_em_comum, c.termos_em_comum,
           p.ultima_grade is not null as tem_grade,
           g.quebrada, g.esgotada
    from candidatos c
    join public.produtos p on p.id = c.produto_id
    join public.marcas m on m.id = p.marca_id
    cross join lateral (
      select bool_or(value = 'false'::jsonb) as quebrada,
             not bool_or(value = 'true'::jsonb) as esgotada
      from jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb))
    ) g
    where coalesce(g.esgotada, false) = false
  ), resumo as (
    select jsonb_build_object(
      'n_similares', count(*),
      'n_marcas', count(distinct marca),
      'atributos_pedidos', (select pedidos from parametros),
      'dimensoes_pedidas', (select dimensoes_pedidas from parametros),
      'minimo_em_comum', coalesce(min(em_comum), 0),
      'minimo_dimensoes', (select minimo from nivel_escolhido),
      'n_com_todos', count(*) filter (
        where em_comum = (select pedidos from parametros)),
      'com_preco', count(*) filter (where preco is not null),
      'pct_preco_cheio', case when count(*) filter (where preco is not null) > 0
        then round(100.0 * count(*) filter (
               where preco is not null and preco >= coalesce(preco_de, preco))
             / count(*) filter (where preco is not null), 1) end,
      'pct_grade_quebrada', case when count(*) filter (where tem_grade) > 0
        then round(100.0 * count(*) filter (where quebrada)
             / count(*) filter (where tem_grade), 1) end,
      'pct_esgotada', 0,
      'preco_min', min(preco),
      'preco_max', max(preco),
      'preco_mediana', percentile_cont(0.5) within group (order by preco),
      'percentil_do_alvo', case
        when $3 is null or count(*) filter (where preco is not null) = 0 then null
        else round(100.0 * count(*) filter (where preco is not null and preco <= $3)
             / count(*) filter (where preco is not null), 0) end,
      'exibidos', least((select teto from parametros), count(*))
    ) as j from sim
  ), ordenado as (
    select *, row_number() over (
      partition by marca order by dimensoes_em_comum desc, em_comum desc, id
    ) as posicao_na_marca
    from sim
  ), amostra as (
    select jsonb_agg(jsonb_build_object(
      'id', id, 'marca', marca, 'papel_da_marca', papel_da_marca,
      'titulo', titulo, 'url', url, 'imagem', imagem,
      'preco', preco, 'preco_de', preco_de,
      'queda_pct', case when preco_de is not null and preco is not null
                         and preco_de > 0 and preco < preco_de
                    then round(100.0 * (preco_de - preco) / preco_de, 1) end,
      'em_comum', em_comum,
      'termos_em_comum', to_jsonb(termos_em_comum),
      'grade', public.grade_em_texto(ultima_grade))
      order by dimensoes_em_comum desc, em_comum desc, posicao_na_marca, id) as j
    from (
      select * from ordenado
      order by dimensoes_em_comum desc, em_comum desc, posicao_na_marca, id
      limit (select teto from parametros)
    ) t
  )
  select jsonb_build_object(
    'resumo', (select j from resumo),
    'pecas', coalesce((select j from amostra), '[]'::jsonb));
$function$;

create or replace function public.similares_da_peca_amplo(
  termos text[], limite integer default 12, preco_alvo numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  estrita jsonb;
  ampliada jsonb;
  dimensao_a_relaxar text;
  termos_reduzidos text[];
  dimensoes_originais integer;
  atributos_originais integer;
begin
  select count(*)::integer, count(distinct t.dimensao)::integer
    into atributos_originais, dimensoes_originais
  from unnest(coalesce(termos, '{}'::text[])) e(id)
  join public.termos t on t.id = e.id and t.status = 'aprovado';

  estrita := public.similares_da_peca(termos, limite, preco_alvo);
  if jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) >= least(limite, 8) then
    return estrita;
  end if;

  select t.dimensao into dimensao_a_relaxar
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> 'categoria'
  group by t.dimensao
  order by array_position(
    array['estetica','comprimento','silhueta','cintura','tecido','cor','estampa'],
    t.dimensao) nulls last, min(e.posicao)
  limit 1;
  if dimensao_a_relaxar is null then return estrita; end if;

  select array_agg(e.id order by e.posicao)
    into termos_reduzidos
  from unnest(coalesce(termos, '{}'::text[])) with ordinality e(id, posicao)
  join public.termos t on t.id = e.id and t.status = 'aprovado'
  where t.dimensao <> dimensao_a_relaxar;
  if cardinality(termos_reduzidos) = 0 then return estrita; end if;

  ampliada := public.similares_da_peca(termos_reduzidos, limite, preco_alvo);
  if jsonb_array_length(coalesce(ampliada->'pecas', '[]'::jsonb)) <=
     jsonb_array_length(coalesce(estrita->'pecas', '[]'::jsonb)) then
    return estrita;
  end if;
  ampliada := jsonb_set(ampliada, '{resumo,atributos_pedidos}',
                        to_jsonb(atributos_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensoes_pedidas}',
                        to_jsonb(dimensoes_originais), true);
  ampliada := jsonb_set(ampliada, '{resumo,dimensao_relaxada}',
                        to_jsonb(dimensao_a_relaxar), true);
  return ampliada;
end;
$function$;

grant execute on function public.similares_da_peca(text[], integer, numeric)
  to anon, authenticated;
grant execute on function public.similares_da_peca_amplo(text[], integer, numeric)
  to anon, authenticated;
