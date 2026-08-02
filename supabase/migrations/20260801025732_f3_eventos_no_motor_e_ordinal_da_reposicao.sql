create or replace function public.computar_eventos()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  total integer := 0;
  n integer;
begin
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
      and (l.grade_anterior -> t.key) = 'false'::jsonb
      and t.value = 'true'::jsonb
      and (l.grade_seguinte -> t.key) = 'true'::jsonb
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
           'regra', 'K1: 14 dias ausente COM a marca coletando; sem essa condicao uma queda de site viraria saida de linha em massa')
  from ultima_por_produto u
  join marca_saudavel m on m.marca_id = u.marca_id
  where (m.coletou_em - u.visto_em) >= 14
    and not exists (select 1 from eventos e
                     where e.produto_id = u.produto_id and e.tipo = 'saida_de_linha');
  get diagnostics n = row_count; total := total + n;

  return total;
end;
$function$;

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
  row_number() over (partition by e.produto_id, e.tipo order by e.data, e.id) as ordinal,
  nullif(e.data - min(e.data) over (partition by e.produto_id, e.tipo), 0) as dias_desde_a_primeira
from eventos e
join produtos p on p.id = e.produto_id
join marcas   m on m.id = p.marca_id
where p.segmento is not null;

comment on view public.eventos_da_semana is
  'Eventos da §23 legiveis pelo app. `ordinal` conta as ocorrencias do mesmo tipo para o mesmo produto ao longo de todo o historico: a 3a reposicao do mesmo tamanho em dois meses e um sinal muito mais forte que a 1a, e sem o ordinal as duas apareciam iguais na tela.';

grant select on public.eventos_da_semana to anon, authenticated;;
