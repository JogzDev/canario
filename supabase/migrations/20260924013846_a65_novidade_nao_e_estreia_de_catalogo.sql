-- A65: novidade na leitura especifica nao e estreia de catalogo trocado.
--
-- A primeira leitura real da `ler-peca` (24/09/2026, "jaqueta napoleao")
-- disse que as tres pecas eram "novidades no painel". Eram da Amaro, que
-- trocou de plataforma em 23/09 (A61): o catalogo novo inteiro tem
-- `primeiro_avistamento` na primeira leitura da Nuvemshop. O fato
-- `novidades_30d` passa a ignorar quem estreou no dia da primeira leitura de
-- um catalogo trocado; o que chegou depois dela e lancamento de verdade.
--
-- So `fatos_da_leitura` muda; as candidatas e as demais regras da A64 ficam.

create or replace function public.fatos_da_leitura(
  p_ids bigint[],
  p_preco_da_pessoa numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  painel date;
  resultado jsonb;
begin
  if coalesce(cardinality(p_ids), 0) > 200 then
    raise exception 'leitura: no maximo 200 pecas por leitura' using errcode = '22023';
  end if;
  select o.observado_em into painel
  from public.observacoes_publicadas_do_painel o
  where o.segmento = 'feminino_casual_br';

  with pecas as (
    -- As mesmas regras de "ativa" das candidatas: um id velho ou aposentado
    -- mandado pela Luna simplesmente nao conta.
    select p.id, p.marca_id, m.nome as marca, p.ultimo_preco_atual as preco,
           p.ultimo_preco_original as original, p.primeiro_avistamento,
           p.ultima_grade
    from public.produtos p
    join public.marcas m on m.id = p.marca_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    where p.id = any (coalesce(p_ids, '{}'))
      and p.segmento = 'feminino_casual_br'
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em between painel - 7 and painel
      and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                       where ca.produto_id = p.id)
  ), estreias_de_catalogo as (
    -- A65: numa troca de plataforma (A61) o catalogo novo inteiro "aparece
    -- pela primeira vez" no dia da primeira leitura. Aquilo e o mesmo estoque
    -- com outro codigo, nao lancamento.
    select t.marca_id, t.em, min(p2.primeiro_avistamento) as primeira_leitura
    from public.trocas_de_catalogo t
    join public.produtos p2 on p2.marca_id = t.marca_id and p2.primeiro_avistamento >= t.em
    group by t.marca_id, t.em
  ), novidades as (
    select pc.id
    from pecas pc
    where pc.primeiro_avistamento >= painel - 29
      and not exists (select 1 from estreias_de_catalogo e
                       where e.marca_id = pc.marca_id
                         and pc.primeiro_avistamento between e.em and e.primeira_leitura)
  ), com_preco as (
    select * from pecas where preco is not null and preco > 0
  ), remarcadas as (
    select id, round(100 * (1 - preco / original))::integer as desconto
    from com_preco
    where original is not null and original > 0 and preco <= original * 0.95
  ), eventos_da_janela as (
    select e.produto_id, e.tipo, e.data
    from public.eventos e
    join pecas pc on pc.id = e.produto_id
    where e.tipo in ('reposicao', 'remarcacao')
      and e.data between painel - 29 and painel
  ), grade as (
    select id,
           exists (select 1 from jsonb_each(coalesce(ultima_grade, '{}'::jsonb)) g
                   where g.value = 'false'::jsonb) as tem_tamanho_esgotado,
           exists (select 1 from jsonb_each(coalesce(ultima_grade, '{}'::jsonb))) as tem_grade
    from pecas
  )
  select jsonb_build_object(
    'painel_observado_em', painel,
    'janela_de_eventos', jsonb_build_object('de', painel - 29, 'ate', painel),
    'fatos', jsonb_build_array(
      jsonb_build_object(
        'id', 'total', 'pecas', (select count(*) from pecas),
        'marcas', (select count(distinct marca) from pecas),
        'provas', coalesce((select jsonb_agg(id order by id) from (select id from pecas order by id limit 24) x), '[]')),
      jsonb_build_object(
        'id', 'marcas',
        'por_marca', coalesce((select jsonb_agg(jsonb_build_object('marca', marca, 'pecas', n) order by n desc, marca)
                               from (select marca, count(*) as n from pecas group by marca) x), '[]')),
      jsonb_build_object(
        'id', 'preco', 'pecas', (select count(*) from com_preco),
        'minimo', (select min(preco) from com_preco),
        'p25', (select round(percentile_cont(0.25) within group (order by preco)::numeric, 2) from com_preco),
        'mediana', (select round(percentile_cont(0.5) within group (order by preco)::numeric, 2) from com_preco),
        'p75', (select round(percentile_cont(0.75) within group (order by preco)::numeric, 2) from com_preco),
        'maximo', (select max(preco) from com_preco),
        'provas', coalesce((select jsonb_agg(id) from (
            (select id from com_preco order by preco, id limit 1)
            union all (select id from com_preco order by preco desc, id limit 1)) x), '[]')),
      jsonb_build_object(
        'id', 'remarcadas', 'pecas', (select count(*) from remarcadas),
        'de_cada_100', (select round(100.0 * (select count(*) from remarcadas) / nullif(count(*), 0))::integer
                        from com_preco),
        'desconto_mediano_pct', (select percentile_disc(0.5) within group (order by desconto) from remarcadas),
        'provas', coalesce((select jsonb_agg(id order by desconto desc, id) from (select * from remarcadas order by desconto desc, id limit 24) x), '[]')),
      jsonb_build_object(
        'id', 'reposicoes_30d',
        'pecas', (select count(distinct produto_id) from eventos_da_janela where tipo = 'reposicao'),
        'ultima', (select max(data) from eventos_da_janela where tipo = 'reposicao'),
        'provas', coalesce((select jsonb_agg(distinct produto_id) from eventos_da_janela where tipo = 'reposicao'), '[]')),
      jsonb_build_object(
        'id', 'remarcacoes_30d',
        'pecas', (select count(distinct produto_id) from eventos_da_janela where tipo = 'remarcacao'),
        'ultima', (select max(data) from eventos_da_janela where tipo = 'remarcacao'),
        'provas', coalesce((select jsonb_agg(distinct produto_id) from eventos_da_janela where tipo = 'remarcacao'), '[]')),
      jsonb_build_object(
        'id', 'novidades_30d',
        'pecas', (select count(*) from novidades),
        'provas', coalesce((select jsonb_agg(id order by id) from novidades), '[]')),
      jsonb_build_object(
        'id', 'grade',
        'pecas_com_grade', (select count(*) from grade where tem_grade),
        'com_tamanho_esgotado', (select count(*) from grade where tem_tamanho_esgotado),
        'provas', coalesce((select jsonb_agg(id order by id) from grade where tem_tamanho_esgotado), '[]'))
    ) || case when p_preco_da_pessoa is null or p_preco_da_pessoa <= 0 then '[]'::jsonb
         else jsonb_build_array(jsonb_build_object(
           'id', 'posicao_do_preco', 'preco', p_preco_da_pessoa,
           'pecas', (select count(*) from com_preco),
           'mais_baratas', (select count(*) from com_preco where preco < p_preco_da_pessoa),
           'mais_caras', (select count(*) from com_preco where preco > p_preco_da_pessoa),
           'provas', coalesce((select jsonb_agg(id) from (
               select id from com_preco order by abs(preco - p_preco_da_pessoa), id limit 3) x), '[]')))
         end)
  into resultado;
  return resultado;
end;
$function$;

revoke all on function public.fatos_da_leitura(bigint[], numeric) from public, anon, authenticated;
grant execute on function public.fatos_da_leitura(bigint[], numeric) to service_role;
