-- PORTAO DE COBERTURA DA PERNA EDITORIAL (§8).
--
-- A §8 existe para isto e nunca foi aplicada aqui. O varejo tem
-- `cobertura_por_celula` com minimo de 30 pecas e 8 marcas. A busca tem os 5
-- anos do Trends. A perna editorial nao tinha portao nenhum -- e por isso um
-- termo com 3 materias em 4 semanas produzia z = 10,03 e acendia `pico`.
--
-- O piso e' 10 materias na janela de 4 semanas. E a regra de bolso padrao para
-- tratar contagem como aproximadamente normal, e esta declarada como o chute
-- documentado que e': a §22 ja diz que "limiares sao chutes iniciais
-- documentados; quem os corrige e o termometro (§31), nunca ajuste ad hoc".
--
-- MEDIDO em 02/08, e o motivo de o portao nao ser suficiente sozinho: mesmo
-- com 20 materias o maior |z| ainda e 6,8. A causa e' que z-score pressupoe
-- normalidade e a contagem editorial e' ESPARSA E SUPERDISPERSA -- testei o
-- residuo de Poisson e o desvio observado deu 1,74 (variancia 3x a de
-- Poisson), porque materia de moda vem em rajada tematica. O modelo correto e'
-- binomial negativa, e essa e' uma decisao de metodo que fica registrada aqui
-- em vez de ser resolvida as pressas.
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
      -- 12 semanas de CALENDARIO, sem a semana corrente. Antes era
      -- `rows between 12 preceding`, que com a perna editorial em 30,6% de
      -- preenchimento cobria 29,2 semanas em media e ate 216 no pior caso,
      -- enquanto o app escrevia "media das ultimas 12 semanas" na tela.
      range between interval '84 days' preceding and interval '7 days' preceding
    )
  )
  update series_semanais s
  set z = case
            when j.fonte = 'varejo' then null
            when j.n_semanas < (case when j.fonte like 'editorial%' then 6 else 8 end)
              then null
            -- §8 na perna editorial: sem materia suficiente na janela, nao ha
            -- z. Nulo declarado, nunca valor plausivel (regra 2).
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
$function$;;
