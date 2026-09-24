-- A68: a curva mede a janela que observou.
--
-- O QUE ESTAVA ERRADO
-- ===================
--
-- A quebra (A62 e antes) comparava a PRIMEIRA e a ULTIMA foto de cada tamanho
-- que caiam dentro da janela de 14 dias. Isso so funciona se ha foto todo
-- dia, e nao ha: o coletor grava foto quando algo muda na peca, ou no
-- batimento semanal (B3). Tres consequencias, todas medidas em 23/09/2026:
--
-- 1. Quando um tamanho esgota no meio da janela, a primeira foto de dentro
--    dela ja e a do tamanho esgotado, e a quebra some. Na janela de 19 a
--    23/09, no feminino: a regra antiga acha 1.614 quebras em 32.783
--    tamanhos em risco (4,92%); partindo da ultima foto ate o primeiro dia,
--    5.478 em 89.422 (6,13%).
-- 2. A janela nominal nao e a observada. De 03 a 17/09 nao houve coleta
--    nenhuma (banco a 96,9% travou as coletas). A semana de 14/09 foi medida
--    com 3 dias de fotos, deu 2,49% contra 6% a 9% das outras, e o app
--    escreveu "janela de 14 dias".
-- 3. O catalogo candidato teve UMA coleta saudavel na janela (21/09; as de
--    03, 07, 10 e 14/09 falharam). Com uma foto por peca, nenhum tamanho tinha
--    como quebrar, e o zero dele entrou na curva do app ate o PR #51.
--
-- A REGRA NOVA
-- ============
--
-- * Os dias que contam sao os de coleta SAUDAVEL de cada marca, lidos em
--   `saude` com o criterio de linha da A58/A60. Dia adiado, recusado ou
--   parcial nao e observacao.
-- * O estado de cada tamanho no primeiro e no ultimo desses dias e a ultima
--   foto ate o dia. No primeiro, a foto tem de ter no maximo seis dias (o
--   batimento garante isso para peca vista) e a peca tem de ter sido vista
--   dali em diante.
-- * Marca com um dia so de coleta nao tem janela: nada dela entra em risco.
--   O candidato sai da taxa sem lista de excecoes, e entra sozinho quando
--   passar a ser coletado todo dia (PR #58).
-- * Tamanho que sumiu da grade no fim fica fora da conta.
-- * A janela observada do segmento viaja em `meta.janela_observada`
--   (inicio, fim, dias, marcas), e o app a declara no lugar dos 14 dias.
--
-- O QUE NAO MUDA
-- ==============
--
-- A base da A62 (vitrine, ancora por segmento, catalogo aposentado, semana
-- alvo substituida inteira, semanas publicadas intocadas), as faixas, a
-- escada padrao, o contrato da tabela e as chaves de `meta` que ja existiam.
-- Peca que saiu do site no meio da janela continua com o estado da ultima
-- foto, como antes: limite conhecido, fora do escopo desta migration.
--
-- ROLLBACK
-- ========
--
-- A funcao volta a A62, cujo corpo tem md5 ba506554f5888563b2b760080c0e5e6c
-- (conferido em producao em 24/09/2026). A semana corrente se refaz na
-- proxima execucao do motor.

create or replace function public.computar_curva_tamanhos(janela_dias integer default 14)
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
  removidas integer;
  semana_alvo date;
begin
  select (max(data) - ((extract(isodow from max(data))::int) - 1)) into semana_alvo
  from snapshots;
  if semana_alvo is null then return 0; end if;

  -- O "agora" de cada segmento e o ultimo dia em que ele foi observado. Uma
  -- data unica deixaria o segmento de cadencia mais rapida reprovar o outro.
  -- Segmento sem observacao na janela da curva nao entra na semana: a foto
  -- dele e de outra semana, e fica na semana em que foi tirada.
  create temp table _curva_ancora on commit drop as
  select p.segmento, max(ep.ultimo_avistamento_em) as observado_em
  from produtos p
  join estado_dos_produtos ep on ep.produto_id = p.id
  where p.segmento is not null
  group by p.segmento
  having max(ep.ultimo_avistamento_em) > (semana_alvo + 6) - janela_dias;

  create temp table _curva_base on commit drop as
  with ativos as (
    -- So o que esta na vitrine: visto na semana do proprio segmento, fora do
    -- catalogo aposentado, e a venda hoje ou em algum dia da janela. A peca
    -- que esgotou dentro da janela E a quebra; tira-la apagaria a manchete.
    select p.id as produto_id, p.segmento, p.ultima_grade
    from produtos p
    join estado_dos_produtos ep on ep.produto_id = p.id
    join _curva_ancora a on a.segmento = p.segmento
    where ep.ultimo_avistamento_em >= a.observado_em - 7
      and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                       where ca.produto_id = p.id)
      and (ep.ofertavel is true
           or exists (select 1 from snapshots s
                       where s.produto_id = p.id
                         and s.data > (semana_alvo + 6) - janela_dias
                         and s.ofertavel is true))
  ),
  bruto as (
    select a.produto_id, a.segmento,
           t.key as tam_bruto, (t.value = 'true'::jsonb) as disponivel
    from ativos a
    cross join lateral jsonb_each(coalesce(a.ultima_grade, '{}'::jsonb)) t
  ),
  normalizado as (
    select b.produto_id, b.segmento, b.disponivel, o.sistema, o.rotulo, o.ordem
    from bruto b
    cross join lateral public.ordem_do_tamanho(b.tam_bruto) o
    where o.sistema is not null and o.ordem is not null
  ),
  grade as (
    select produto_id, segmento, sistema, count(*) as degraus,
           bool_and(rotulo = any (array['PP','P','M','G','GG'])) as escada_padrao
    from normalizado group by produto_id, segmento, sistema
  ),
  posicionado as (
    select n.produto_id, n.segmento, n.disponivel, n.sistema, n.rotulo,
           g.escada_padrao,
           (rank() over (partition by n.produto_id, n.sistema order by n.ordem) - 1)::numeric
             / nullif(g.degraus - 1, 0) as posicao
    from normalizado n join grade g using (produto_id, segmento, sistema)
    where g.degraus >= 3
  )
  select produto_id, segmento, disponivel, sistema, rotulo, escada_padrao,
         case when posicao <= 1.0/3 then 'menores'
              when posicao >= 2.0/3 then 'maiores' else 'meio' end as faixa
  from posicionado;
  create index on _curva_base (produto_id, sistema, rotulo);

  -- Os dias em que cada marca foi DE FATO observada na janela. O criterio e o
  -- da linha saudavel da A58/A60: visitou, nao declarou corte, e nao caiu
  -- abaixo de 30% da media positiva dos sete dias anteriores. Dia adiado,
  -- recusado ou parcial nao conta: nele, "nenhuma foto nova" nao quer dizer
  -- "nada mudou". Marca com um dia so nao tem janela -- nada a comparar.
  create temp table _curva_marca_janela on commit drop as
  with diarias as (
    select s.marca_id, s.data,
           coalesce(s.visitados, 0) as visitados,
           coalesce(s.alertas, '{}'::jsonb) as alertas
    from saude s
    where s.fonte = 'varejo'
      and s.marca_id is not null
      and s.data > (semana_alvo + 6) - janela_dias
      and s.data <= semana_alvo + 6
  ), observadas as (
    select l.marca_id, l.data
    from diarias l
    left join lateral (
      select avg(h.visitados::numeric) as media_positiva_7d
      from saude h
      where h.fonte = 'varejo'
        and h.marca_id = l.marca_id
        and h.data >= l.data - 7
        and h.data < l.data
        and coalesce(h.visitados, 0) > 0
    ) historico on true
    where l.visitados > 0
      and not (l.alertas ?| array['truncou', 'faixas_truncadas'])
      and (historico.media_positiva_7d is null
           or l.visitados::numeric >= historico.media_positiva_7d * 0.30)
  )
  select marca_id, min(data) as inicio, max(data) as fim
  from observadas
  group by marca_id
  having max(data) > min(data);

  -- A quebra compara o estado de cada tamanho no primeiro e no ultimo dia
  -- observado da marca. O coletor so grava foto quando algo muda, ou no
  -- batimento semanal (B3); entao o estado de um dia e a ULTIMA foto ate ele,
  -- e nao a primeira foto que cai dentro da janela. Com o batimento de sete
  -- dias, peca vista num dia tem foto de no maximo seis dias antes; mais
  -- velha que isso, a peca nao foi vista ali e fica fora da conta.
  create temp table _curva_janela on commit drop as
  with medidas as (
    select distinct b.produto_id, mj.inicio, mj.fim
    from _curva_base b
    join produtos p on p.id = b.produto_id
    join estado_dos_produtos ep on ep.produto_id = b.produto_id
    join _curva_marca_janela mj on mj.marca_id = p.marca_id
    where ep.ultimo_avistamento_em >= mj.inicio
  ), no_inicio as (
    select distinct on (m.produto_id)
           m.produto_id, m.fim, s.grade_por_tamanho as grade
    from medidas m
    join snapshots s on s.produto_id = m.produto_id
    where s.data <= m.inicio
      and s.data > m.inicio - 7
    order by m.produto_id, s.data desc
  ), no_fim as (
    select distinct on (i.produto_id)
           i.produto_id, s.grade_por_tamanho as grade
    from no_inicio i
    join snapshots s on s.produto_id = i.produto_id
    where s.data <= i.fim
    order by i.produto_id, s.data desc
  )
  -- Tamanho que sumiu da grade no fim tem estado final desconhecido: fica
  -- fora da conta, em vez de virar quebra ou permanencia por palpite.
  select distinct i.produto_id, o.sistema, o.rotulo,
         (t.value = 'true'::jsonb) as no_inicio,
         (t.value = 'true'::jsonb and f.grade -> t.key <> 'true'::jsonb) as quebrou
  from no_inicio i
  join no_fim f using (produto_id)
  cross join lateral jsonb_each(coalesce(i.grade, '{}'::jsonb)) t
  cross join lateral public.ordem_do_tamanho(t.key) o
  where o.sistema is not null and o.ordem is not null
    and coalesce(f.grade, '{}'::jsonb) ? t.key;
  create index on _curva_janela (produto_id, sistema, rotulo);

  -- A janela que o segmento de fato observou, para a tela declarar em vez de
  -- prometer os 14 dias nominais.
  create temp table _curva_janela_do_segmento on commit drop as
  select b.segmento, min(mj.inicio) as inicio, max(mj.fim) as fim,
         count(distinct mj.marca_id) as marcas
  from (select distinct produto_id, segmento from _curva_base) b
  join produtos p on p.id = b.produto_id
  join _curva_marca_janela mj on mj.marca_id = p.marca_id
  group by b.segmento;

  create temp table _curva_nova on commit drop as
  with juntado as materialized (
    select b.*, coalesce(j.no_inicio, false) as em_risco,
           coalesce(j.quebrou, false) as quebrou
    from _curva_base b
    left join _curva_janela j using (produto_id, sistema, rotulo)
  ),
  por_termo as not materialized (
    select pt.termo_id, c.*
    from juntado c
    join produto_termos pt on pt.produto_id = c.produto_id
  ),
  agregado as (
    select termo_id, segmento, sistema, faixa, null::text as rotulo,
           count(distinct produto_id) as n_grades, count(*) as n_pares,
           count(*) filter (where not disponivel) as n_indisponivel,
           count(*) filter (where em_risco) as n_em_risco,
           count(*) filter (where quebrou) as n_quebrou, false as so_padrao
    from por_termo group by termo_id, segmento, sistema, faixa
    union all
    select termo_id, segmento, sistema, faixa, rotulo,
           count(distinct produto_id), count(*),
           count(*) filter (where not disponivel),
           count(*) filter (where em_risco), count(*) filter (where quebrou), true
    from por_termo where escada_padrao
    group by termo_id, segmento, sistema, faixa, rotulo
    union all
    select null::text, segmento, sistema, faixa, null::text,
           count(distinct produto_id), count(*),
           count(*) filter (where not disponivel),
           count(*) filter (where em_risco), count(*) filter (where quebrou), false
    from juntado group by segmento, sistema, faixa
    union all
    select null::text, segmento, sistema, faixa, rotulo,
           count(distinct produto_id), count(*),
           count(*) filter (where not disponivel),
           count(*) filter (where em_risco), count(*) filter (where quebrou), true
    from juntado where escada_padrao
    group by segmento, sistema, faixa, rotulo
  )
  select * from agregado where n_pares >= 1;

  -- A semana alvo e refeita inteira: combinacao que so existia no estoque
  -- morto sai, em vez de ficar com o numero velho. Semana anterior nao e
  -- tocada -- foi publicada com a base de entao.
  delete from public.curva_tamanhos c
  where c.semana = semana_alvo
    and not exists (
      select 1 from _curva_nova n
      where n.termo_id is not distinct from c.termo_id
        and n.segmento = c.segmento
        and n.sistema = c.sistema
        and n.faixa = c.faixa
        and n.rotulo is not distinct from c.rotulo);
  get diagnostics removidas = row_count;

  insert into curva_tamanhos
    (termo_id, segmento, semana, sistema, faixa, rotulo,
     n_grades, n_pares, n_indisponivel, n_em_risco, n_quebrou,
     taxa_quebra, share_indisponivel, meta)
  select a.termo_id, a.segmento, semana_alvo, a.sistema, a.faixa, a.rotulo,
         a.n_grades, a.n_pares, a.n_indisponivel, a.n_em_risco, a.n_quebrou,
         round(100.0 * a.n_quebrou / nullif(a.n_em_risco, 0), 2),
         round(100.0 * a.n_indisponivel / nullif(a.n_pares, 0), 2),
         jsonb_build_object(
           'principal', 'taxa_quebra: dos tamanhos disponiveis no primeiro dia observado da marca na janela, quantos estavam indisponiveis no ultimo',
           'contexto', 'share_indisponivel e a foto de hoje; a §23 proibe le-la como sinal',
           'posicao', 'faixa pela posicao relativa DENTRO da grade do proprio produto; nada e convertido entre marcas',
           'escada_padrao', a.so_padrao, 'janela_dias', janela_dias,
           'ressalva_profundidade', 'nao observamos quantidade em estoque; marca costuma comprar menos nas pontas da grade, e isso sozinho ja acelera a quebra em PP e GG',
           'base', 'A62: visto nos 7 dias ate o ultimo dia observado do segmento, fora do catalogo aposentado, a venda hoje ou em algum dia da janela',
           'base_observada_em', an.observado_em,
           'janela', 'A68: estado no primeiro e no ultimo dia de coleta saudavel de cada marca, pela ultima foto ate cada dia; marca com um dia so nao entra em risco',
           'janela_observada', case when js.segmento is null then null
             else jsonb_build_object('inicio', js.inicio, 'fim', js.fim,
                                     'dias', js.fim - js.inicio,
                                     'marcas', js.marcas) end,
           'computado_em', now())
  from _curva_nova a
  join _curva_ancora an on an.segmento = a.segmento
  left join _curva_janela_do_segmento js on js.segmento = a.segmento
  on conflict (termo_id, segmento, semana, sistema, faixa, rotulo) do update
    set n_grades = excluded.n_grades, n_pares = excluded.n_pares,
        n_indisponivel = excluded.n_indisponivel,
        n_em_risco = excluded.n_em_risco, n_quebrou = excluded.n_quebrou,
        taxa_quebra = excluded.taxa_quebra,
        share_indisponivel = excluded.share_indisponivel,
        meta = excluded.meta, computado_em = now();

  get diagnostics linhas = row_count;
  return linhas + removidas;
end;
$function$;

-- `create or replace` preserva os privilegios; repetidos aqui para que a
-- migration se leia sozinha.
revoke all on function public.computar_curva_tamanhos(integer)
  from public, anon, authenticated;
grant execute on function public.computar_curva_tamanhos(integer) to service_role;

comment on function public.computar_curva_tamanhos(integer) is
  'A68: a quebra compara o primeiro e o ultimo dia de coleta saudavel de cada marca na janela, pela ultima foto ate cada dia, e a janela observada viaja em meta.janela_observada. Base da A62: visto nos 7 dias ate o ultimo dia observado do segmento, fora do catalogo aposentado, a venda hoje ou em algum dia da janela; a semana alvo e substituida inteira.';
