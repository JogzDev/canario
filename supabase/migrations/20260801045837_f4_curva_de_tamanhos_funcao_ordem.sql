create or replace function public.ordem_do_tamanho(bruto text)
returns table (sistema text, rotulo text, ordem numeric)
language sql immutable
set search_path to 'public', 'pg_temp'
as $$
  with limpo as (
    select upper(btrim(bruto)) as t
  ),
  br as (
    select case
             when t ~ '^[A-Z0-9]+/[A-Z0-9]+$' and t !~ 'BR|EU'
               then split_part(t, '/', 2)
             else t
           end as t
    from limpo
  )
  select
    case
      when t in ('XPP','XP','PP','P','M','G','GG','XG','XGG','XXG','EXG') then 'letra'
      when t ~ '^0*(3[0-9]|4[0-9]|5[0-9]|6[0-9])$' then 'br_numerico'
      else null
    end,
    case when t ~ '^0*\d+$' then ltrim(t, '0') else t end,
    case t
      when 'XPP' then 1 when 'XP' then 2 when 'PP' then 3 when 'P' then 4
      when 'M'   then 5 when 'G'  then 6 when 'GG' then 7 when 'XG' then 8
      when 'XGG' then 9 when 'XXG' then 10 when 'EXG' then 11
      else case when t ~ '^0*\d+$' then ltrim(t, '0')::numeric else null end
    end
  from br;
$$;

comment on function public.ordem_do_tamanho is
  'Rotulo de tamanho -> (sistema, rotulo limpo, ordem). A ordem serve APENAS para ordenar dentro da grade de um produto: o mesmo rotulo significa degraus diferentes em marcas diferentes (XG e o maior da Hering e um degrau alem do GG na Zinzane), entao nada aqui equivale tamanho entre marcas.';;
