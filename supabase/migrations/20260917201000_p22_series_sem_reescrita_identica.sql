-- P22: series_semanais so recebe versao nova quando um valor muda.
--
-- POR QUE
-- =======
--
-- Medido em 18/09/2026, em leitura, no banco de producao:
--
--   series_semanais   29.047 linhas vivas   22,6 MB de dado vivo
--                     heap de 73,8 MB  ->  30,6% do heap e dado
--                     2.728.348 updates acumulados, 24% HOT
--
-- Tres caminhos do motor reescrevem a tabela inteira a cada publicacao, mude
-- o valor ou nao:
--
--   computar_z                 as 29.047 linhas, todo dia
--   computar_serie_editorial   ate 17.242 linhas das pernas editoriais
--   computar_serie_varejo      as 423 linhas do varejo, com `computado_em`
--                              novo no meta mesmo quando nada mudou
--
-- Sao ate ~46,7 mil versoes novas por publicacao. O autovacuum as recupera DENTRO
-- da tabela, entao ela nao cresce sem fim -- ela estaciona no maior tamanho
-- que o pior dia exigiu. A P9 fez VACUUM FULL em 18/08 (48,2 -> 26,6 MiB) e
-- pos fillfactor 70; a tabela voltou a 73,8 MB porque a causa ficou. Esta
-- migration trata a causa. Sem ela, qualquer compactacao volta a ser comida
-- nas primeiras publicacoes depois que a coleta voltar.
--
-- O QUE MUDA, E SO ISSO
-- =====================
--
-- As expressoes de calculo sao as mesmas, copiadas sem alteracao, das funcoes
-- que rodam hoje em producao (o laboratorio confere, por hash de
-- `pg_get_functiondef`, que a versao de partida e a de producao em 18/09). O
-- que muda e o PREDICADO da escrita: cada caminho calcula o valor novo e so escreve a
-- linha em que ele difere do guardado, por `is distinct from` -- que trata
-- nulo como valor, entao "nulo antes, nulo depois" nao reescreve e "nulo
-- antes, 1,2 depois" reescreve.
--
-- O resultado final da tabela e identico ao de antes em todos os casos: a
-- linha que nao e escrita ja tinha o valor que receberia.
--
-- `computado_em` MUDA DE SENTIDO, E ISTO ESTA DECLARADO
-- ====================================================
--
-- No varejo, `meta.computado_em` era "a ultima vez que o motor passou por
-- aqui". Passa a ser "a ultima vez que este valor mudou". Nenhum consumidor
-- le a chave (conferido em coletor/, ferramentas/ e app/ em 18/09); a
-- informacao "o motor rodou" continua em `motor_execucoes` e no retorno de
-- `computar_motor`.
--
-- O retorno das tres funcoes passa a contar linhas ESCRITAS, nao linhas
-- visitadas. Reexecutar sem mudanca devolve 0 -- e esse zero e a prova de
-- que a prevencao esta funcionando, impressa pelo `motor_computar.py`.
--
-- O QUE ESTA FORA, E POR QUE
-- ==========================
--
-- `indices_semanais`, `curva_tamanhos` e `raridade_do_atributo` tem o mesmo
-- padrao (610.443 updates em 9.897 linhas no indice, medidos no mesmo dia) e
-- ficam para a proxima rodada: o escopo aprovado desta etapa e
-- `series_semanais`. Os upserts por REST dos coletores editorial e de busca
-- tambem ficam fora -- o editorial toca ~285 celulas por dia (as que tem
-- `coletado_em`), e a busca reescala a serie inteira do Google a cada coleta,
-- entao ali a mudanca de valor e real.
--
-- APLICACAO
-- =========
--
-- Timestamp anterior ao da A57 de proposito: esta migration entra antes dela
-- em producao. Ela nao precisa de espaco livre para ser aplicada -- substitui
-- tres funcoes, alguns KB de catalogo -- e nao reescreve nenhuma linha.
-- Precisa estar aplicada ANTES da primeira publicacao do motor depois de
-- qualquer compactacao; enquanto a coleta estiver parada, o motor nao roda e
-- nada reescreve `series_semanais`.

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
      s.ofertavel
    from public.snapshots s
    join public.produtos p on p.id = s.produto_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
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

create or replace function public.computar_serie_editorial()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  inseridas integer;
  ajustadas integer;
