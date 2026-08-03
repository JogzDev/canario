-- MOTOR SEM ACUMULO DE STAGE E SEM EXPANSAO TEMPORARIA LARGA

-- Stage e reconstruivel e nunca e lido pelo app. Tentativas falhas anteriores
-- deixaram 336 mil linhas ocupando o disco do projeto; limpa a recuperacao e
-- evita WAL dobrado nas proximas preparacoes.
update public.motor_execucoes
set status = 'failed', erro = coalesce(erro, 'stage limpo pela recuperacao de disco'),
    concluido_em = coalesce(concluido_em, now())
where status in ('queued', 'running');

truncate table public.motor_termos_stage, public.motor_produtos_stage;
alter table public.motor_termos_stage set unlogged;
alter table public.motor_produtos_stage set unlogged;

create or replace function public.executar_publicacao_motor(
  p_execucao uuid,
  p_total integer
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '900s'
as $function$
declare
  v_status text;
  v_resultado jsonb;
begin
  select status into v_status
  from public.motor_execucoes
  where execucao = p_execucao
  for update;

  if not found or v_status <> 'queued' then return; end if;

  update public.motor_execucoes
  set status = 'running', iniciado_em = now(), erro = null
  where execucao = p_execucao;

  begin
    v_resultado := public.publicar_motor(p_execucao, p_total);
  exception when others then
    -- O stage reproduz o matcher, nao e diagnostico insubstituivel. Remover o
    -- lote falho impede que cada red consuma mais disco e derrube o seguinte.
    delete from public.motor_termos_stage where execucao = p_execucao;
    delete from public.motor_produtos_stage where execucao = p_execucao;
    update public.motor_execucoes
    set status = 'failed', erro = sqlstate || ': ' || sqlerrm,
        concluido_em = now()
    where execucao = p_execucao;
    return;
  end;

  update public.motor_execucoes
  set status = 'success', resultado = v_resultado, concluido_em = now()
  where execucao = p_execucao;
end;
$function$;

-- A versao anterior materializava `_curva_com_termo`: todas as colunas de
-- tamanho repetidas para cada termo do produto. O agregado abaixo faz o mesmo
-- join em fluxo e so materializa base e janela, que sao uma linha por par.
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
           'computado_em', now())
  from agregado a where a.n_pares >= 1
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

select cron.schedule(
  'canario-motor-dispatcher', '* * * * *',
  $$set statement_timeout = '900s';
    set work_mem = '64MB';
    select public.executar_proxima_publicacao_motor();$$
);

comment on function public.computar_curva_tamanhos(integer) is
  'Calcula quebra de grade sem materializar produto x tamanho x termo.';
