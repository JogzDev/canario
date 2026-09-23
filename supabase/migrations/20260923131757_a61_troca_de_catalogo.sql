-- A61: troca de catalogo sem inventar eventos.
--
-- O QUE ACONTECEU
-- ===============
--
-- Entre 22 e 23/09/2026 a Amaro saiu da Shopify e foi para a Nuvemshop. O
-- `/products.json` passou a responder 404 e o portao de saude bloqueou a
-- publicacao do painel -- corretamente: zero por erro desconhecido.
--
-- A loja continua no ar, com ~360 produtos, e o coletor passa a ler a
-- Nuvemshop pelo sitemap e pelas paginas publicas. Mas cada produto ganhou
-- outro identificador, e so metade manteve o endereco: os sufixos -1, -2 que
-- a Shopify acrescentava sumiram. Nao ha chave publica que ligue um catalogo
-- ao outro. O endereco antigo so redireciona quando o slug e identico, e
-- responde 404 nos outros.
--
-- POR QUE NAO CASAR OS DOIS CATALOGOS
-- ===================================
--
-- Casar por titulo ou por slug parecido transformaria diferenca de cadastro
-- entre plataformas -- preco com ou sem desconto, grade renomeada -- em
-- remarcacao e reposicao da Amaro: uma manchete falsa na capa, o pior defeito
-- que o metodo pode ter. O catalogo novo comeca do zero. A primeira leitura e
-- a base, e os eventos voltam a nascer da comparacao com ela: remarcacao a
-- partir da segunda leitura, reposicao (que pede confirmacao) da terceira.
--
-- O QUE A TROCA FARIA SEM ESTA MIGRATION
-- ======================================
--
-- 1. Saida de linha em massa. Em 07/10, catorze dias depois, os produtos do
--    catalogo antigo virariam `saida_de_linha` (K1: ausente 14 dias com a
--    marca coletando). Nao sairam de linha; mudaram de endereco.
-- 2. Amaro contada duas vezes no denominador por ate sete dias: o
--    `sortimento_observado` vale o ultimo snapshot da janela de 7 dias (P17),
--    e os dois catalogos cabem nela. A taxa "de cada 100 pecas" da Amaro
--    cairia pela metade sem nada ter acontecido.
-- 3. A mesma contagem dupla na semana da troca da serie de varejo: o antigo
--    esteve presente na segunda e na terca, o novo de quarta em diante. A
--    semana vira historico permanente quando a poda leva o cru.
--
-- O QUE MUDA
-- ==========
--
-- * `trocas_de_catalogo` registra a troca: marca, data, de, para, motivo.
-- * `produtos_de_catalogo_aposentado`: produto da marca que trocou e que nao
--   foi visto desde a troca. Nada e apagado. Os eventos que o catalogo antigo
--   ja produziu aconteceram de verdade e continuam valendo.
-- * a saida de linha ignora o catalogo aposentado;
-- * o denominador diario ignora o aposentado a partir do dia da troca;
-- * a serie semanal conta so o catalogo novo na semana da troca;
-- * `marcas.plataforma` e `marcas.status_teste` aceitam 'nuvemshop'.
--
-- O QUE FICA DE PROPOSITO COMO ESTA
-- =================================
--
-- `estado_dos_produtos` registra o que foi visto: o aposentado foi visto
-- ofertavel em 22/09, e reescrever isso mentiria sobre aquele dia. As
-- leituras do app (similares, busca por link) e a raridade ja tiram da vitrine
-- quem nao aparece ha sete dias -- a mesma tolerancia que vale para qualquer
-- peca retirada de qualquer marca. Metade dos enderecos antigos redireciona
-- para a pagina nova, porque o slug se manteve.
--
-- NENHUM snapshot, evento ou serie ja publicada e reescrito. As semanas antes
-- da troca continuam com o catalogo antigo, que era o real naquela data.
--
-- ROLLBACK
-- ========
--
-- As tres funcoes voltam as versoes anteriores, cujos corpos tem md5
-- 74dfb12f4daabdef361c819f67b7a181 (computar_eventos, F3),
-- ba4a8becc4c1d29c4a9f14b3e8b87dac (sortimento_observado, A58) e
-- 8739a2ea5ddda51cee76b9603fe2ba7b (computar_serie_varejo, P22). A tabela, a
-- view e as restricoes podem ficar: sem as funcoes, nada as le.

alter table public.marcas drop constraint if exists marcas_plataforma_check;
alter table public.marcas add constraint marcas_plataforma_check
  check (plataforma in ('vtex', 'shopify', 'nuvemshop'));
alter table public.marcas drop constraint if exists marcas_status_teste_check;
alter table public.marcas add constraint marcas_status_teste_check
  check (status_teste in ('pendente', 'vtex', 'shopify', 'nuvemshop',
                          'falhou', 'nao_se_aplica'));

create table if not exists public.trocas_de_catalogo (
  marca_id bigint not null references public.marcas(id),
  em date not null,
  de text not null,
  para text not null,
  motivo text not null,
  registrado_em timestamptz not null default now(),
  primary key (marca_id, em),
  check (de <> para)
);

