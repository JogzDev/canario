-- P25: indices_semanais so recebe versao nova quando o resultado muda.
--
-- Medido em 18/09/2026: 610.443 updates acumulados em 9.897 linhas, com
-- 17,2 MB de heap para ~7,3 MB de dado vivo. `computar_indice()` recalculava
-- corretamente, mas o `on conflict do update` regravava todas as linhas em
-- toda publicacao, inclusive `meta.computado_em` e `computado_em` com `now()`.
-- Assim, qualquer compactacao da tabela seria consumida outra vez.
--
-- A expressao de calculo abaixo e a que estava em producao no backup
-- verificavel de 18/09. Ela difere da migration historica P1 em uma unica
-- prosa: `meta.por_que` e mais curta em producao. A P25 preserva a forma curta
-- para nao transformar a correcao de escrita em uma reescrita unica das
-- 9.897 linhas nem alterar o conteudo de auditoria por acidente.
--
-- So o predicado de escrita muda: cada coluna de negocio e comparada com
-- `is distinct from`, que trata nulo como valor. `meta.computado_em` fica fora
-- da comparacao porque e carimbo; os dois carimbos passam a significar a
-- ultima vez em que o resultado daquela linha mudou. A execucao do motor
-- continua registrada em `motor_execucoes`.
--
-- O `delete` de leituras que perderam toda base ja era diferencial e fica
-- intacto. O retorno continua sendo o `row_count` do upsert: insercoes e
-- alteracoes, sem contar remocoes, como no contrato anterior.

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
  insert into indices_semanais as atual
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
        computado_em = now()
  where atual.indice is distinct from excluded.indice
     or atual.estado is distinct from excluded.estado
     or atual.pernas_ativas is distinct from excluded.pernas_ativas
     or atual.n_pernas is distinct from excluded.n_pernas
     or (atual.meta - 'computado_em')
          is distinct from (excluded.meta - 'computado_em');

  get diagnostics linhas = row_count;
  return linhas;
end;
$function$;

comment on column public.indices_semanais.computado_em is
  'Instante da ultima mudanca do resultado desta linha, nao da ultima execucao do motor; cada execucao permanece auditavel em motor_execucoes.';

comment on function public.computar_indice() is
  'Recalcula o indice e escreve apenas insercoes ou resultados alterados; os carimbos computado_em representam a ultima mudanca por linha.';
