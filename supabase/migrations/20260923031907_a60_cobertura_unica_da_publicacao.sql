-- A60: UMA REGRA SO PARA DIZER QUE O PAINEL ESTA COBERTO
-- =====================================================
--
-- Em 22/09/2026 a coleta completa rodou, o motor rodou e o painel nao
-- avancou: `observacoes_publicadas: 0`, relogio publico preso em 20/09 (run
-- 35722287583, issue #45). Duas regras diferentes respondiam a mesma pergunta,
-- "toda marca do segmento foi vista?":
--
-- * o portao Python (`alertas_criticos`, coletor/coletor_varejo.py) aceita a
--   Animale adiada por cadencia -- varredura integral semanal desde a PR #36 --
--   e aceita zero com recusa externa conhecida (http 429/5xx, robots) por
--   menos de `DIAS_DE_ZERO_PARA_BLOQUEAR` = 3 coletas seguidas;
-- * o portao SQL da A58 exigia `visitados > 0` de toda marca, todo dia.
--
-- Com a cadencia semanal o painel so poderia avancar um dia por semana; e no
-- proprio dia 22 a PatBo recebeu `http 429` do Shopify, recusa que o Python
-- tratou como aviso e o SQL como bloqueio. A regra passa a morar numa funcao
-- so, com a tolerancia do Python, e declara por marca o motivo de estar ou nao
-- coberta -- quem investigar um painel parado le o motivo em vez de deduzi-lo.
--
-- O QUE NAO MUDA
-- ==============
--
-- Continua reprovando: marca ativa sem linha de saude no dia, zero sem motivo,
-- zero com erro interno (inclusive 403, que nao e recusa de ritmo), catalogo
-- que declarou corte (`truncou`/`faixas_truncadas`) e queda critica -- volume
-- positivo abaixo de 30% da media positiva dos sete dias anteriores.
--
-- Marca adiada ou recusada so conta como coberta com observacao SAUDAVEL nos
-- sete dias anteriores, a mesma janela de presenca da P17. Nada e inventado
-- para o dia pulado: a marca nao ganha snapshot, evento nem avistamento, e
-- cada peca continua carregando a propria data (A57), de modo que a tela
-- declara a idade da ponta velha em vez de chamar a marca de atual.
--
-- A contagem de falhas ignora os dias de adiamento declarado. Adiar e plano;
-- falhar e acidente. Somar os seis dias de cadencia da Animale como "zeros"
-- faria uma unica recusa numa segunda-feira parecer a setima falha seguida.

create or replace function public.cobertura_de_publicacao(p_segmento text,
                                                          p_data date)
returns table (
  marca_id bigint,
  marca text,
  coberta boolean,
  motivo text,
  ultima_saudavel date,
  falhas_seguidas integer
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with esperadas as (
    -- A coorte operacional vem de `marcas.segmento`, como na A58: e ela que o
    -- coletor usa para decidir quem TEM de comparecer.
    select m.id, m.nome
    from public.marcas m
    where m.segmento = p_segmento
      and m.ativa is true
      and m.status_teste in ('vtex', 'shopify')
  ), linhas as (
    select s.marca_id, s.data,
           coalesce(s.visitados, 0) as visitados,
           coalesce(s.alertas, '{}'::jsonb) as alertas
    from public.saude s
    join esperadas e on e.id = s.marca_id
    where s.fonte = 'varejo'
      and s.data between p_data - 7 and p_data
  ), julgadas as (
    select l.marca_id, l.data, l.visitados, l.alertas,
           -- Saudavel: o mesmo criterio da A58, linha por linha.
           (l.visitados > 0
             and not (l.alertas ?| array['truncou', 'faixas_truncadas'])
             and (historico.media_positiva_7d is null
                  or l.visitados::numeric
                     >= historico.media_positiva_7d * 0.30)) as saudavel,
           -- Adiamento declarado pelo proprio coletor, nunca inferido.
           (l.visitados = 0
             and (coalesce((l.alertas->>'adiado_por_cadencia')::boolean, false)
                  or coalesce((l.alertas->>'adiado_por_capacidade')::boolean,
                               false))) as adiada,
           -- Mesma expressao de `recusa_conhecida` no Python.
           (l.visitados = 0
             and coalesce(l.alertas->>'erro', '')
                 ~* '\yhttp\s+(429|5[0-9]{2})\y|robots\s+proibe') as recusa
    from linhas l
    left join lateral (
      select avg(h.visitados::numeric) as media_positiva_7d
      from public.saude h
      where h.fonte = 'varejo'
        and h.marca_id = l.marca_id
        and h.data >= l.data - 7
        and h.data < l.data
        and coalesce(h.visitados, 0) > 0
    ) historico on true
  ), por_marca as (
    select e.id, e.nome,
           hoje.marca_id is not null as tem_linha,
           coalesce(hoje.saudavel, false) as saudavel_hoje,
           coalesce(hoje.adiada, false) as adiada_hoje,
           coalesce(hoje.recusa, false) as recusa_hoje,
           coalesce(hoje.visitados, 0) as visitados_hoje,
           coalesce(hoje.alertas, '{}'::jsonb) as alertas_hoje,
           anterior.data as ultima_saudavel
    from esperadas e
    left join julgadas hoje on hoje.marca_id = e.id and hoje.data = p_data
    left join lateral (
      select max(j.data) as data
      from julgadas j
      where j.marca_id = e.id and j.saudavel and j.data < p_data
    ) anterior on true
  ), com_falhas as (
    select pm.*,
           (select count(*)::integer
            from julgadas f
            where f.marca_id = pm.id
              and f.data > coalesce(pm.ultima_saudavel, p_data - 8)
              and f.data <= p_data
              and not f.saudavel
              and not f.adiada) as falhas
    from por_marca pm
  )
  select id, nome,
         case
           when saudavel_hoje then true
           when not tem_linha then false
           when adiada_hoje then ultima_saudavel is not null
           when recusa_hoje then ultima_saudavel is not null and falhas < 3
           else false
         end as coberta,
         case
           when saudavel_hoje then 'observada'
           when not tem_linha then 'sem_observacao_no_dia'
           when adiada_hoje and ultima_saudavel is not null then 'adiada_com_base'
           when adiada_hoje then 'adiada_sem_observacao_em_7_dias'
           when recusa_hoje and ultima_saudavel is null
             then 'recusa_sem_observacao_em_7_dias'
           when recusa_hoje and falhas < 3 then 'recusa_externa_tolerada'
           when recusa_hoje then 'recusa_persistente'
           when visitados_hoje = 0 then 'zero_sem_recusa_conhecida'
           when alertas_hoje ?| array['truncou', 'faixas_truncadas']
             then 'catalogo_truncado'
           else 'queda_critica'
         end as motivo,
         case when saudavel_hoje then p_data else ultima_saudavel end
           as ultima_saudavel,
         falhas as falhas_seguidas
  from com_falhas
  order by nome;
$function$;

comment on function public.cobertura_de_publicacao(text, date) is
  'A60: unica regra de cobertura para avancar o relogio publico do painel; espelha a tolerancia de alertas_criticos (adiamento declarado e recusa externa por menos de 3 coletas, com observacao saudavel nos 7 dias anteriores) e declara o motivo por marca.';

revoke all on function public.cobertura_de_publicacao(text, date)
  from public, anon, authenticated;
grant execute on function public.cobertura_de_publicacao(text, date)
  to service_role;

-- O MOTOR PASSA A PERGUNTAR A FUNCAO
-- ==================================
--
-- Tudo o mais fica identico a A58: a mesma ordem de calculos, o mesmo
-- marcador por segmento, a mesma reconstrucao do denominador antes da poda.
create or replace function public.computar_motor()
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  r_eventos integer;
  r_varejo integer;
  r_editorial integer;
  r_z integer;
  r_indice integer;
  r_curva integer;
  r_raridade integer;
  r_observacoes integer;
  r_sortimento integer;
  r_snapshots_removidos integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:publicacao-do-motor', 0));

  r_eventos := public.computar_eventos();
  r_varejo := public.computar_serie_varejo();
  r_editorial := public.computar_serie_editorial();
  r_z := public.computar_z();
  r_indice := public.computar_indice();
  r_curva := public.computar_curva_tamanhos();
  r_raridade := public.computar_raridade();

  -- O maximo do estado e apenas CANDIDATO. Ele so vira observacao publicada
  -- quando `cobertura_de_publicacao` cobre todas as marcas ativas/testadas do
  -- segmento naquela data. Isso vale tambem para motor manual e coleta
  -- dirigida a uma unica marca, que nao passam pelo portao Python.
  with candidatos as (
    select p.segmento, max(ep.ultimo_avistamento_em) as observado_em
    from public.estado_dos_produtos ep
    join public.produtos p on p.id = ep.produto_id
    where p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em <= current_date
    group by p.segmento
  ), contagens as (
    select c.segmento, c.observado_em,
           count(*)::integer as produtos_observados,
           count(distinct p.marca_id)::integer as marcas_observadas
    from candidatos c
    join public.produtos p on p.segmento = c.segmento
    join public.estado_dos_produtos ep
      on ep.produto_id = p.id
     and ep.ultimo_avistamento_em = c.observado_em
     and ep.ofertavel is true
    group by c.segmento, c.observado_em
  ), cobertura as (
    select c.segmento, c.observado_em,
           count(cp.marca_id)::integer as marcas_esperadas,
           count(cp.marca_id) filter (where cp.coberta)::integer
             as marcas_cobertas
    from candidatos c
    cross join lateral public.cobertura_de_publicacao(
      c.segmento, c.observado_em) cp
    group by c.segmento, c.observado_em
  ), publicaveis as (
    select c.*
    from contagens c
    join cobertura co
      on co.segmento = c.segmento and co.observado_em = c.observado_em
    left join public.observacoes_publicadas_do_painel anterior
      on anterior.segmento = c.segmento
    where co.marcas_esperadas > 0
      and co.marcas_cobertas = co.marcas_esperadas
      and (anterior.segmento is null
           or c.observado_em > anterior.observado_em)
  )
  insert into public.observacoes_publicadas_do_painel
    (segmento, observado_em, produtos_observados, marcas_observadas,
     publicado_em)
  select segmento, observado_em, produtos_observados, marcas_observadas, now()
  from publicaveis
  on conflict (segmento) do update
    set observado_em = excluded.observado_em,
        produtos_observados = excluded.produtos_observados,
        marcas_observadas = excluded.marcas_observadas,
        publicado_em = excluded.publicado_em
    where excluded.observado_em
          > public.observacoes_publicadas_do_painel.observado_em;
  get diagnostics r_observacoes = row_count;

  -- Ultima chance de ler o cru do dia. A chamada sem argumento inclui agora
  -- os dias dos marcadores publicados, alem dos dias com snapshot proprio.
  -- Depois da poda, um dia fora da janela nao existe mais em lugar nenhum.
  r_sortimento := public.computar_sortimento_diario();

  -- Todos os consumidores do cru ja terminaram; mantemos o piso seguro da A30.
  r_snapshots_removidos := public.podar_snapshots(21);

  return jsonb_build_object(
    'computar_eventos', r_eventos,
    'computar_serie_varejo', r_varejo,
    'computar_serie_editorial', r_editorial,
    'computar_z', r_z,
    'computar_indice', r_indice,
    'computar_curva_tamanhos', r_curva,
    'computar_raridade', r_raridade,
    'observacoes_publicadas', r_observacoes,
    'computar_sortimento_diario', r_sortimento,
    'snapshots_removidos', r_snapshots_removidos
  );
end;
$function$;

comment on function public.computar_motor() is
  'A60: mesma sequencia da A58; so avanca a observacao quando cobertura_de_publicacao cobre todas as marcas ativas do segmento; reconstroi o denominador e depois poda o cru, tudo na mesma transacao.';

revoke execute on function public.computar_motor()
  from public, anon, authenticated;
grant execute on function public.computar_motor() to service_role;