alter table public.trocas_de_catalogo enable row level security;
alter table public.trocas_de_catalogo force row level security;
revoke all on public.trocas_de_catalogo from public, anon, authenticated;
grant select on public.trocas_de_catalogo to service_role;

comment on table public.trocas_de_catalogo is
  'A61: marca que trocou de plataforma e, com ela, de identificadores de produto. `em` e o primeiro dia do catalogo novo; o que nao foi visto desde entao pertence ao catalogo aposentado. Registrar por migration, com o motivo.';

insert into public.trocas_de_catalogo (marca_id, em, de, para, motivo)
select m.id, date '2026-09-23', 'shopify', 'nuvemshop',
       '/products.json respondeu 404 em 23/09/2026 e o robots.txt passou a declarar a Nuvemshop; ~360 produtos com identificadores novos e metade dos slugs mudados'
from public.marcas m
where m.nome = 'Amaro'
on conflict (marca_id, em) do nothing;

do $$
begin
  if not exists (select 1 from public.trocas_de_catalogo t
                   join public.marcas m on m.id = t.marca_id
                  where m.nome = 'Amaro' and t.em = date '2026-09-23') then
    raise exception 'A61: troca da Amaro nao registrada; marca ausente?';
  end if;
end $$;

-- A primeira troca depois do ultimo avistamento aposenta o produto. Um
-- produto visto depois da troca e, por definicao, do catalogo vigente.
create or replace view public.produtos_de_catalogo_aposentado
with (security_invoker = true) as
select distinct on (p.id)
  p.id as produto_id,
  t.marca_id,
  t.em as aposentado_em
from public.trocas_de_catalogo t
join public.produtos p on p.marca_id = t.marca_id
join public.estado_dos_produtos ep on ep.produto_id = p.id
where ep.ultimo_avistamento_em < t.em
order by p.id, t.em;

revoke all on public.produtos_de_catalogo_aposentado from public, anon, authenticated;
grant select on public.produtos_de_catalogo_aposentado to service_role;

comment on view public.produtos_de_catalogo_aposentado is
  'A61: produtos de uma marca que trocou de catalogo e nao foram vistos desde a troca. Nao sairam de linha e nao sao mais sortimento; o historico deles continua valendo.';

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
                     where e.produto_id = u.produto_id and e.tipo = 'saida_de_linha')
    -- A61: o catalogo aposentado numa troca de plataforma nao saiu de linha;
    -- a mesma roupa segue a venda sob outro identificador.
    and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                     where ca.produto_id = u.produto_id);
  get diagnostics n = row_count; total := total + n;

  return total;
end;
$function$;

create or replace function public.sortimento_observado(alvo date)
returns table (marca_id bigint, segmento text, pecas_ofertadas integer)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with ultimo as (
    -- P17: o snapshot vale por sete dias, nao para sempre. Quem nao foi
    -- observado dentro da janela nao entra no denominador daquele dia.
    select distinct on (s.produto_id) s.produto_id, s.ofertavel
    from public.snapshots s
    where s.data between alvo - 6 and alvo
    order by s.produto_id, s.data desc
  )
  select p.marca_id, p.segmento, count(*)::int
  from ultimo u
  join public.produtos p on p.id = u.produto_id
  where u.ofertavel is true
    and p.segmento is not null
    -- A61: a partir do dia da troca, o catalogo aposentado nao e sortimento.
    -- Sem isto a marca conta duas vezes enquanto os dois cabem na janela.
    and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                     where ca.produto_id = u.produto_id
                       and ca.aposentado_em <= alvo)
  group by p.marca_id, p.segmento;
$function$;

create or replace function public.computar_serie_varejo()
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer := 0;
  removidas integer := 0;
