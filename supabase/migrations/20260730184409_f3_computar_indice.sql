-- Indice do atributo e estado semanal (§22).
--
-- Pesos IGUAIS entre as pernas ativas, fixados por escrito ANTES de olhar
-- resultado -- e a protecao contra curve fitting retorico que a §22 exige. Nao
-- mexer nos pesos sem entrada no changelog; K10 diz que o termometro recalibra
-- LIMIARES, nao pesos.
create or replace function computar_indice()
returns integer
language plpgsql
security invoker
as $$
declare
  linhas integer;
begin
  with ativas as (
    -- Perna ativa = a que tem z na semana. Varejo nunca tem (B1), entao entra
    -- no produto pela camada descritiva, nao pelo indice.
    select termo_id, segmento, semana, fonte, z
    from series_semanais
    where z is not null
  ),
  agregado as (
    select
      termo_id, segmento, semana,
      round(avg(z), 4)                      as indice,
      count(*)                              as n_pernas,
      array_agg(fonte order by fonte)       as pernas,
      -- Para o estado `pico` (C4): o z do editorial isolado, e o maximo das
      -- demais pernas, que precisa estar neutro.
      max(z) filter (where fonte like 'editorial%')       as z_editorial,
      max(abs(z)) filter (where fonte not like 'editorial%') as z_outras_abs,
      count(*) filter (where z >= 1)        as pernas_acima,
      count(*) filter (where z <= -1)       as pernas_abaixo
    from ativas
    group by termo_id, segmento, semana
  ),
  com_anterior as (
    select a.*,
      lag(a.indice) over (partition by a.termo_id, a.segmento order by a.semana) as indice_anterior
    from agregado a
  )
  insert into indices_semanais
    (termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas, meta)
  select
    c.termo_id, c.segmento, c.semana, c.indice,
    case
      -- `pico` (§22 + C4): evento pontual do editorial com as demais neutras.
      -- Vem ANTES de em alta/queda porque e a leitura mais especifica.
      when c.z_editorial >= 2.5
       and coalesce(c.z_outras_abs, 0) < 1
        then 'pico'
      -- `em alta`: indice >= +1 por DUAS semanas consecutivas E pelo menos duas
      -- pernas concordando. Uma semana isolada nunca muda estado -- e a regra
      -- anti-ruido, e e ela que impede o app de gritar a cada oscilacao.
      when c.indice >= 1 and coalesce(c.indice_anterior, 0) >= 1
       and c.pernas_acima >= 2
        then 'em alta'
      -- `em queda`: espelho exato.
      when c.indice <= -1 and coalesce(c.indice_anterior, 0) <= -1
       and c.pernas_abaixo >= 2
        then 'em queda'
      else 'estavel'
    end,
    c.pernas, c.n_pernas,
    jsonb_build_object(
      'pesos', 'iguais entre as pernas ativas (§22), fixados antes de olhar resultado',
      'indice_semana_anterior', c.indice_anterior,
      'pernas_acima_de_1', c.pernas_acima,
      'pernas_abaixo_de_-1', c.pernas_abaixo,
      'obs_varejo', 'varejo nao entra no indice (B1); entra como camada descritiva',
      'computado_em', now()
    )
  from com_anterior c
  on conflict (termo_id, segmento, semana) do update
    set indice = excluded.indice,
        estado = excluded.estado,
        pernas_ativas = excluded.pernas_ativas,
        n_pernas = excluded.n_pernas,
        meta = excluded.meta,
        computado_em = now();

  get diagnostics linhas = row_count;
  return linhas;
end;
$$;

comment on function computar_indice is
  'Indice = media dos z das pernas ativas, pesos iguais (§22). Estados com a regra anti-ruido de 2 semanas; `pico` sobre editorial isolado (C4).';;
