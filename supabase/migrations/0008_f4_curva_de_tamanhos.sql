-- 0008 -- Curva de tamanhos (§24), o marco de demo 1.
--
-- É o achado que a cliente relatou em entrevista: a grade quebrando concentrada
-- nos tamanhos menores. Este arquivo o transforma em número medido.
--
-- ===========================================================================
-- O PROBLEMA QUE DECIDIU O MÉTODO
-- ===========================================================================
--
-- Cada marca escreve tamanho na sua própria escada, e o MESMO RÓTULO significa
-- degraus diferentes. Medido no painel em 01/08:
--
--   Hering : XP · P · M · G · XG · XXG      (não existe PP nem GG)
--   Zinzane: PP · P · M · G · GG · XG · XGG (XG fica ACIMA do GG)
--
-- Em Hering, `XG` é o maior tamanho corrente, o equivalente do GG das outras.
-- Em Zinzane, `XG` é um degrau ALÉM do GG. Uma tabela global rótulo → tamanho
-- seria demonstravelmente errada, e converter 38 para M seria pior ainda: a
-- equivalência número↔letra varia de marca para marca e não temos como aferir.
--
-- Então nada é convertido entre marcas nem entre sistemas. O que se faz é:
--
--   1. ordenar os rótulos DENTRO da grade de cada produto, por uma ordem
--      canônica que só precisa estar certa como ORDEM, nunca como equivalência;
--   2. converter cada tamanho na sua POSIÇÃO RELATIVA naquela grade (0 = o menor
--      que a marca oferece, 1 = o maior);
--   3. agrupar em três faixas — menores, meio, maiores.
--
-- Numa grade de cinco degraus isso recorta exatamente o que a §24 pede:
-- menores = PP/P, meio = M, maiores = G/GG. E funciona igual na Hering, que tem
-- outra escada, sem que ninguém precise afirmar que XP "é" PP.
--
-- A leitura por rótulo ("P contra G") também existe, mas só para as grades da
-- escada padrão {PP,P,M,G,GG}, e isso fica marcado na linha. É a única forma de
-- nomear tamanho sem misturar significados.
--
-- ===========================================================================
-- O QUE É MEDIDO, E O QUE NÃO É
-- ===========================================================================
--
-- Não vemos profundidade de estoque. Vemos disponível/indisponível por tamanho,
-- por dia. Daí saem duas medidas, e a escolha entre elas MUDOU o resultado:
--
--   `taxa_quebra` -- MEDIDA PRINCIPAL. Dos pares (produto, tamanho) que estavam
--       DISPONÍVEIS quando a janela abriu, quantos ficaram indisponíveis até o
--       fim. É quebra observada.
--
--   `share_indisponivel` -- CONTEXTO. A foto do estado de hoje.
--
-- A primeira versão deste arquivo usava a FOTO como manchete, porque tem N
-- maior. Estava contrariando a §23, que é explícita: "Usar dinâmica (velocidade
-- de quebra, percentual da grade ao longo do tempo), **nunca a foto de um
-- dia**". E as duas medidas discordam de verdade — não é detalhe de precisão:
--
--   pela foto      : GG é o que mais quebra (62,5%), curva em U
--   pela dinâmica  : P é o que mais quebra (3,57%), e GG é o que menos (2,16%)
--
-- A foto carrega toda a indisponibilidade antiga e a profundidade de compra da
-- marca, que não observamos: como se compra menos GG e menos PP, as pontas
-- aparecem esgotadas por construção. A dinâmica pergunta outra coisa — do que
-- estava no ar, o que saiu — e é essa que responde à §24.
--
-- Não é velocidade. A §24 fala em "velocidade relativa de esgotamento", e com
-- 8 dias de janela isso não é aferível — chamar de velocidade seria afirmar o
-- que não foi medido (regra 2). O nome usado é o que a coisa é: taxa de saída.
--
-- Grades com menos de 3 degraus ficam de fora: não têm curva, têm um par.

