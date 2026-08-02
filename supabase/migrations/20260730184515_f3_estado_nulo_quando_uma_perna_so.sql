-- CORRECAO: `estavel` estava sendo afirmado com UMA perna ativa.
--
-- A §22 exige "pelo menos 2 fontes concordando" para `em alta` e o espelho para
-- `em queda`. Com uma perna so, nenhum desses estados e alcancavel -- e cair no
-- `else 'estavel'` faz o sistema AFIRMAR estabilidade que nao mediu. Isso e
-- valor plausivel no lugar de nulo declarado, que a regra inviolavel 2 proibe,
-- e a regra 6 manda dizer "cobertura insuficiente" em vez de inventar.
--
-- Agora: estado nulo quando ha menos de 2 pernas. O indice continua existindo e
-- sendo exibivel (com as pernas declaradas, §8), mas o ESTADO fica em silencio
-- honesto ate a segunda perna atingir o minimo.
create or replace function computar_indice()
returns integer
language plpgsql
security invoker
as $$
declare
  linhas integer;
begin
  with ativas as (
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
      max(z) filter (where fonte like 'editorial%')          as z_editorial,
      max(abs(z)) filter (where fonte not like 'editorial%')  as z_outras_abs,
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
      -- Silencio honesto: com menos de 2 pernas nao ha estado a declarar.
      when c.n_pernas < 2 then null
      when c.z_editorial >= 2.5 and coalesce(c.z_outras_abs, 0) < 1 then 'pico'
      when c.indice >= 1 and coalesce(c.indice_anterior, 0) >= 1
       and c.pernas_acima >= 2 then 'em alta'
      when c.indice <= -1 and coalesce(c.indice_anterior, 0) <= -1
       and c.pernas_abaixo >= 2 then 'em queda'
      else 'estavel'
    end,
    c.pernas, c.n_pernas,
    jsonb_build_object(
      'pesos', 'iguais entre as pernas ativas (§22), fixados antes de olhar resultado',
      'indice_semana_anterior', c.indice_anterior,
      'pernas_acima_de_1', c.pernas_acima,
      'pernas_abaixo_de_-1', c.pernas_abaixo,
      'estado_indisponivel_por', case when c.n_pernas < 2
        then 'apenas ' || c.n_pernas || ' perna ativa; §22 exige 2 fontes concordando'
        else null end,
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
$$;;