begin
  -- 1) MATERIALIZAR OS ZEROS.
  --
  -- Semana em que a perna coletou e o termo nao apareceu vale ZERO, e zero e
  -- medicao. Hoje ela nao existe como linha, e a janela do z-score so enxerga
  -- as semanas boas do termo: media inflada, desvio subestimado, z puxado para
  -- baixo. Medido em 02/08: z medio do editorial_br negativo em 13 de 13
  -- semanas, e `em alta` = 0 em toda semana desde 01/06.
  --
  -- O limite e' deliberado: so' se cria zero a partir da PRIMEIRA semana em que
  -- o termo ja tinha linha naquela perna. Antes disso nao se sabe se o termo
  -- estava sendo casado (a taxonomia mudou em 28/07 e 31/07), e afirmar zero
  -- onde nao houve medicao seria a regra 2 ao contrario.
  with coberta as (
    select distinct fonte, semana from denominador_editorial
  ),
  inicio as (
    select termo_id, segmento, fonte, min(semana) as primeira
    from series_semanais where fonte like 'editorial%'
    group by 1, 2, 3
  ),
  faltando as (
    select i.termo_id, i.segmento, i.fonte, c.semana
    from inicio i
    join coberta c on c.fonte = i.fonte and c.semana >= i.primeira
    where not exists (
      select 1 from series_semanais s
      where s.termo_id = i.termo_id and s.segmento = i.segmento
        and s.fonte = i.fonte and s.semana = c.semana)
  )
  insert into series_semanais (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select f.termo_id, f.segmento, f.fonte, f.semana, 0, null, 0,
         jsonb_build_object(
           'janela_semanas', 4,
           'contagem_semana_crua', 0,
           'unidade', 'materias por mil da perna, em janela de 4 semanas',
           'zero_materializado', true,
           'obs', 'semana em que a perna coletou e o termo nao apareceu. '
                  'Zero e medicao, nao ausencia.')
  from faltando f;
  get diagnostics inseridas = row_count;

  -- 2) SHARE OF VOICE DE VERDADE.
  --
  -- O coletor dividia por 4 -- o numero de SEMANAS da janela -- e chamava isso
  -- de share of voice. E contagem absoluta: quando o painel de veiculos cresce,
  -- todo termo sobe junto sem o mercado ter se mexido. Medido em 02/08: o
  -- denominador BR foi de ~460 para 896 materias (+90%) em uma semana, quando
  -- Marie Claire, Vogue Brasil e Glamour entraram.
  --
  -- Agora divide pelo total de materias da propria perna na mesma janela, em
  -- partes por mil para o numero continuar legivel. `n_amostra` segue sendo a
  -- contagem crua, que e o que a tela mostra e continua verdadeira.
  --
  -- P22: o valor e o meta sao os MESMOS de antes, calculados antes de
  -- escrever. So a linha em que um dos dois muda recebe versao nova; as
  -- outras ficam exatamente como estavam, inclusive fisicamente.
  with normalizada as (
    select s.id,
           round(1000.0 * coalesce(s.n_amostra, 0) / d.total_janela_4sem, 4)
             as valor_bruto,
           coalesce(s.meta, '{}'::jsonb) || jsonb_build_object(
             'unidade', 'materias por mil da perna, em janela de 4 semanas',
             'materias_da_perna_na_janela', d.total_janela_4sem,
             'obs_normalizacao',
               'share of voice: numerador e denominador na MESMA janela de 4 '
               'semanas. Antes o divisor era 4 (semanas), o que fazia o numero '
               'crescer quando o painel de veiculos crescia.') as meta
    from series_semanais s
    join denominador_editorial d
      on d.fonte = s.fonte and d.semana = s.semana
   where s.fonte like 'editorial%'
     and d.total_janela_4sem > 0
  )
  update series_semanais s
     set valor_bruto = n.valor_bruto,
         meta = n.meta
    from normalizada n
   where n.id = s.id
     and (s.valor_bruto is distinct from n.valor_bruto
          or s.meta is distinct from n.meta);
  get diagnostics ajustadas = row_count;

  return inseridas + ajustadas;
end;
$function$;

create or replace function public.computar_z()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  atualizadas integer;
begin
  with janela as (
    select
      s.id, s.fonte, s.valor_bruto, s.n_amostra,
      avg(s.valor_bruto) over w         as media,
      stddev_samp(s.valor_bruto) over w as desvio,
      count(*) over w                   as n_semanas
    from series_semanais s
    window w as (
      partition by s.termo_id, s.segmento, s.fonte
      order by s.semana
      -- 12 semanas de CALENDARIO, sem a semana corrente. Antes era
      -- `rows between 12 preceding`, que com a perna editorial em 30,6% de
      -- preenchimento cobria 29,2 semanas em media e ate 216 no pior caso,
      -- enquanto o app escrevia "media das ultimas 12 semanas" na tela.
      range between interval '84 days' preceding and interval '7 days' preceding
    )
  ), calculado as (
    select j.id,
           case
             when j.fonte = 'varejo' then null
             when j.n_semanas < (case when j.fonte like 'editorial%' then 6 else 8 end)
               then null
             -- §8 na perna editorial: sem materia suficiente na janela, nao ha
             -- z. Nulo declarado, nunca valor plausivel (regra 2).
             when j.fonte like 'editorial%' and coalesce(j.n_amostra, 0) < 10
               then null
             when j.desvio is null or j.desvio = 0 then null
             else round((j.valor_bruto - j.media) / j.desvio, 4)
           end as z
    from janela j
  )
  update series_semanais s
  set z = c.z
  from calculado c
  where c.id = s.id
    -- P22: a linha so ganha versao nova quando o z dela muda. Antes, as
    -- 29.047 linhas eram reescritas a cada publicacao, mudasse ou nao.
    and s.z is distinct from c.z;

  get diagnostics atualizadas = row_count;
  return atualizadas;
end;
$function$;
