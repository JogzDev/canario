-- A64: a Amaro volta a ser cobrada pelo portao de publicacao.
--
-- O QUE ACONTECEU
-- ===============
--
-- A A61 trocou a Amaro para `status_teste = 'nuvemshop'`. O coletor passou a
-- coleta-la -- a lista dele e `materializar_anexos.PLATAFORMAS`, que ja
-- conhece a Nuvemshop --, mas os dois portoes que decidem se o painel pode
-- ser publicado continuaram com a lista antiga, ('vtex', 'shopify'):
--
-- * `cobertura_de_publicacao` (A60), no motor;
-- * `renderizar_saude`, no Python, que alimenta `alertas_criticos`.
--
-- Conferido em producao em 23/09/2026: a cobertura esperava 14 marcas; a
-- Amaro, 15a ativa do feminino, estava fora. O painel de 23/09 foi publicado
-- sem que ninguem conferisse a Amaro. Hoje ela veio inteira (360 de 360
-- paginas), mas se a perna da Nuvemshop falhar, o painel sairia sem a marca
-- e sem alerta -- exatamente o "zero por erro desconhecido" que o portao
-- existe para barrar.
--
-- O QUE MUDA
-- ==========
--
-- So a lista da coorte esperada. Toda a regra de cobertura da A60 --
-- saudavel, adiada, recusa tolerada, queda critica -- fica identica. O
-- `teste_migrations.py` passa a exigir que esta lista seja a mesma de
-- `materializar_anexos.PLATAFORMAS`, e o Python passa a ler a lista de la:
-- plataforma nova entra nos dois portoes junto, ou o teste reprova.
--
-- ROLLBACK
-- ========
--
-- Voltar a funcao ao corpo da A60 (md5 b2920a553e4e73ebe8386aadb7797c74,
-- conferido em producao em 23/09/2026).

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
      -- A64: a mesma lista de `materializar_anexos.PLATAFORMAS`, que decide
      -- quem o coletor coleta. Marca coletada e nao esperada publica em
      -- silencio quando falha.
      and m.status_teste in ('vtex', 'shopify', 'nuvemshop')
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
  'A60 + A64: unica regra de cobertura para avancar o relogio publico do painel; espera toda marca ativa de plataforma coletavel (vtex, shopify, nuvemshop); espelha a tolerancia de alertas_criticos (adiamento declarado e recusa externa por menos de 3 coletas, com observacao saudavel nos 7 dias anteriores) e declara o motivo por marca.';

revoke all on function public.cobertura_de_publicacao(text, date)
  from public, anon, authenticated;
grant execute on function public.cobertura_de_publicacao(text, date)
  to service_role;
