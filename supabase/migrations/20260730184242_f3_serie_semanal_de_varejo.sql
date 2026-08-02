-- Motor, passo 2: agrega os snapshots diarios em serie semanal de varejo (§21).
--
-- A metrica e SHARE, nao contagem: §15 define oferta como "presenca do atributo
-- no sortimento do painel". Contagem cresceria so porque uma marca grande
-- entrou no painel; share mede composicao, que e o que interessa.
--
-- Roda no servidor de proposito (§33: "servidor calcula, app consulta"). Fazer
-- isto em Python exigiria trazer 65 mil produtos e 190 mil ligacoes pela rede.
--
-- IMPORTANTE: o varejo NAO recebe z-score (decisao B1 de 24/07 -- a perna nasce
-- em 24/07/2026 e nao alcanca as 8 semanas de §8 dentro do projeto). Esta
-- funcao grava `z` nulo de proposito; o varejo entra no produto como camada
-- descritiva (B1.3), que e fato do presente e nao precisa de normalizacao.
create or replace function computar_serie_varejo()
returns integer
language plpgsql
security invoker
as $$
declare
  linhas integer;
begin
  with semanas as (
    -- Semana ISO de cada snapshot: a segunda-feira.
    select distinct (data - ((extract(isodow from data)::int) - 1)) as semana
    from snapshots
  ),
  -- Um produto esta no sortimento da semana se ja tinha sido avistado ate o
  -- fim dela. Isto respeita a gravacao por delta (B3): dia sem linha nao
  -- significa produto ausente, significa produto sem mudanca.
  presenca as (
    select s.semana, p.id as produto_id, p.segmento
    from semanas s
    join produtos p
      on p.primeiro_avistamento <= s.semana + 6
     and p.segmento is not null
  ),
  total_semana as (
    select semana, segmento, count(*)::numeric as n_total
    from presenca group by semana, segmento
  ),
  por_termo as (
    select pr.semana, pr.segmento, pt.termo_id, count(distinct pr.produto_id)::numeric as n
    from presenca pr
    join produto_termos pt on pt.produto_id = pr.produto_id
    group by pr.semana, pr.segmento, pt.termo_id
  )
  insert into series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select
    pt.termo_id, pt.segmento, 'varejo', pt.semana,
    round(100.0 * pt.n / t.n_total, 4),   -- share em % do sortimento
    null,                                  -- B1: varejo sem z-score na v1
    pt.n::int,
    jsonb_build_object(
      'metrica', 'share do atributo no sortimento do painel (%)',
      'n_total_sortimento', t.n_total,
      'obs', 'sem z-score por decisao B1: a perna de varejo nasce em 24/07/2026 '
             'e nao alcanca as 8 semanas de §8 dentro do projeto',
      'computado_em', now()
    )
  from por_termo pt
  join total_semana t on t.semana = pt.semana and t.segmento = pt.segmento
  on conflict (termo_id, segmento, fonte, semana) do update
    set valor_bruto = excluded.valor_bruto,
        n_amostra   = excluded.n_amostra,
        meta        = excluded.meta;

  get diagnostics linhas = row_count;
  return linhas;
end;
$$;

comment on function computar_serie_varejo is
  'Agrega snapshots em serie semanal de varejo, como SHARE do sortimento (§15/§21). Varejo nao recebe z (B1).';;
