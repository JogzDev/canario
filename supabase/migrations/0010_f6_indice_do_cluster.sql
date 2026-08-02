-- 0010 -- Índice do cluster (§22, K5): o número da peça inteira.
--
-- ===========================================================================
-- O QUE A LEI PEDE, E POR QUE A FÓRMULA DELA NÃO SOBREVIVE A ESTE DADO
-- ===========================================================================
--
-- §22: "Índice do cluster (conjunto de atributos de uma peça) = média dos
--       índices dos atributos ponderada por raridade: atributos raros no
--       painel pesam mais (lógica IDF); 'vestido' pesa pouco, 'floral' pesa
--       muito."
--
-- Rodei o IDF cru — ln(N/df) sobre as 58.487 peças ligadas à taxonomia —
-- ANTES de escrever qualquer coisa. Ele devolve isto:
--
--     liso .......... 6,87   <- o MAIOR peso de toda a taxonomia
--     blusa e top ... 1,17
--
-- `liso` tem 61 peças. Não porque peça lisa seja rara: 90,7% das peças
-- (53.074 de 58.487) não têm NENHUM termo de estampa. As 61 são as que
-- escreveram a palavra no título. É raridade medida sobre não-medição, e
-- premiada com o maior peso do sistema.
--
-- Três defeitos. Cada correção tem procedência, e uma quarta tentativa foi
-- MEDIDA E DESCARTADA (está registrada abaixo, porque tentativa descartada
-- também é resultado).
--
-- ---------------------------------------------------------------------------
-- DEFEITO 1: o df é medido com taxa de detecção que depende da MARCA
-- ---------------------------------------------------------------------------
-- Isto tem nome na literatura: aprendizado com positivos e não-rotulados.
-- Elkan & Noto (KDD 2008) mostram que, se a probabilidade de um positivo ser
-- rotulado é uma constante c (hipótese SCAR), então p(s=1|x) = c·p(y=1|x) — o
-- viés é multiplicativo e a ordenação sobrevive. Quando c depende do exemplo
-- (caso SNAR, Bekker & Davis 2020), o resultado colapsa.
--
-- Medido no nosso painel, % de peças com algum termo de estampa detectado:
--
--     C&A ............ 14,2%   (26.867 peças)
--     Farm ............ 9,0%
--     PatBô ........... 4,8%
--     Le Lis Blanc .... 0,4%
--     Morena Rosa ..... 0,0%   (812 peças, e a marca vende estampa)
--
-- E a cor vai de 0,1% (Lança Perfume) a 88,6% (PatBô) — 900×, mesma
-- taxonomia, mesmo matcher. A detecção é função da convenção de nomenclatura
-- da marca, não da roupa. SNAR medido, não suposto.
--
-- **A consequência boa, e ela explica por que o resto do sistema sobrevive:**
-- um viés de detecção aproximadamente constante no tempo SE CANCELA no
-- z-score, porque z é desvio contra a própria história — o viés desloca a
-- média e a observação juntos. Ele NÃO se cancela no IDF, porque IDF é um
-- nível comparado ENTRE termos. Por isso `series_semanais` e
-- `indices_semanais` não precisam de conserto, e o peso de raridade precisa.
--
-- ---------------------------------------------------------------------------
-- DEFEITO 2: raridade global ignora a categoria, e a categoria manda
-- ---------------------------------------------------------------------------
-- O MAVE (Google Research, WSDM 2022, 2,2M produtos da Amazon) registra que
-- atributos são definidos POR CATEGORIA: alguns são gerais (Type, Style),
-- outros "apply to only a few categories".
--
-- Medido aqui:
--
--     jeans   dentro de `calça` .... 23,7%   |  dentro de `vestido` .... 1,8%
--     midi    dentro de `saia` ..... 35,8%   |  no painel inteiro ...... 9,7%
--     floral  dentro de `vestido` ... 4,9%   |  dentro de `calça` ...... 0,8%
--
-- **Vestido jeans é 13× mais raro que calça jeans**, e a fórmula global dá o
-- mesmo peso aos dois.
--
-- Efeito colateral que vale registrar: ao condicionar à categoria, o próprio
-- termo de categoria vira 100% do seu denominador e cai para o PISO do peso.
-- Ou seja, "vestido pesa pouco" — o exemplo escrito na §22 — sai de graça,
-- mas por um mecanismo diferente do que a §22 nomeou.
--
-- ---------------------------------------------------------------------------
-- DEFEITO 3: cardinalidade variável por dimensão (dívida registrada no C2)
-- ---------------------------------------------------------------------------
-- O changelog já registrava: "o IDF (K5) precisa lidar com cardinalidade
-- variável por dimensão". Medido, o tamanho do problema:
--
--     categoria ..... 8 termos, 98,5% das peças preenchidas
--     cor ........... 10 termos, 61,4%
--     comprimento .... 3 termos, 32,2%
--     estampa ........ 6 termos,  9,3%
--     cintura ........ 1 termo,   5,4%
--
-- Numa dimensão de 3 termos nada pode ser mais raro que ~1/3. E `cintura` tem
-- UM termo: 100% de quem a tem é `cintura_alta`, logo ela não distingue nada
-- — mas o IDF cru lhe dava 2,92, mais que a `vestido` (1,62).
--
-- Correção: df e denominador são ambos DENTRO da dimensão, e o prior é 1/k.
-- Com k=1, p=prior=1 e o peso cai para o piso ln(2). É o tratamento por campo
-- do BM25F (Robertson, Zaragoza & Taylor, CIKM 2004), que existe exatamente
-- porque campos não são comparáveis entre si.
--
-- ---------------------------------------------------------------------------
-- TENTATIVA DESCARTADA: sobredispersão de Pearson entre marcas
-- ---------------------------------------------------------------------------
-- O encolhimento (abaixo) conserta contagem baixa, mas NÃO conserta detecção
-- enviesada — são dois problemas, e eu tratei como um. Com o encolhimento
-- ligado, `liso` continuou o mais pesado (3,65), porque a dispersão entre os
-- termos de estampa é alta e o m empírico-bayesiano concluiu, corretamente
-- dentro da sua hipótese, que valia confiar no observado.
--
-- Testei então um índice de sobredispersão: para cada termo, a variação da
-- sua fatia ENTRE marcas comparada com a que a amostragem sozinha explicaria
-- (φ = χ²/gl, correção quase-verossimilhança de Wedderburn 1974). A ideia era
-- cortar o n efetivo dos termos medidos de forma inconsistente.
--
-- **Não discrimina.** Medido:
--
--     vestido ......... φ = 305      <- o MAIOR de todos
--     camisa .......... φ = 243
--     linho ........... φ = 209
--     listra .......... φ =  66
--     liso ............ nem entra no top 22
--
-- φ mede heterogeneidade de sortimento REAL — marcas de fato diferem no quanto
-- vendem vestido — e não separa isso de viés de detecção. Descartado. Fica
-- registrado para ninguém tentar de novo achando que é ideia nova.
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO QUE FUNCIONOU, E ELA JÁ ESTAVA ESCRITA NA TAXONOMIA
-- ---------------------------------------------------------------------------
-- O campo `motivo` do termo `liso` diz, desde a construção da taxonomia:
--
--     "Denominador da dimensão estampa: sem ele o share de floral perde base
--      de comparação"
--
-- `liso` nunca foi um atributo a medir. Foi posto lá como DENOMINADOR, e o
-- IDF transformou o denominador no atributo mais pesado do sistema. O mesmo
-- vale para `outras_cores`, cujo motivo é ainda mais explícito: "balde
-- residual... atribuído por exclusão pelo motor, nunca por casamento de
-- palavra".
--
-- Então entra `termos.papel`, espelhando `marcas.papel`, que já distingue
-- medição de direção. Um termo `denominador`:
--
--   * fica FORA do denominador da própria dimensão (senão mexe na fatia dos
--     outros por um número que não é medição);
--   * não conta para o k do prior (não é opção que o comprador escolhe);
--   * recebe o peso MÉDIO dos atributos medidos da sua dimensão — nem prior
--     (que depende de k, e k é arbitrário) nem zero (o termo TEM índice
--     válido vindo das pernas de busca e editorial; só a contagem no painel
--     é que não é medição).
--
-- Resultado: `liso` foi de 3,65 (o mais pesado do sistema) para 1,97 (o meio
-- da tabela). O topo virou `lilás e roxo` (2,1% das peças com cor), que é
-- raridade de verdade, medida onde a medição funciona.
--
-- ===========================================================================
-- A FÓRMULA, E DE ONDE VEM CADA PEDAÇO
-- ===========================================================================
--
--   p_observado = pecas(categoria, termo) / pecas(categoria, dimensão)
--   p_prior     = 1 / k          k = ATRIBUTOS da dimensão na taxonomia
--
--   λ = n / (m + n)              n = pecas(categoria, termo)
--   m = p̄(1-p̄) / τ²             p̄, τ² = média e variância dos p_observado
--                                 entre os termos daquela dimensão
--
--   p_ajustado = λ·p_observado + (1-λ)·p_prior
--   peso       = ln(1 + 1/p_ajustado)
--
-- O encolhimento é o de Micci-Barreca (SIGKDD Explorations 3(1), 2001), na
-- forma empírico-bayesiana implementada no `TargetEncoder` do scikit-learn:
-- λ = n/(m+n) com m = σ²/τ². Substitui o portão de preenchimento que eu ia
-- usar: um limiar é um penhasco arbitrário, isto degrada suavemente.
-- **Nenhum número escolhido a dedo entra aqui.**
--
-- O `1 +` dentro do log é a correção do Lucene. O IDF original de Robertson
-- vai NEGATIVO quando df > N/2 — Robertson (2004) chama isso de "a somewhat
-- odd prediction for a query term — that its presence should count against
-- retrieval". Globalmente nenhum termo nosso cruza 50%, mas ao condicionar à
-- categoria `jeans` dentro de `calça` está em 54,3% e `reta_wide` em 78,6%.
-- Kamphuis et al. (ECIR 2020) testaram 8 variantes de BM25 em 3 coleções TREC
-- e não acharam diferença significativa entre elas — mas registram que ainda
-- vale usar uma que não produza valor negativo. É a família ATIRE/Lucene.
--
-- ===========================================================================
-- HONESTIDADE SOBRE A FUNDAÇÃO
-- ===========================================================================
--
-- Spärck Jones (1972) propôs a especificidade do termo como HEURÍSTICA.
-- Robertson (2004) revisa as tentativas de fundamentá-la e mostra que as
-- derivações por Teoria da Informação são problemáticas; a justificativa boa
-- está no modelo probabilístico (RSJ), que é sobre discriminar documentos
-- RELEVANTES de não-relevantes.
--
-- O Canário não tem consulta nem conjunto relevante. Então a justificativa
-- probabilística não transfere — o que transfere é a intuição heurística.
-- Isso não invalida usar IDF; significa que a escolha se decide por
-- comportamento medido, e que este comentário não deve fingir princípio onde
-- há heurística.
--
-- ===========================================================================
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
-- ===========================================================================
--
-- Não cria estado do cluster. A §22 define estados (`em alta`, `em queda`,
-- `pico`, `estável`) para a série semanal de um TERMO, com a regra anti-ruído
-- de 2 semanas e 2 pernas concordando. Nada disso está definido para um
-- conjunto de atributos, e inventar seria a regra 2 ao contrário.
--
-- Não vira score. A §5 proíbe "probabilidade, score ou chance de sucesso de
-- peça" com todas as letras. O índice do cluster está na MESMA unidade do
-- índice do atributo (desvios da própria história) e responde "quanto este
-- conjunto de atributos se moveu", nunca "quanto esta peça vai vender".
--
-- Não afirma direção quando os atributos discordam. Devolve `dispersao` (o
-- desvio ponderado dos índices em torno da média) e `ha_direcao`, que só é
-- verdadeiro quando |índice| >= dispersão. Medido no caso real
-- vestido+floral+midi: índice -0,77 com dispersão 1,28, porque `vestido` está
-- em -3,10 e `floral` em +0,29. Chamar isso de "conjunto em queda" seria a
-- mesma falha da manchete da curva de tamanhos, corrigida em 01/08.

