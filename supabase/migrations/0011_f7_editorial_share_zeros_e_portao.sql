-- 0011 -- A perna editorial estava medindo a si mesma.
--
-- ===========================================================================
-- O QUE APARECEU NA TELA, E O QUE ESTAVA POR TRÁS
-- ===========================================================================
--
-- O app dizia que **preto, azul, branco/cru e vermelho/rosa estavam em `pico`**
-- na imprensa brasileira na semana de 27/07. Fui atrás das matérias:
--
--     semana   veículos ANTIGOS   veículos NOVOS
--     27/07           1                 14      <- o pico
--     20/07           6                  3
--     13/07           3                  0
--     06/07           8                  0
--     29/06           6                  0
--
-- Nos quatro veículos que já eram medidos (Elle, Steal the Look, Harper's,
-- Fashion Bubbles) a cobertura desses termos naquela semana **caiu para 1
-- artigo — o menor de toda a série**. Os 14 vieram inteiramente de Marie
-- Claire, Vogue Brasil e Glamour, que entraram entre 23 e 27/07.
--
-- Três defeitos independentes produziram isso, e dois deles se cancelavam
-- parcialmente — por isso a superfície parecia só "meio negativa" em vez de
-- obviamente quebrada.
--
-- ---------------------------------------------------------------------------
-- DEFEITO 1: semana sem matéria não virava zero, virava ausência
-- ---------------------------------------------------------------------------
-- `editorial_br` tinha **zero linhas com valor 0**, mínimo 0,25, e só **30,6%**
-- das células (termo × semana) existiam. `editorial_intl`: 48,5%.
--
-- A janela do z-score então só enxergava as semanas boas do termo: média
-- inflada, desvio subestimado, z puxado para baixo. Medido: **z médio do BR
-- negativo em 13 de 13 semanas**, e `em alta` = **0** em toda semana desde
-- 01/06. Depois da correção o z passa a oscilar em torno de zero (média
-- −0,03), que é o que um z normalizado tem de fazer.
--
-- O limite é deliberado: só se cria zero a partir da PRIMEIRA semana em que o
-- termo já tinha linha naquela perna. Antes disso não se sabe se o termo estava
-- sendo casado — a taxonomia mudou em 28/07 e 31/07 — e afirmar zero onde não
-- houve medição seria a regra 2 ao contrário.
--
-- ---------------------------------------------------------------------------
-- DEFEITO 2: a "janela móvel de 12 semanas" da §21 não era de 12 semanas
-- ---------------------------------------------------------------------------
-- `rows between 12 preceding` conta 12 **linhas**. Com 30,6% de preenchimento
-- isso cobria **29,2 semanas em média no `editorial_br`, e até 216 semanas —
-- mais de quatro anos — no pior caso**. E o app escrevia na tela, literalmente:
-- *"desvios da média das últimas 12 semanas deste mesmo atributo"*. Regra 3: o
-- caminho até a origem estava errado.
--
-- Agora é `range between interval '84 days' preceding and interval '7 days'
-- preceding` — calendário, não linhas. Com os zeros do defeito 1 as duas
-- coisas coincidem, mas o `range` deixa a garantia explícita.
--
-- ---------------------------------------------------------------------------
-- DEFEITO 3: "share of voice" era contagem absoluta
-- ---------------------------------------------------------------------------
-- O docstring do `coletor_editorial.py` e o nome do workflow dizem "share of
-- voice" desde sempre. A conta era `sum(janela) / 4` — divisão pelo número de
-- SEMANAS. Quando o painel de veículos cresce, todo termo sobe junto.
--
-- Medido: o denominador BR de 4 semanas foi de ~460 para **896 matérias
-- (+90%)** numa semana. Agora divide pelo total de matérias da própria perna na
-- mesma janela, em partes por mil para o número seguir legível. `n_amostra`
-- continua sendo a contagem crua, que é o que a tela mostra e continua verdade.
--
-- **A §33 mandou onde isto vive:** o coletor só enxerga o feed recente, e o
-- denominador precisa da série inteira. Quem divide é o motor.
--
-- ===========================================================================
-- O QUE A CORREÇÃO REVELOU, E NÃO RESOLVE
-- ===========================================================================
--
-- Com os zeros materializados, um termo que fica em 0 na maior parte das
-- semanas passa a ter desvio quase nulo — e uma semana com 5 matérias vira
-- **z = 10,27** (`azul`) ou 10,03 (`xadrez`, com 3 matérias).
--
-- **Z-score é o modelo errado para contagem esparsa.** Testei o resíduo de
-- Poisson, que seria o candidato óbvio: piorou (1.428 leituras acima de 2,5
-- contra 781) e o desvio observado deu **1,74** — variância 3× a de Poisson.
-- A contagem editorial é SUPERDISPERSA porque matéria de moda vem em rajada
-- temática. O modelo correto é binomial negativa, e isso é decisão de método,
-- não conserto de madrugada. Fica registrado aqui em vez de ser improvisado.
--
-- O que dá para fazer com a lei que já existe é o **portão de cobertura da §8**,
-- que a perna editorial nunca teve — o varejo tem `cobertura_por_celula` com
-- mínimo de 30 peças e 8 marcas, a busca tem os 5 anos do Trends, o editorial
-- não tinha nada. Piso: **10 matérias na janela de 4 semanas**, a regra de bolso
-- padrão para tratar contagem como aproximadamente normal, declarada como o
-- chute documentado que é (§22: "limiares são chutes iniciais documentados;
-- quem os corrige é o termômetro (§31), nunca ajuste ad hoc").
--
-- **Consequência de produto, e ela é grande:** a tela fica bem mais vazia. Na
-- semana de 27/07 sobram 6 termos com leitura e nenhum estado. Isso é o
-- tamanho real da imprensa de moda brasileira — ~450 a 900 matérias por 4
-- semanas, 40 termos disputando menção — e a regra 2 diz que dizer "não sei" é
-- melhor que afirmar o que não se mediu. **O valor do piso é decisão do JP.**

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
      s.id, s.fonte, s.valor_bruto, s.n_amostra,
      avg(s.valor_bruto) over w         as media,
      stddev_samp(s.valor_bruto) over w as desvio,
      count(*) over w                   as n_semanas
    from series_semanais s
    window w as (
      partition by s.termo_id, s.segmento, s.fonte
      order by s.semana
      range between interval '84 days' preceding and interval '7 days' preceding
    )
  )
  update series_semanais s
  set z = case
            when j.fonte = 'varejo' then null
            when j.n_semanas < (case when j.fonte like 'editorial%' then 6 else 8 end)
              then null
            -- §8 na perna editorial, que nunca teve portao.
            when j.fonte like 'editorial%' and coalesce(j.n_amostra, 0) < 10
              then null
            when j.desvio is null or j.desvio = 0 then null
            else round((j.valor_bruto - j.media) / j.desvio, 4)
          end
  from janela j
  where j.id = s.id;

  get diagnostics atualizadas = row_count;
  return atualizadas;