-- ---------------------------------------------------------------------------
-- Ordem canonica dos rotulos.
--
-- Serve SO para ordenar dentro da grade de um produto. Que `XG` valha 8 e `GG`
-- valha 7 e verdade na Zinzane e inofensivo na Hering, que nao tem GG -- em
-- nenhum dos dois casos se afirma que o XG de uma e o XG da outra.
--
-- O mesmo esta em `coletor/tamanhos.py`, que e onde os testes rodam.
-- ---------------------------------------------------------------------------
create or replace function public.ordem_do_tamanho(bruto text)
returns table (sistema text, rotulo text, ordem numeric)
language sql immutable
set search_path to 'public', 'pg_temp'
as $$
  with limpo as (
    select upper(btrim(coalesce(bruto, ''))) as t
  ),
  -- PatBo escreve US/BR junto ("XS/PP", "4/36"). O lado BR e o que interessa.
  -- "34BR/36EU" e numeracao de calcado e fica de fora inteira.
  br as (
    select case
             when t ~ '^[A-Z0-9]+/[A-Z0-9]+$' and t !~ 'BR|EU'
               then split_part(t, '/', 2)
             else t
           end as t
    from limpo
  ),
  -- `000` existe no catalogo e `ltrim('000','0')` devolve string vazia, que
  -- estoura na conversao para numeric. O nullif fecha o caso, e um tamanho sem
  -- digito nenhum nao e tamanho.
  norm as (
    select t, case when t ~ '^0*\d+$' then nullif(ltrim(t, '0'), '') else null end as digitos
    from br
  )
  select
    case
      when t in ('XPP','XP','PP','P','M','G','GG','XG','XGG','XXG','EXG') then 'letra'
      when digitos is not null and digitos::numeric between 30 and 69 then 'br_numerico'
      else null
    end,
    coalesce(digitos, t),
    case t
      when 'XPP' then 1 when 'XP' then 2 when 'PP' then 3 when 'P' then 4
      when 'M'   then 5 when 'G'  then 6 when 'GG' then 7 when 'XG' then 8
      when 'XGG' then 9 when 'XXG' then 10 when 'EXG' then 11
      else digitos::numeric
    end
  from norm;
$$;

comment on function public.ordem_do_tamanho is
  'Rotulo de tamanho -> (sistema, rotulo limpo, ordem). A ordem serve APENAS '
  'para ordenar dentro da grade de um produto: o mesmo rotulo significa degraus '
  'diferentes em marcas diferentes (XG e o maior da Hering e um degrau alem do '
  'GG na Zinzane), entao nada aqui equivale tamanho entre marcas.';

-- ---------------------------------------------------------------------------
-- Onde a curva mora.
-- ---------------------------------------------------------------------------
create table if not exists public.curva_tamanhos (
  id              bigserial primary key,
  -- NULL = painel inteiro; preenchido = a curva daquele atributo.
  termo_id        text references public.termos(id) on delete cascade,
  segmento        text not null,
  semana          date not null,
  sistema         text not null,          -- 'letra' | 'br_numerico'
  faixa           text not null,          -- 'menores' | 'meio' | 'maiores'
  -- NULL = agregado da faixa. Preenchido = detalhe por rotulo, so na escada padrao.
  rotulo          text,
  n_grades        integer not null,
  n_pares         integer not null,
  n_indisponivel  integer not null,
  n_em_risco      integer not null default 0,
  n_quebrou       integer not null default 0,
  taxa_quebra     numeric,
  share_indisponivel numeric,
  meta            jsonb,
  computado_em    timestamptz not null default now()
);

comment on column public.curva_tamanhos.taxa_quebra is
  'MEDIDA PRINCIPAL (§23: usar dinamica, nunca a foto de um dia). Dos pares '
  '(produto, tamanho) que estavam DISPONIVEIS no inicio da janela, quantos '
  'ficaram indisponiveis ate o fim.';