begin
  create temp table _serie_varejo_nova (
    termo_id text not null,
    segmento text not null,
    semana date not null,
    valor_bruto numeric not null,
    n_amostra integer not null,
    n_total integer not null,
    dimensao text not null,
    n_dimensao integer not null,
    cobertura_dimensao_pct numeric not null,
    primary key (termo_id, segmento, semana)
  ) on commit drop;

  insert into _serie_varejo_nova
    (termo_id, segmento, semana, valor_bruto, n_amostra, n_total,
     dimensao, n_dimensao, cobertura_dimensao_pct)
  with semanas as (
    select distinct
      (s.data - ((extract(isodow from s.data)::int) - 1)) as semana
    from public.snapshots s
  ),
  estados as (
    select
      s.produto_id,
      p.segmento,
      s.data as inicio,
      least(
        coalesce(
          lead(s.data) over (partition by s.produto_id order by s.data) - 1,
          ep.ultimo_avistamento_em),
        ep.ultimo_avistamento_em,
        s.data + 6
      ) as fim,
      s.ofertavel,
      ca.aposentado_em
    from public.snapshots s
    join public.produtos p on p.id = s.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    left join public.produtos_de_catalogo_aposentado ca on ca.produto_id = p.id
    where p.segmento is not null
      and ep.ultimo_avistamento_em is not null
  ),
  presenca as (
    select distinct
      w.semana, e.produto_id, e.segmento
    from semanas w
    join estados e
      on e.ofertavel is true
     and e.inicio <= w.semana + 6
     and e.fim >= w.semana
     -- A61: na semana da troca vale so o catalogo novo. O antigo esteve la
     -- nos dias anteriores a ela, e contar os dois pesaria a marca em dobro.
     and (e.aposentado_em is null or w.semana + 6 < e.aposentado_em)
  ),
  total_semana as (
    select semana, segmento, count(distinct produto_id)::integer as n_total
    from presenca
    group by semana, segmento
  ),
  por_termo as (
    select pr.semana, pr.segmento, pt.termo_id, t.dimensao,
           count(distinct pr.produto_id)::integer as n
    from presenca pr
    join public.produto_termos pt on pt.produto_id = pr.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.status = 'aprovado'
    group by pr.semana, pr.segmento, pt.termo_id, t.dimensao
  ),
  por_dimensao as (
    select pr.semana, pr.segmento, t.dimensao,
           count(distinct pr.produto_id)::integer as n_dimensao
    from presenca pr
    join public.produto_termos pt on pt.produto_id = pr.produto_id
    join public.termos t on t.id = pt.termo_id
    where t.status = 'aprovado'
      and t.papel in ('atributo', 'denominador')
    group by pr.semana, pr.segmento, t.dimensao
  )
  select
    pt.termo_id,
    pt.segmento,
    pt.semana,
    round(100.0 * pt.n / nullif(ts.n_total, 0), 4),
    pt.n,
    ts.n_total,
    pt.dimensao,
    pd.n_dimensao,
    round(100.0 * pd.n_dimensao / nullif(ts.n_total, 0), 4)
  from por_termo pt
  join total_semana ts
    on ts.semana = pt.semana and ts.segmento = pt.segmento
  join por_dimensao pd
    on pd.semana = pt.semana and pd.segmento = pt.segmento
   and pd.dimensao = pt.dimensao;

  if not exists (select 1 from _serie_varejo_nova) then
    raise exception
      'serie de varejo vazia: nenhuma oferta observada; publicacao preservada';
  end if;

  -- So a janela ainda reconstruivel pode ser substituida. Sem este limite,
  -- podar o cru faria a proxima coleta apagar as semanas historicas prontas.
  delete from public.series_semanais s
  where s.fonte = 'varejo'
    and s.semana >= (select min(semana) from _serie_varejo_nova)
    and not exists (
      select 1 from _serie_varejo_nova n
      where n.termo_id = s.termo_id
        and n.segmento = s.segmento
        and n.semana = s.semana
    );
  get diagnostics removidas = row_count;

  insert into public.series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select
    n.termo_id,
    n.segmento,
    'varejo',
    n.semana,
    n.valor_bruto,
    null,
    n.n_amostra,
    jsonb_build_object(
      'metrica', 'share de ofertas observadas no sortimento do painel (%)',
      'n_total_sortimento', n.n_total,
      'dimensao', n.dimensao,
      'n_com_atributo_na_dimensao', n.n_dimensao,
      'cobertura_dimensao_pct', n.cobertura_dimensao_pct,
      'minimo_cobertura_dimensao_pct', 30,
      'semantica_presenca', 'ofertavel em ao menos um dia da semana, com confirmacao em intervalo de ate 7 dias',
      'legado_desconhecido_excluido', true,
      'obs', 'varejo descritivo, sem z-score por decisao B1',
      'computado_em', now()
    )
  from _serie_varejo_nova n
  on conflict (termo_id, segmento, fonte, semana) do update
    set valor_bruto = excluded.valor_bruto,
        z           = null,
        n_amostra   = excluded.n_amostra,
        meta        = excluded.meta
    -- P22: reescreve so quando um valor de negocio mudou. `computado_em` fica
    -- fora da comparacao porque e carimbo, nao medida: com ele dentro, toda
    -- linha pareceria diferente todo dia, que e o defeito que esta migration
    -- corrige. Comparacao por `is distinct from`, que trata nulo como valor.
    where series_semanais.valor_bruto is distinct from excluded.valor_bruto
       or series_semanais.z is not null
       or series_semanais.n_amostra is distinct from excluded.n_amostra
       or (series_semanais.meta - 'computado_em')
            is distinct from (excluded.meta - 'computado_em');

  get diagnostics linhas = row_count;
  return linhas + removidas;
end;
$function$;

-- `create or replace` preserva os privilegios; repetidos aqui para que a
-- migration se leia sozinha.
revoke all on function public.computar_eventos() from public, anon, authenticated;
grant execute on function public.computar_eventos() to service_role;
revoke all on function public.sortimento_observado(date) from public, anon, authenticated;
grant execute on function public.sortimento_observado(date) to service_role;
revoke all on function public.computar_serie_varejo() from public, anon, authenticated;
grant execute on function public.computar_serie_varejo() to service_role;

comment on function public.sortimento_observado(date) is
  'A58 + A61: sortimento ofertavel por (marca, segmento) no dia, pela janela de observacao de sete dias da P17, sem o catalogo aposentado depois da troca.';
