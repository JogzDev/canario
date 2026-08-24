-- A29: recorte editorial feminino sem apagar o arquivo.
-- A classificação usa somente o título persistido, permitindo aplicar a mesma
-- regra ao histórico e ao futuro. Masculino continua auditável em `artigos`,
-- mas não participa nem do numerador nem do denominador.

alter table public.artigos
  add column if not exists publico_editorial text not null default 'neutro',
  add column if not exists pontos_femininos smallint not null default 0,
  add column if not exists pontos_masculinos smallint not null default 0,
  add column if not exists genero_classificado_em timestamptz;

alter table public.artigos drop constraint if exists artigos_publico_editorial_check;
alter table public.artigos add constraint artigos_publico_editorial_check
  check (publico_editorial in ('feminino', 'masculino', 'neutro'));

create or replace view public.denominador_editorial
with (security_invoker = true)
as
with por_semana as (
  select v.fonte, date_trunc('week', a.data_pub)::date as semana,
         count(*)::numeric as n
  from public.artigos a
  join public.veiculo_da_perna v on v.veiculo = a.veiculo
  where a.data_pub is not null
    and a.publico_editorial <> 'masculino'
  group by 1, 2
)
select fonte, semana,
       sum(n) over (partition by fonte order by semana
                    rows between 3 preceding and current row) as total_janela_4sem,
       n as total_semana_crua
from por_semana;

comment on view public.denominador_editorial is
  'Total feminino+neutro por perna na mesma janela móvel de 4 semanas do numerador. Artigos inclinados >50% ao masculino ficam preservados e excluídos.';

create or replace function public.registrar_classificacao_editorial(classificacoes jsonb)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare linhas integer;
begin
  update public.artigos a
     set publico_editorial = x.publico,
         pontos_femininos = x.feminino,
         pontos_masculinos = x.masculino,
         genero_classificado_em = now()
    from jsonb_to_recordset(classificacoes) as x(
      id bigint, publico text, feminino smallint, masculino smallint)
   where a.id = x.id;
  get diagnostics linhas = row_count;
  return linhas;
end;
$function$;

revoke execute on function public.registrar_classificacao_editorial(jsonb)
  from public, anon, authenticated;
grant execute on function public.registrar_classificacao_editorial(jsonb)
  to service_role;

-- Substitui uma perna inteira em uma transação. O script calcula fora do banco
-- porque o vocabulário aprovado contém regexes e sinônimos que já vivem no
-- matcher Python. Se a carga falhar, a série antiga permanece intacta.
create or replace function public.substituir_serie_editorial(
  perna text, linhas jsonb)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare inseridas integer;
begin
  if perna not in ('editorial_br', 'editorial_intl') then
    raise exception 'perna editorial inválida';
  end if;
  if jsonb_array_length(linhas) = 0 then
    raise exception 'carga vazia: série preservada';
  end if;

  create temp table _editorial_novo on commit drop as
  select * from jsonb_to_recordset(linhas) as x(
    termo_id text, segmento text, fonte text, semana date,
    valor_bruto numeric, z numeric, n_amostra integer, meta jsonb);

  if exists (select 1 from _editorial_novo where fonte <> perna) then
    raise exception 'carga mistura pernas editoriais';
  end if;

  delete from public.series_semanais where fonte = perna;
  insert into public.series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select termo_id, segmento, fonte, semana, valor_bruto, null, n_amostra, meta
  from _editorial_novo;
  get diagnostics inseridas = row_count;
  return inseridas;
end;
$function$;

revoke execute on function public.substituir_serie_editorial(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.substituir_serie_editorial(text, jsonb)
  to service_role;
