-- A62: a curva de tamanhos so com o que esta na vitrine.
--
-- O QUE ESTAVA ERRADO
-- ===================
--
-- `computar_curva_tamanhos` (P0) montava a base com todo produto que ja
-- existiu: `produtos` com segmento e `ultima_grade`, sem olhar quando a peca
-- foi vista pela ultima vez. O coletor so reescreve `ultima_grade` de quem ele
-- ve; a grade de quem saiu do site fica congelada no ultimo dia, e a curva a
-- lia como se fosse de hoje. `share_indisponivel` -- "a foto de hoje" -- e as
-- faixas contavam estoque morto.
--
-- Medido em 23/09/2026, com a coleta do dia em andamento:
--
--   segmento               base hoje   base nova   share_indisponivel
--   feminino_casual_br        81.620      28.811       74,8% -> 43,2%
--   catalogo_candidato_br     18.882      14.055       43,8% -> 33,8%
--   direcao_intl               2.754       2.540       26,6% -> 21,3%
--
-- No feminino, as ligacoes termo x produto caem de 230.176 para 73.948. A
-- `taxa_quebra`, a manchete, quase nao se move (6,06% -> 6,09%): peca morta
-- nao tem snapshot na janela, entao nunca entrava "em risco". O defeito mora
-- na foto de hoje e no tamanho das grades, que o app mostra.
--
-- A BASE NOVA
-- ===========
--
-- Tres condicoes, todas sobre o produto:
--
-- 1. Visto nos sete dias ate o ultimo dia observado do PROPRIO segmento. E a
--    tolerancia de sete dias que vale para o resto do painel (P17, A27), com
--    a ancora da A57: pausa de coleta nao e ausencia de mercado.
-- 2. Fora do catalogo aposentado numa troca de plataforma (A61). Hoje sao os
--    322 produtos antigos da Amaro ainda dentro da janela.
-- 3. A venda hoje, ou a venda em algum snapshot da janela da curva.
--
-- POR QUE A TERCEIRA CONDICAO NAO E SO "OFERTAVEL HOJE"
-- ====================================================
--
-- A raridade (A27) define o estado atual como ofertavel e visto em sete
-- dias. Para a curva isso tira da base exatamente a peca que esgotou DENTRO
-- da janela -- que e a propria quebra. Medido no feminino: a taxa cairia de
-- 6,09% para 5,31%, 775 quebras a menos. Vies de sobrevivencia na manchete.
--
-- E por que nao "tudo que esta listado": 83% das pecas listadas da PatBo
-- estao esgotadas em todos os tamanhos, 70% da Dress To, 62% da Hering;
-- Zinzane, Animale e Morena Rosa ficam perto de zero. Umas lojas mantem a
-- pagina da peca esgotada, outras tiram. Contar essa vitrine faria o share
-- medir a politica de cada site, nao o mercado.
--
-- A peca que esteve a venda em algum dia da janela e o meio-termo: entra quem
-- esgotou agora, sai quem esgotou ha meses e continua pendurado no site.
--
-- POR QUE A ANCORA NAO E O MARCADOR PUBLICADO DA A57
-- =================================================
--
-- `observacoes_publicadas_do_painel` e a data que a TELA declara. Aqui ela
-- nao serve:
--
-- * o motor calcula a curva ANTES de avancar o marcador (A58, A60), entao a
--   curva ficaria sempre uma publicacao atras;
-- * o catalogo candidato esta com o marcador em 25/08 e o dado em 21/09, e
--   `direcao_intl` nao tem marcador;
-- * o teto `<= observado_em` da A57 congela o relogio, nao a grade:
--   `ultima_grade` ja e a do lote novo. Com o teto, o feminino cairia de
--   42 mil para 3.908 produtos.
--
-- A ancora e o ultimo dia em que o segmento foi observado, e a idade viaja em
-- `meta.base_observada_em`. Sem teto em current_date, como a `semana_alvo`,
-- que tambem vem do dado: base e janela concordam sobre o "agora".
--
-- AS LINHAS DA SEMANA CORRENTE
-- ============================
--
-- O upsert nunca apagava combinacao que sumiu. Com a base encolhendo, uma
-- faixa ou rotulo que so existia no estoque morto continuaria na semana com
-- o numero velho. A semana alvo passa a ser substituida inteira. As semanas
-- anteriores NAO sao reescritas: foram publicadas com a base de entao, e
-- serie publicada e historia (A61).
--
-- O QUE NAO MUDA
-- ==============
--
-- `semana_alvo`, a janela de quebra, as faixas pela posicao na grade, a
-- escada padrao, o contrato da tabela e as chaves de `meta` que ja existiam.
-- O retorno passa a somar linhas escritas e removidas, como a serie de
-- varejo.
--
-- ROLLBACK
-- ========
--
-- A funcao volta a P0, cujo corpo tem md5 265552fa6d57794bf3a9f3f3dcdad6b9
-- (conferido em producao em 23/09/2026). As linhas da semana corrente se
-- refazem na proxima execucao do motor.

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
  create temp table _curva_ancora on commit drop as
  select p.segmento, max(ep.ultimo_avistamento_em) as observado_em
  from produtos p
  join estado_dos_produtos ep on ep.produto_id = p.id
  where p.segmento is not null
  group by p.segmento;

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

  create temp table _curva_janela on commit drop as
  with historico as (
    select s.produto_id, t.key as tam_bruto,
           first_value(t.value = 'true'::jsonb) over w as no_inicio,
           last_value(t.value = 'true'::jsonb) over w as no_fim
    from snapshots s
    cross join lateral jsonb_each(coalesce(s.grade_por_tamanho, '{}'::jsonb)) t
    where s.data > (semana_alvo + 6) - janela_dias
    window w as (partition by s.produto_id, t.key order by s.data
                 rows between unbounded preceding and unbounded following)
  )
  select distinct h.produto_id, o.sistema, o.rotulo, h.no_inicio,
         (h.no_inicio and not h.no_fim) as quebrou
  from historico h
  cross join lateral public.ordem_do_tamanho(h.tam_bruto) o
  where o.sistema is not null and o.ordem is not null;
  create index on _curva_janela (produto_id, sistema, rotulo);

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
           'principal', 'taxa_quebra: dos tamanhos disponiveis no inicio da janela, quantos ficaram indisponiveis',
           'contexto', 'share_indisponivel e a foto de hoje; a §23 proibe le-la como sinal',
           'posicao', 'faixa pela posicao relativa DENTRO da grade do proprio produto; nada e convertido entre marcas',
           'escada_padrao', a.so_padrao, 'janela_dias', janela_dias,
           'ressalva_profundidade', 'nao observamos quantidade em estoque; marca costuma comprar menos nas pontas da grade, e isso sozinho ja acelera a quebra em PP e GG',
           'base', 'A62: visto nos 7 dias ate o ultimo dia observado do segmento, fora do catalogo aposentado, a venda hoje ou em algum dia da janela',
           'base_observada_em', an.observado_em,
           'computado_em', now())
  from _curva_nova a
  join _curva_ancora an on an.segmento = a.segmento
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
  'A62: curva de tamanhos sobre o que esta na vitrine -- visto nos 7 dias ate o ultimo dia observado do segmento, fora do catalogo aposentado, a venda hoje ou em algum dia da janela; a semana alvo e substituida inteira.';
