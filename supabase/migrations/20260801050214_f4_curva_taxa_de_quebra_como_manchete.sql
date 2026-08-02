alter table public.curva_tamanhos
  add column if not exists n_em_risco integer not null default 0,
  add column if not exists taxa_quebra numeric;

comment on column public.curva_tamanhos.taxa_quebra is
  'MEDIDA PRINCIPAL (§23: usar dinamica, nunca a foto de um dia). Dos pares '
  '(produto, tamanho) que estavam DISPONIVEIS no inicio da janela, quantos '
  'ficaram indisponiveis ate o fim. E taxa de quebra observada, nao estoque.';

comment on column public.curva_tamanhos.share_indisponivel is
  'MEDIDA DE CONTEXTO. Foto do estado atual. A §23 proibe le-la como sinal de '
  'sucesso: carrega toda a indisponibilidade antiga e a profundidade de compra '
  'da marca, que nao observamos.';

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
$function$;;
