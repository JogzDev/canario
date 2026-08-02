create or replace function public.ordem_do_tamanho(bruto text)
returns table (sistema text, rotulo text, ordem numeric)
language sql immutable
set search_path to 'public', 'pg_temp'
as $$
  with limpo as (
    select upper(btrim(coalesce(bruto, ''))) as t
  ),
  br as (
    select case
             when t ~ '^[A-Z0-9]+/[A-Z0-9]+$' and t !~ 'BR|EU'
               then split_part(t, '/', 2)
             else t
           end as t
    from limpo
  ),
  -- `000` existe no catalogo e `ltrim('000','0')` devolve string vazia, que
  -- estoura na conversao para numeric. O nullif fecha o caso, e um tamanho sem
  -- digito nenhum nao e tamanho.
  norm as (
    select t, case when t ~ '^0*\d+$' then nullif(ltrim(t, '0'), '') else null end as digitos
    from br
  )
  select
    case
      when t in ('XPP','XP','PP','P','M','G','GG','XG','XGG','XXG','EXG') then 'letra'
      when digitos is not null and digitos::numeric between 30 and 69 then 'br_numerico'
      else null
    end,
    coalesce(digitos, t),
    case t
      when 'XPP' then 1 when 'XP' then 2 when 'PP' then 3 when 'P' then 4
      when 'M'   then 5 when 'G'  then 6 when 'GG' then 7 when 'XG' then 8
      when 'XGG' then 9 when 'XXG' then 10 when 'EXG' then 11
      else digitos::numeric
    end
  from norm;
$$;;
