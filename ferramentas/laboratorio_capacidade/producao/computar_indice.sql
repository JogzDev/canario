-- `computar_indice` COMO ESTA EM PRODUCAO, capturada em leitura em 18/09/2026
-- (`pg_get_functiondef`, hash normalizado ce2ffa99841a237ee1001071b46ee772).
--
-- A migration histórica contém uma frase adicional em `meta.por_que` que
-- nunca chegou ao banco. O laboratório precisa partir do código ativo, não de
-- uma reconstrução aproximada do histórico.

create or replace function public.computar_indice()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  linhas integer;
begin
  delete from indices_semanais i
  where not exists (
    select 1 from series_semanais s
    where s.termo_id = i.termo_id and s.segmento = i.segmento
      and s.semana = i.semana and s.z is not null
      and s.fonte in ('busca', 'editorial_br'));

  with ativas as (
    select termo_id, segmento, semana, fonte, z
    from series_semanais
    where z is not null and fonte in ('busca', 'editorial_br')
  ),
  contexto as (
    select termo_id, segmento, semana,
           jsonb_object_agg(fonte, round(z, 4)) as z_de_contexto
    from series_semanais
    where z is not null and fonte not in ('busca', 'editorial_br')
    group by termo_id, segmento, semana
  ),
  agregado as (
    select
      termo_id, segmento, semana,
      round(avg(z), 4)                      as indice,
      count(*)                              as n_pernas,
      array_agg(fonte order by fonte)       as pernas,
      max(z) filter (where fonte = 'editorial_br')  as z_editorial,
      max(abs(z)) filter (where fonte = 'busca')    as z_outras_abs,
      count(*) filter (where z >= 1)        as pernas_acima,
      count(*) filter (where z <= -1)       as pernas_abaixo
    from ativas
    group by termo_id, segmento, semana
  ),
  com_anterior as (
    select a.*,
      lag(a.indice) over (partition by a.termo_id, a.segmento order by a.semana) as indice_anterior,
      c.z_de_contexto
    from agregado a
    left join contexto c using (termo_id, segmento, semana)
  )
  insert into indices_semanais
    (termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas, meta)
  select
    c.termo_id, c.segmento, c.semana, c.indice,
    case
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
      'pesos', 'iguais entre as pernas que confirmam (§22), fixados antes de olhar resultado',
      'pernas_que_confirmam', array['busca', 'editorial_br'],
      'por_que', 'o app posiciona peca no mercado brasileiro; quem confirma direcao daqui e sinal daqui',
      'contexto_nao_confirma', c.z_de_contexto,
      'indice_semana_anterior', c.indice_anterior,
      'pernas_acima_de_1', c.pernas_acima,
      'pernas_abaixo_de_-1', c.pernas_abaixo,
      'estado_indisponivel_por', case when c.n_pernas < 2
        then 'apenas ' || c.n_pernas || ' perna que confirma; §22 exige 2'
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
$function$;
