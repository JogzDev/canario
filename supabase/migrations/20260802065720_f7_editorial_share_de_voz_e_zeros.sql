-- O mapa veiculo -> perna sai do anexos/veiculos.csv e passa a viver no banco,
-- para o coletor e o motor concordarem sobre quem e' BR e quem e' internacional.
create table if not exists public.veiculo_da_perna (
  veiculo text primary key,
  fonte   text not null check (fonte in ('editorial_br','editorial_intl'))
);

insert into public.veiculo_da_perna (veiculo, fonte) values
  ('Vogue Brasil','editorial_br'), ('Elle Brasil','editorial_br'),
  ('Harpers Bazaar Brasil','editorial_br'), ('Glamour Brasil','editorial_br'),
  ('Marie Claire Brasil','editorial_br'), ('FFW','editorial_br'),
  ('Steal the Look','editorial_br'), ('Fashion Bubbles','editorial_br'),
  ('FashionNetwork Brasil','editorial_br'),
  ('Vogue','editorial_intl'), ('Vogue Business','editorial_intl'),
  ('Business of Fashion','editorial_intl'), ('WWD','editorial_intl'),
  ('Who What Wear','editorial_intl'), ('Refinery29','editorial_intl'),
  ('Hypebeast','editorial_intl'), ('Highsnobiety','editorial_intl'),
  ('Dazed','editorial_intl'), ('Lyst','editorial_intl')
on conflict (veiculo) do update set fonte = excluded.fonte;

alter table public.veiculo_da_perna enable row level security;

-- Denominador da perna editorial: total de materias da perna na mesma janela
-- movel de 4 semanas (§18) que o numerador usa.
create or replace view public.denominador_editorial as
with por_semana as (
  select v.fonte, date_trunc('week', a.data_pub)::date as semana, count(*)::numeric as n
  from artigos a
  join veiculo_da_perna v on v.veiculo = a.veiculo
  where a.data_pub is not null
  group by 1, 2
)
select fonte, semana,
       sum(n) over (partition by fonte order by semana
                    rows between 3 preceding and current row) as total_janela_4sem,
       n as total_semana_crua
from por_semana;

comment on view public.denominador_editorial is
  'Total de materias por perna na janela de 4 semanas. E o denominador que '
  'faltava: sem ele o numero e contagem absoluta e cresce quando o painel de '
  'veiculos cresce, nao quando o mercado se move.';

create or replace function public.computar_serie_editorial()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  inseridas integer;
  ajustadas integer;
begin
  -- 1) MATERIALIZAR OS ZEROS.
  --
  -- Semana em que a perna coletou e o termo nao apareceu vale ZERO, e zero e
  -- medicao. Hoje ela nao existe como linha, e a janela do z-score so enxerga
  -- as semanas boas do termo: media inflada, desvio subestimado, z puxado para
  -- baixo. Medido em 02/08: z medio do editorial_br negativo em 13 de 13
  -- semanas, e `em alta` = 0 em toda semana desde 01/06.
  --
  -- O limite e' deliberado: so' se cria zero a partir da PRIMEIRA semana em que
  -- o termo ja tinha linha naquela perna. Antes disso nao se sabe se o termo
  -- estava sendo casado (a taxonomia mudou em 28/07 e 31/07), e afirmar zero
  -- onde nao houve medicao seria a regra 2 ao contrario.
  with coberta as (
    select distinct fonte, semana from denominador_editorial
  ),
  inicio as (
    select termo_id, segmento, fonte, min(semana) as primeira
    from series_semanais where fonte like 'editorial%'
    group by 1, 2, 3
  ),
  faltando as (
    select i.termo_id, i.segmento, i.fonte, c.semana
    from inicio i
    join coberta c on c.fonte = i.fonte and c.semana >= i.primeira
    where not exists (
      select 1 from series_semanais s
      where s.termo_id = i.termo_id and s.segmento = i.segmento
        and s.fonte = i.fonte and s.semana = c.semana)
  )
  insert into series_semanais (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  select f.termo_id, f.segmento, f.fonte, f.semana, 0, null, 0,
         jsonb_build_object(
           'janela_semanas', 4,
           'contagem_semana_crua', 0,
           'unidade', 'materias por mil da perna, em janela de 4 semanas',
           'zero_materializado', true,
           'obs', 'semana em que a perna coletou e o termo nao apareceu. '
                  'Zero e medicao, nao ausencia.')
  from faltando f;
  get diagnostics inseridas = row_count;

  -- 2) SHARE OF VOICE DE VERDADE.
  --
  -- O coletor dividia por 4 -- o numero de SEMANAS da janela -- e chamava isso
  -- de share of voice. E contagem absoluta: quando o painel de veiculos cresce,
  -- todo termo sobe junto sem o mercado ter se mexido. Medido em 02/08: o
  -- denominador BR foi de ~460 para 896 materias (+90%) em uma semana, quando
  -- Marie Claire, Vogue Brasil e Glamour entraram.
  --
  -- Agora divide pelo total de materias da propria perna na mesma janela, em
  -- partes por mil para o numero continuar legivel. `n_amostra` segue sendo a
  -- contagem crua, que e o que a tela mostra e continua verdadeira.
  update series_semanais s
     set valor_bruto = round(1000.0 * coalesce(s.n_amostra, 0) / d.total_janela_4sem, 4),
         meta = coalesce(s.meta, '{}'::jsonb) || jsonb_build_object(
           'unidade', 'materias por mil da perna, em janela de 4 semanas',
           'materias_da_perna_na_janela', d.total_janela_4sem,
           'obs_normalizacao',
             'share of voice: numerador e denominador na MESMA janela de 4 '
             'semanas. Antes o divisor era 4 (semanas), o que fazia o numero '
             'crescer quando o painel de veiculos crescia.')
    from denominador_editorial d
   where d.fonte = s.fonte and d.semana = s.semana
     and s.fonte like 'editorial%'
     and d.total_janela_4sem > 0;
  get diagnostics ajustadas = row_count;

  return inseridas + ajustadas;
end;
$function$;

-- 3) A JANELA DA §21 PASSA A SER DE CALENDARIO, NAO DE LINHAS.
--
-- `rows between 12 preceding` conta 12 LINHAS. Com a perna editorial em 30,6%
-- de preenchimento isso cobria 29,2 semanas em media e ate 216 semanas -- mais
-- de quatro anos -- enquanto o app escrevia na tela "media das ultimas 12
-- semanas". Com os zeros materializados (passo 1) as duas coisas coincidem,
-- mas o `range` deixa a garantia explicita em vez de depender disso.
create or replace function public.computar_z()
returns integer
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  atualizadas integer;
begin
  with janela as (
    select
      s.id, s.fonte, s.valor_bruto,
      avg(s.valor_bruto) over w        as media,
      stddev_samp(s.valor_bruto) over w as desvio,
      count(*) over w                  as n_semanas
    from series_semanais s
    window w as (
      partition by s.termo_id, s.segmento, s.fonte
      order by s.semana
      -- 12 semanas de CALENDARIO, sem a semana corrente.
      range between interval '84 days' preceding and interval '7 days' preceding
    )
  )
  update series_semanais s
  set z = case
            when j.fonte = 'varejo' then null
            when j.n_semanas < (case when j.fonte like 'editorial%' then 6 else 8 end)
              then null
            when j.desvio is null or j.desvio = 0 then null
            else round((j.valor_bruto - j.media) / j.desvio, 4)
          end
  from janela j
  where j.id = s.id;

  get diagnostics atualizadas = row_count;
  return atualizadas;
end;
$function$;;