-- ---------------------------------------------------------------------------
-- Papel do termo. Espelha `marcas.papel`.
-- ---------------------------------------------------------------------------
alter table public.termos
  add column if not exists papel text not null default 'atributo';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'termos_papel_valido') then
    alter table public.termos
      add constraint termos_papel_valido check (papel in ('atributo','denominador'));
  end if;
end $$;

comment on column public.termos.papel is
  'atributo = medido por casamento de palavra. denominador = existe para dar '
  'base de comparacao (liso, outras_cores); nao recebe peso de raridade '
  'proprio porque sua contagem nao e medicao.';

update public.termos set papel = 'denominador' where id in ('liso','outras_cores');

-- ---------------------------------------------------------------------------
-- Tabela de raridade. Recomputada pelo motor, lida ao vivo pelo app.
-- §33: servidor calcula, app consulta. Contar df de 58 mil peças a cada
-- abertura de tela seria o oposto disso.
-- ---------------------------------------------------------------------------
create table if not exists public.raridade_do_atributo (
  categoria           text        not null,
  termo_id            text        not null,
  dimensao            text        not null,
  papel               text        not null default 'atributo',
  pecas               integer     not null,
  pecas_na_dimensao   integer     not null,
  termos_na_dimensao  integer     not null,
  p_observado         numeric,
  p_prior             numeric     not null,
  m                   numeric,
  lambda              numeric     not null,
  p_ajustado          numeric     not null,
  peso                numeric     not null,
  computado_em        timestamptz not null default now(),
  primary key (categoria, termo_id)
);

