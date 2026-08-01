-- 0007 -- Eventos da §23: a funcao vira arquivo, e a view aprende a contar.
--
-- POR QUE ESTA MIGRACAO EXISTE
--
-- `computar_eventos()` foi criada direto no banco em 30/07 e nunca virou
-- arquivo nem entrou no `motor_computar.py`. Resultado: o PENDENCIAS.md
-- marcava K1 e K4 como feitos -- a funcao existe e esta correta -- mas nada
-- a chamava depois daquela vez. A tabela `eventos` congelou em 30/07 enquanto
-- as coletas seguiram gravando snapshot todo dia, e o app passou a mostrar
-- "Remarcacoes da semana" com o dado de anteontem.
--
-- E exatamente a classe de divida que o JP reclamou: decisao registrada,
-- codigo escrito, nada ligando os dois. A funcao passa a viver aqui, versionada
-- junto das outras, e o motor passa a chama-la todo dia (motor_computar.py).
--
-- O QUE MUDA DE COMPORTAMENTO
--
-- A view ganha o ordinal do evento por produto. O JP pediu "*1a reposicao" e
-- "*3a reposicao dos tamanhos PP/P em menos de 2 meses": a segunda frase e
-- muito mais forte que a primeira, porque repor tres vezes o mesmo tamanho em
-- dois meses e a marca dizendo que aquele tamanho vende. Sem o ordinal, as
-- duas apareciam iguais na tela.

-- ---------------------------------------------------------------------------
-- A funcao, identica a que ja roda no banco desde 30/07. Esta aqui para que
-- exista em arquivo; `create or replace` a torna idempotente.
-- ---------------------------------------------------------------------------
create or replace function public.computar_eventos()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  total integer := 0;
  n integer;
begin
  -- -------------------------------------------------------------------------
  -- REMARCACAO: queda de preco de pelo menos 5% (K4).
  -- Abaixo disso e arredondamento e cupom, nao decisao comercial.
  -- -------------------------------------------------------------------------
  with pares as (
    select produto_id, data, preco_atual,
           lag(preco_atual) over (partition by produto_id order by data) as anterior,
           lag(data)        over (partition by produto_id order by data) as data_anterior
    from snapshots
  )
  insert into eventos (produto_id, tipo, data, detalhe)
  select p.produto_id, 'remarcacao', p.data,
         jsonb_build_object(
           'preco_de', p.anterior, 'preco_para', p.preco_atual,
           'queda_pct', round(100.0 * (p.anterior - p.preco_atual) / p.anterior, 2),
           'desde', p.data_anterior,
           'regra', 'K4: queda >= 5%; abaixo disso e arredondamento, nao decisao')
  from pares p
  where p.anterior is not null and p.preco_atual is not null
    and p.anterior > 0
    and p.preco_atual < p.anterior
    and (p.anterior - p.preco_atual) / p.anterior >= 0.05
    and not exists (select 1 from eventos e
                     where e.produto_id = p.produto_id and e.tipo = 'remarcacao'
                       and e.data = p.data);
  get diagnostics n = row_count; total := total + n;

  -- -------------------------------------------------------------------------
  -- REPOSICAO: tamanho indisponivel que volta e PERSISTE (§23, debounce de
  -- 2+ snapshots). "E a marca votando com o proprio dinheiro" -- por isso
  -- vale mais que ruptura, e por isso o debounce importa: um retorno de um
  -- snapshot so pode ser correcao de catalogo, nao decisao de compra.
  --
  -- CONSEQUENCIA QUE A TELA PRECISA DECLARAR: a confirmacao exige uma segunda
  -- observacao, entao a reposicao mais recente que da para afirmar e sempre a
  -- de ontem. Isso nao e atraso de processamento, e o debounce funcionando.
  -- -------------------------------------------------------------------------
  with linhas as (
    select s.produto_id, s.data, s.grade_por_tamanho,
           lag(s.grade_por_tamanho) over (partition by s.produto_id order by s.data) as grade_anterior,
           lead(s.grade_por_tamanho) over (partition by s.produto_id order by s.data) as grade_seguinte
    from snapshots s
  ),
  voltas as (
    select l.produto_id, l.data, t.key as tamanho
    from linhas l
    cross join lateral jsonb_each(coalesce(l.grade_por_tamanho, '{}'::jsonb)) t
    where l.grade_anterior is not null
      and (l.grade_anterior -> t.key) = 'false'::jsonb   -- estava indisponivel
      and t.value = 'true'::jsonb                        -- voltou
      and (l.grade_seguinte -> t.key) = 'true'::jsonb    -- e continuou
  )
  insert into eventos (produto_id, tipo, data, detalhe)
  select v.produto_id, 'reposicao', v.data,
         jsonb_build_object(
           'tamanhos', jsonb_agg(v.tamanho order by v.tamanho),
           'regra', '§23: indisponivel -> disponivel persistente por 2+ snapshots (debounce)')
  from voltas v
  where not exists (select 1 from eventos e
                     where e.produto_id = v.produto_id and e.tipo = 'reposicao'
                       and e.data = v.data)
  group by v.produto_id, v.data;
  get diagnostics n = row_count; total := total + n;

  -- -------------------------------------------------------------------------
  -- SAIDA DE LINHA: produto sem aparecer ha 14 dias (K1), E SO SE a marca
  -- dele continuou coletando. Sem essa condicao, uma queda do site viraria
  -- saida de linha em massa -- que e exatamente o que o K1 previne.
  -- -------------------------------------------------------------------------
  with ultima_por_produto as (
    select p.id as produto_id, p.marca_id, max(s.data) as visto_em
    from produtos p join snapshots s on s.produto_id = p.id
    group by p.id, p.marca_id
  ),
  marca_saudavel as (
    select marca_id, max(data) as coletou_em
    from saude where fonte = 'varejo' and coalesce(visitados, 0) > 0
    group by marca_id
  )
  insert into eventos (produto_id, tipo, data, detalhe)
  select u.produto_id, 'saida_de_linha', m.coletou_em,
         jsonb_build_object(
           'ultimo_avistamento', u.visto_em,
           'dias_ausente', (m.coletou_em - u.visto_em),
           'regra', 'K1: 14 dias ausente COM a marca coletando; sem essa condicao '
                    'uma queda de site viraria saida de linha em massa')
  from ultima_por_produto u
  join marca_saudavel m on m.marca_id = u.marca_id
  where (m.coletou_em - u.visto_em) >= 14
    and not exists (select 1 from eventos e
                     where e.produto_id = u.produto_id and e.tipo = 'saida_de_linha');
  get diagnostics n = row_count; total := total + n;

  return total;
