-- §22: quem CONFIRMA uma direcao e sinal brasileiro. O resto e contexto.
--
-- A DECISAO
-- =========
--
-- O Canario existe para marca brasileira decidir como posicionar uma peca NO
-- MERCADO NACIONAL. A imprensa estrangeira antecipa moda que chega aqui -- por
-- copia e por desejo do cliente influenciado pela midia de fora -- e por isso
-- continua sendo coletada e mostrada. Mas ela nao pode ser a testemunha que
-- autoriza o app a dizer "em alta" sobre o mercado daqui.
--
-- O QUE A MEDICAO MOSTROU (06/08)
-- ===============================
--
-- Correlacao do z e concordancia de sinal contra a perna de busca (BR):
--
--   busca x editorial_br     r = 0,235   67,7% de mesmo sinal (ambos |z|>=1, n=167)
--   busca x editorial_intl   r = -0,070  54,7%                (n=179)
--
-- Com n~170 o erro-padrao de r e ~0,077: 0,235 esta a tres erros-padrao de
-- zero, e -0,070 esta dentro de um. A imprensa internacional e a busca
-- brasileira nao se movem juntas de forma distinguivel do acaso.
--
-- E o par sem relacao era o mais usado: dos 114 "em alta" no banco, 49 vinham
-- de {busca, editorial_intl} contra 47 de {busca, editorial_br}.
--
-- (editorial_br x editorial_intl da r = 0,036 -- as duas nao sao a mesma
-- imprensa contada duas vezes. Sao coisas diferentes, e uma delas nao e sobre
-- este mercado.)
--
-- O QUE MUDA
-- ==========
--
-- Pernas que confirmam: `busca` e `editorial_br`. O indice passa a ser a media
-- delas, e a §22 exige que DUAS delas concordem.
--
-- `editorial_intl` e `varejo` viram contexto: continuam gravados, continuam
-- aparecendo em `meta`, e nao movem o numero nem acendem estado.
--
-- Isso tambem fecha um buraco que o comentario da propria funcao ja admitia: o
-- meta dizia "varejo nao entra no indice (B1)" e o CTE `ativas` nao filtrava
-- fonte nenhuma. Funcionava so porque `computar_z()` nao calcula z para
-- varejo -- o indice dependia do comportamento de outra funcao, e nao de uma
-- regra sua.

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
      'por_que', 'o app posiciona peca no mercado brasileiro; quem confirma direcao daqui e sinal daqui. Medido em 06/08: busca x editorial_br r=0,235 e 67,7% de mesmo sinal; busca x editorial_intl r=-0,070, dentro de um erro-padrao de zero',
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