comment on column public.curva_tamanhos.share_indisponivel is
  'MEDIDA DE CONTEXTO. Foto do estado atual. A §23 proibe le-la como sinal de '
  'sucesso: carrega toda a indisponibilidade antiga e a profundidade de compra '
  'da marca, que nao observamos.';

create unique index if not exists curva_tamanhos_chave
  on public.curva_tamanhos (termo_id, segmento, semana, sistema, faixa, rotulo)
  nulls not distinct;

create index if not exists curva_tamanhos_busca
  on public.curva_tamanhos (segmento, semana desc, termo_id);

alter table public.curva_tamanhos enable row level security;

-- O app le; ninguem escreve pela chave publishable (a escrita e do service_role,
-- que ignora RLS).
drop policy if exists curva_tamanhos_leitura on public.curva_tamanhos;
create policy curva_tamanhos_leitura on public.curva_tamanhos
  for select to anon, authenticated using (true);


-- ---------------------------------------------------------------------------
-- O calculo.
-- ---------------------------------------------------------------------------
create or replace function public.computar_curva_tamanhos(janela_dias integer default 14)
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
  semana_alvo date;
begin
  select (max(data) - ((extract(isodow from max(data))::int) - 1)) into semana_alvo
  from snapshots;
  if semana_alvo is null then return 0; end if;

  create temp table _curva_base on commit drop as
  with bruto as (
    select p.id as produto_id, p.segmento,
           t.key as tam_bruto, (t.value = 'true'::jsonb) as disponivel
    from produtos p
    cross join lateral jsonb_each(coalesce(p.ultima_grade, '{}'::jsonb)) t
    where p.segmento is not null
  ),
  -- Portao de qualidade: so o que o normalizador reconhece. E ele que descarta
  -- a grade da Amaro, que veio com nome de COR no lugar de tamanho (bug do
  -- coletor Shopify, corrigido em 01/08 -- o dado velho fica no banco ate a
  -- proxima coleta residencial).
  normalizado as (
    select b.produto_id, b.segmento, b.disponivel, o.sistema, o.rotulo, o.ordem
    from bruto b
    cross join lateral public.ordem_do_tamanho(b.tam_bruto) o
    where o.sistema is not null and o.ordem is not null
  ),
  -- Uma grade = (produto, sistema). Produto que mistura letra e numero entra
  -- duas vezes, cada uma na sua propria escada: sao duas grades na mesma peca.
  grade as (
    select produto_id, segmento, sistema,
           count(*) as degraus,
           count(*) filter (where disponivel) as disponiveis,
           bool_and(rotulo = any (array['PP','P','M','G','GG'])) as escada_padrao
    from normalizado
    group by produto_id, segmento, sistema
  ),
  quebrando as (
    select * from grade where degraus >= 3
  ),
  -- Posicao relativa dentro da escada DA PROPRIA GRADE.
  posicionado as (
    select n.produto_id, n.segmento, n.disponivel, n.sistema, n.rotulo,
           q.escada_padrao,
           (rank() over (partition by n.produto_id, n.sistema order by n.ordem) - 1)::numeric
             / nullif(q.degraus - 1, 0) as posicao
    from normalizado n
    join quebrando q on q.produto_id = n.produto_id and q.sistema = n.sistema
  )
  select produto_id, segmento, disponivel, sistema, rotulo, escada_padrao,
         case when posicao <= 1.0/3 then 'menores'
              when posicao >= 2.0/3 then 'maiores'
              else 'meio' end as faixa
  from posicionado;

  -- Risco e quebra na janela. `no_inicio` e o denominador: so pode quebrar o
  -- que estava disponivel quando a janela abriu.
  create temp table _curva_janela on commit drop as
  with historico as (
    select s.produto_id, t.key as tam_bruto,
           first_value(t.value = 'true'::jsonb) over w as no_inicio,
           last_value (t.value = 'true'::jsonb) over w as no_fim
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

  -- `termo_id` nulo e a linha do painel inteiro, e sai da MESMA base para os
  -- dois numeros serem comparaveis.
  create temp table _curva_com_termo on commit drop as
  select b.*, pt.termo_id from _curva_base b
  join produto_termos pt on pt.produto_id = b.produto_id
  union all
  select b.*, null::text from _curva_base b;

  with juntado as (
    select c.*, coalesce(j.no_inicio, false) as em_risco,
           coalesce(j.quebrou, false) as quebrou
    from _curva_com_termo c
    left join _curva_janela j
      on j.produto_id = c.produto_id and j.sistema = c.sistema and j.rotulo = c.rotulo
  ),
  -- Dois graos na mesma passagem: agregado da faixa (rotulo nulo) e detalhe por
  -- rotulo, este so na escada padrao, onde nomear tamanho nao mistura sentido.
  agregado as (
    select termo_id, segmento, sistema, faixa, null::text as rotulo,
           count(distinct produto_id) as n_grades,
           count(*) as n_pares,
           count(*) filter (where not disponivel) as n_indisponivel,
           count(*) filter (where em_risco) as n_em_risco,
           count(*) filter (where quebrou) as n_quebrou,
           false as so_padrao
    from juntado group by termo_id, segmento, sistema, faixa
    union all
    select termo_id, segmento, sistema, faixa, rotulo,
           count(distinct produto_id), count(*),
           count(*) filter (where not disponivel),
           count(*) filter (where em_risco),
           count(*) filter (where quebrou),
           true
    from juntado where escada_padrao
    group by termo_id, segmento, sistema, faixa, rotulo
  )
  insert into curva_tamanhos
    (termo_id, segmento, semana, sistema, faixa, rotulo,
     n_grades, n_pares, n_indisponivel, n_em_risco, n_quebrou,
     taxa_quebra, share_indisponivel, meta)
  select
    a.termo_id, a.segmento, semana_alvo, a.sistema, a.faixa, a.rotulo,
    a.n_grades, a.n_pares, a.n_indisponivel, a.n_em_risco, a.n_quebrou,
    round(100.0 * a.n_quebrou / nullif(a.n_em_risco, 0), 2),
    round(100.0 * a.n_indisponivel / nullif(a.n_pares, 0), 2),
    jsonb_build_object(
      'principal', 'taxa_quebra: dos tamanhos disponiveis no inicio da janela, quantos ficaram indisponiveis',
      'contexto', 'share_indisponivel e a foto de hoje; a §23 proibe le-la como sinal',
      'posicao', 'faixa pela posicao relativa DENTRO da grade do proprio produto; nada e convertido entre marcas',
      'escada_padrao', a.so_padrao,
      'janela_dias', janela_dias,
      'ressalva_profundidade', 'nao observamos quantidade em estoque; marca costuma comprar menos nas pontas da grade, e isso sozinho ja acelera a quebra em PP e GG',
      'computado_em', now()
    )
  from agregado a
  where a.n_pares >= 1
  on conflict (termo_id, segmento, semana, sistema, faixa, rotulo) do update
    set n_grades = excluded.n_grades, n_pares = excluded.n_pares,
        n_indisponivel = excluded.n_indisponivel,
        n_em_risco = excluded.n_em_risco, n_quebrou = excluded.n_quebrou,
        taxa_quebra = excluded.taxa_quebra,
        share_indisponivel = excluded.share_indisponivel,
        meta = excluded.meta, computado_em = now();

  get diagnostics linhas = row_count;
  return linhas;
end;
$function$;

comment on function public.computar_curva_tamanhos is
  'Curva de tamanhos da §24. Mede onde a grade quebra, por posicao relativa '
  'dentro da escada de cada produto -- nunca convertendo tamanho entre marcas.';