end;
$function$;

-- ---------------------------------------------------------------------------
-- A view, agora com a historia do produto junto do evento.
--
-- `ordinal` e `desde_a_primeira` sao o que permite a frase que o JP pediu:
-- "3a reposicao dos tamanhos PP/P em menos de 2 meses". A contagem e sobre
-- TODO o historico do produto, nao sobre a janela exibida -- senao a terceira
-- reposicao apareceria como primeira so porque a tela mostra 7 dias.
-- ---------------------------------------------------------------------------
drop view if exists public.eventos_da_semana;

create view public.eventos_da_semana as
select
  e.id,
  e.tipo,
  e.data,
  (e.data - ((extract(isodow from e.data))::integer - 1)) as semana,
  m.nome  as marca,
  m.papel as papel_da_marca,
  p.titulo as peca,
  p.url    as url_da_peca,
  p.segmento,
  p.ultimo_preco_atual,
  e.detalhe,
  -- Quantas vezes ja aconteceu isto com ESTE produto, contando esta.
  row_number() over (partition by e.produto_id, e.tipo order by e.data, e.id) as ordinal,
  -- Ha quantos dias foi a primeira vez. Nulo quando esta e a primeira.
  nullif(e.data - min(e.data) over (partition by e.produto_id, e.tipo), 0) as dias_desde_a_primeira
from eventos e
join produtos p on p.id = e.produto_id
join marcas   m on m.id = p.marca_id
where p.segmento is not null;

comment on view public.eventos_da_semana is
  'Eventos da §23 legiveis pelo app. `ordinal` conta as ocorrencias do mesmo '
  'tipo para o mesmo produto ao longo de todo o historico: a 3a reposicao do '
  'mesmo tamanho em dois meses e um sinal muito mais forte que a 1a, e sem o '
  'ordinal as duas apareciam iguais na tela.';

grant select on public.eventos_da_semana to anon, authenticated;