end;
$function$;

-- ---------------------------------------------------------------------------
-- LEITURA QUE PERDE A BASE TEM DE SUMIR DA TELA.
--
-- `computar_indice()` fazia upsert e nunca apagava. Uma vez escrito, um `pico`
-- ficava na tela para sempre, mesmo depois de a perna que o sustentava perder o
-- z. Descoberto agora, ao ligar o portao: quatro `pico` da semana de 27/07
-- continuaram exibidos com indice 5,48 e as DUAS pernas com z nulo. E a regra 2
-- ao contrario -- afirmar um estado que naquele momento nao tinha medicao
-- nenhuma por tras.
-- ---------------------------------------------------------------------------
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
      and s.semana = i.semana and s.z is not null);

  with ativas as (
    select termo_id, segmento, semana, fonte, z
    from series_semanais where z is not null
  ),
  agregado as (
    select termo_id, segmento, semana,
      round(avg(z), 4)                as indice,
      count(*)                        as n_pernas,
      array_agg(fonte order by fonte) as pernas,
      max(z) filter (where fonte like 'editorial%')          as z_editorial,
      max(abs(z)) filter (where fonte not like 'editorial%') as z_outras_abs,
      count(*) filter (where z >= 1)  as pernas_acima,
      count(*) filter (where z <= -1) as pernas_abaixo
    from ativas group by termo_id, segmento, semana
  ),
  com_anterior as (
    select a.*, lag(a.indice) over (partition by a.termo_id, a.segmento
                                    order by a.semana) as indice_anterior
    from agregado a
  )
  insert into indices_semanais
    (termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas, meta)
  select c.termo_id, c.segmento, c.semana, c.indice,
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
      'pesos', 'iguais entre as pernas ativas (§22), fixados antes de olhar resultado',
      'indice_semana_anterior', c.indice_anterior,
      'pernas_acima_de_1', c.pernas_acima,
      'pernas_abaixo_de_-1', c.pernas_abaixo,
      'estado_indisponivel_por', case when c.n_pernas < 2
        then 'apenas ' || c.n_pernas || ' perna ativa; §22 exige 2 fontes concordando'
        else null end,
      'obs_varejo', 'varejo nao entra no indice (B1); entra como camada descritiva',
      'computado_em', now())
  from com_anterior c
  on conflict (termo_id, segmento, semana) do update
    set indice = excluded.indice, estado = excluded.estado,
        pernas_ativas = excluded.pernas_ativas, n_pernas = excluded.n_pernas,
        meta = excluded.meta, computado_em = now();

  get diagnostics linhas = row_count;
  return linhas;
end;
$function$;