comment on table public.raridade_do_atributo is
  'Peso de raridade por (categoria, termo), §22/K5. Encolhido para o prior '
  '1/k quando a contagem e baixa (Micci-Barreca 2001). Forma nao-negativa '
  'ln(1+1/p), familia ATIRE/Lucene.';

alter table public.raridade_do_atributo enable row level security;

drop policy if exists "leitura publica da raridade" on public.raridade_do_atributo;
create policy "leitura publica da raridade"
  on public.raridade_do_atributo for select
  using (true);

-- ---------------------------------------------------------------------------
-- computar_raridade() -- entra no motor, ao lado de computar_indice().
-- ---------------------------------------------------------------------------
create or replace function public.computar_raridade()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
begin
  with
  cat as (
    select pt.produto_id, t.id as categoria
    from produto_termos pt
    join termos t on t.id = pt.termo_id
    where t.dimensao = 'categoria'
  ),
  universo as (
    select produto_id, categoria from cat
    union all
    select distinct produto_id, '(todas)' from produto_termos
  ),
  -- k conta so os ATRIBUTOS: o denominador nao e uma opcao que o comprador
  -- escolhe, e infla-lo rebaixaria o prior de todos.
  dims as (
    select dimensao, count(*) filter (where papel = 'atributo')::integer as k
    from termos group by dimensao
  ),
  categorias as (select distinct categoria from universo),
  -- Grade completa: toda categoria x todo termo. Sem isto, termo com zero
  -- observacoes numa categoria simplesmente sumiria, e sumir e pior que
  -- aparecer com peso de prior.
  grade as (
    select c.categoria, t.id as termo_id, t.dimensao, t.papel,
           greatest(d.k, 1) as termos_na_dimensao
    from categorias c
    cross join termos t
    join dims d on d.dimensao = t.dimensao
  ),
  df as (
    select u.categoria, pt.termo_id, count(distinct u.produto_id)::integer as pecas
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    group by 1, 2
  ),
  n_dim as (
    select u.categoria, t.dimensao,
           count(distinct u.produto_id)::integer as pecas_na_dimensao
    from universo u
    join produto_termos pt on pt.produto_id = u.produto_id
    join termos t on t.id = pt.termo_id
    where t.papel = 'atributo'
    group by 1, 2
  ),
  observado as (
    select g.categoria, g.termo_id, g.dimensao, g.papel, g.termos_na_dimensao,
           coalesce(df.pecas, 0) as pecas,
           coalesce(n.pecas_na_dimensao, 0) as pecas_na_dimensao,
           case when coalesce(n.pecas_na_dimensao, 0) > 0 and g.papel = 'atributo'
                then coalesce(df.pecas, 0)::numeric / n.pecas_na_dimensao
                else null end as p_observado,
           1.0::numeric / g.termos_na_dimensao as p_prior
    from grade g
    left join df    on df.categoria = g.categoria and df.termo_id = g.termo_id
    left join n_dim n on n.categoria = g.categoria and n.dimensao = g.dimensao
  ),
  -- Empirico-bayesiano: m = sigma2/tau2, com sigma2 = p(1-p) e tau2 a
  -- variancia dos p_observado ENTRE os termos daquela dimensao naquela
  -- categoria. tau2 nulo ou zero (dimensao de um termo so, ou todos
  -- igualmente frequentes) => m infinito => lambda=0 => tudo vai para o
  -- prior, que e o comportamento correto: nada a distinguir.
  momentos as (
    select categoria, dimensao,
           avg(p_observado) as p_barra, var_samp(p_observado) as tau2
    from observado where p_observado is not null group by 1, 2
  ),
  ajustado as (
    select o.*,
           case when mo.tau2 is null or mo.tau2 <= 0 then null
                else (mo.p_barra * (1 - mo.p_barra)) / mo.tau2 end as m
    from observado o
    left join momentos mo on mo.categoria = o.categoria and mo.dimensao = o.dimensao
  ),
  final as (
    select a.*,
           case when a.m is null or a.p_observado is null then 0::numeric
                else a.pecas::numeric / (a.m + a.pecas) end as lambda
    from ajustado a
  )
  insert into raridade_do_atributo
    (categoria, termo_id, dimensao, papel, pecas, pecas_na_dimensao,
     termos_na_dimensao, p_observado, p_prior, m, lambda, p_ajustado, peso,
     computado_em)
  select
    f.categoria, f.termo_id, f.dimensao, f.papel, f.pecas, f.pecas_na_dimensao,
    f.termos_na_dimensao, f.p_observado, f.p_prior, f.m, round(f.lambda, 6),
    round(calc.p_aj, 8),
    round(ln(1 + 1 / calc.p_aj)::numeric, 6),
    now()
  from final f
  cross join lateral (
    select greatest(
      f.lambda * coalesce(f.p_observado, f.p_prior) + (1 - f.lambda) * f.p_prior,
      1e-6) as p_aj
  ) calc
  on conflict (categoria, termo_id) do update
    set dimensao = excluded.dimensao, papel = excluded.papel,
        pecas = excluded.pecas, pecas_na_dimensao = excluded.pecas_na_dimensao,
        termos_na_dimensao = excluded.termos_na_dimensao,
        p_observado = excluded.p_observado, p_prior = excluded.p_prior,
        m = excluded.m, lambda = excluded.lambda,
        p_ajustado = excluded.p_ajustado, peso = excluded.peso,
        computado_em = now();

  get diagnostics linhas = row_count;

  update raridade_do_atributo r
     set peso = coalesce(med.peso_medio, r.peso),
         lambda = 0,
         p_ajustado = r.p_prior
    from (select categoria, dimensao, avg(peso) as peso_medio
            from raridade_do_atributo
           where papel = 'atributo'
           group by 1, 2) med
   where r.papel = 'denominador'
     and med.categoria = r.categoria
     and med.dimensao = r.dimensao;

  return linhas;
