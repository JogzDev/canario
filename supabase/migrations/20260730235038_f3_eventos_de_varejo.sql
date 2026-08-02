-- §23: os eventos que o documento chama de sinal mais forte do painel.
--
-- Nota sobre a gravacao por delta (B3): snapshot so e escrito quando algo muda,
-- entao linhas consecutivas de um produto JA SAO as mudancas. Nao e preciso
-- reconstruir a serie diaria para comparar.
create or replace function computar_eventos()
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  total integer := 0;
  n integer;
begin
  -- ---------------------------------------------------------------------
  -- REMARCACAO: queda de preco de pelo menos 5% (K4).
  -- Abaixo disso e arredondamento e cupom, nao decisao comercial.
  -- ---------------------------------------------------------------------
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

  -- ---------------------------------------------------------------------
  -- REPOSICAO: tamanho indisponivel que volta e PERSISTE (§23, debounce de
  -- 2+ snapshots). "E a marca votando com o proprio dinheiro" -- por isso
  -- vale mais que ruptura, e por isso o debounce importa: um retorno de um
  -- snapshot so pode ser correcao de catalogo, nao decisao de compra.
  -- ---------------------------------------------------------------------
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
      -- persistencia: continua disponivel no snapshot seguinte, ou nao ha
      -- seguinte ainda (e ai o evento so entra quando houver).
      and (l.grade_seguinte -> t.key) = 'true'::jsonb
  )
  insert into eventos (produto_id, tipo, data, detalhe)
  select v.produto_id, 'reposicao', v.data,
         jsonb_build_object(
           'tamanhos', jsonb_agg(v.tamanho),
           'regra', '§23: indisponivel -> disponivel persistente por 2+ snapshots (debounce)')
  from voltas v
  where not exists (select 1 from eventos e
                     where e.produto_id = v.produto_id and e.tipo = 'reposicao'
                       and e.data = v.data)
  group by v.produto_id, v.data;
  get diagnostics n = row_count; total := total + n;

  -- ---------------------------------------------------------------------
  -- SAIDA DE LINHA: produto sem aparecer ha 14 dias (K1), E SO SE a marca
  -- dele continuou coletando. Sem essa condicao, uma queda do site viraria
  -- saida de linha em massa -- que e exatamente o que o K1 previne.
  -- ---------------------------------------------------------------------
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
$$;

comment on function computar_eventos is
  '§23: remarcacao (K4, >=5%), reposicao (debounce 2+ snapshots) e saida de linha (K1, 14 dias com a marca coletando).';;