end;
$function$;

-- ---------------------------------------------------------------------------
-- indice_do_cluster(termos) -- chamada ao vivo pelo app.
--
-- `security definer` pelo mesmo motivo da §29: o `anon` nao enxerga
-- `produto_termos` nem `produtos`, e nao deve passar a enxergar. A funcao e
-- uma JANELA CONTROLADA -- devolve o indice de um conjunto que o usuario ja
-- digitou, e nada mais. Medido: 56ms com 6 atributos, contra o
-- `statement_timeout` de 3s do papel `anon`.
-- ---------------------------------------------------------------------------
create or replace function public.indice_do_cluster(termos text[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  categoria_da_peca text;
  n_categorias      integer;
begin
  if termos is null or array_length(termos, 1) is null then
    return jsonb_build_object('erro', 'nenhum atributo informado');
  end if;

  -- A categoria manda na raridade. Com mais de uma marcada (ou nenhuma), cai
  -- no universo '(todas)': misturar denominadores de categorias diferentes
  -- daria um numero que nao e de nenhuma delas.
  select count(*), min(t.id) into n_categorias, categoria_da_peca
  from termos t
  where t.id = any(indice_do_cluster.termos) and t.dimensao = 'categoria';

  if coalesce(n_categorias, 0) <> 1 then
    categoria_da_peca := '(todas)';
  end if;

  return (
  with
  ultimo as (
    select distinct on (i.termo_id)
           i.termo_id, i.indice, i.estado, i.semana, i.pernas_ativas, i.n_pernas
    from indices_semanais i
    where i.termo_id = any(indice_do_cluster.termos)
    order by i.termo_id, i.semana desc
  ),
  com_cobertura as (
    select u.*, coalesce(c.suficiente, true) as cobertura_ok
    from ultimo u
    left join cobertura_por_celula c
      on c.termo_id = u.termo_id and c.semana = u.semana
  ),
  -- Todo atributo pedido aparece na saida, inclusive os que nao entram --
  -- regra 6: dizer o que nao se sabe, no lugar onde a pessoa procuraria.
  pedido as (
    select t.id as termo_id, t.rotulo, t.dimensao, t.papel,
           r.peso, r.pecas, r.p_observado,
           cc.indice, cc.estado, cc.semana, cc.pernas_ativas, cc.n_pernas,
           case
             when cc.indice is null   then 'sem leitura neste recorte'
             when not coalesce(cc.cobertura_ok, false)
                                      then 'cobertura insuficiente (§8)'
             when r.peso is null      then 'sem raridade computada'
             else null
           end as fora_por
    from termos t
    left join raridade_do_atributo r
      on r.termo_id = t.id and r.categoria = categoria_da_peca
    left join com_cobertura cc on cc.termo_id = t.id
    where t.id = any(indice_do_cluster.termos)
  ),
  somas as (
    select coalesce(sum(peso), 0)          as soma_w,
           coalesce(sum(peso * peso), 0)   as soma_w2,
           coalesce(sum(peso * indice), 0) as soma_wz,
           count(*)::integer               as n_atributos
    from pedido where fora_por is null
  ),
  media as (
    select s.*, case when s.soma_w > 0 then s.soma_wz / s.soma_w end as indice
    from somas s
  ),
  -- Dispersao ponderada: o quanto os atributos DISCORDAM entre si. Um indice
  -- de -0,77 com atributos em -3,10 e +0,29 nao e leitura de nada.
  espalhamento as (
    select m.*,
      (select case when m.soma_w > 0 and m.n_atributos > 1
                then sqrt(sum(p.peso * (p.indice - m.indice) ^ 2) / m.soma_w)
              end
         from pedido p where p.fora_por is null) as desvio
    from media m
  )
  select jsonb_build_object(
    'categoria_usada', categoria_da_peca,
    'indice',      round(e.indice, 4),
    'dispersao',   round(e.desvio, 4),
    -- Tamanho efetivo de amostra de Kish: (Sw)^2/Sw^2. Diz quantos atributos
    -- REALMENTE sustentam o numero. Se um carrega quase todo o peso, isto cai
    -- para perto de 1 e o "indice do conjunto" e um atributo so usando roupa
    -- de conjunto.
    'atributos_efetivos',
        round((e.soma_w ^ 2) / nullif(e.soma_w2, 0), 2),
    'n_atributos', e.n_atributos,
    'ha_direcao',  case when e.n_atributos = 0 then false
                        when e.n_atributos = 1 then true
                        else abs(e.indice) >= coalesce(e.desvio, 0) end,
    'unidade', 'desvios-padrao da propria historia de cada atributo (§21)',
    'metodo',  'media dos indices ponderada por raridade dentro da dimensao e '
               || 'da categoria, com encolhimento para o prior em contagem '
               || 'baixa (§22, K5)',
    'atributos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'termo_id', p.termo_id,
        'rotulo',   p.rotulo,
        'dimensao', p.dimensao,
        'papel',    p.papel,
        'indice',   p.indice,
        'estado',   p.estado,
        'semana',   p.semana,
        'pernas',   p.pernas_ativas,
        'peso',     round(p.peso, 4),
        'peso_relativo', case when e.soma_w > 0 and p.fora_por is null
                              then round(p.peso / e.soma_w, 4) end,
        'pecas_no_painel', p.pecas,
        'pct_na_dimensao', round(100 * p.p_observado, 1),
        'fora_por', p.fora_por
      ) order by (p.fora_por is not null), p.peso desc nulls last), '[]'::jsonb)
      from pedido p
    )
  )
  from espalhamento e);
end;
$function$;

revoke all on function public.indice_do_cluster(text[]) from public;
grant execute on function public.indice_do_cluster(text[]) to anon, authenticated;

comment on function public.indice_do_cluster(text[]) is
  'Indice do cluster (§22/K5). Janela controlada: devolve o numero do '
  'conjunto que o usuario digitou, sem abrir produtos nem produto_termos.';
