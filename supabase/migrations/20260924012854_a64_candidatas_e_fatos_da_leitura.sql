-- A64: candidatas e fatos da leitura específica.
--
-- O QUE A LEITURA ESPECÍFICA PRECISA DO BANCO
-- ===========================================
--
-- "Napoleon jacket" não é termo da taxonomia: são 45 termos, e nenhum diz
-- fileira dupla de botões, gola alta ou alamares. A leitura específica da 2.0
-- faz assim:
--
--   1. a Luna traduz o pedido (texto ou foto) em categoria + sinais de
--      construção no nome das peças ("napole", "abotoamento duplo", "gola
--      padre") + vetos ("verde militar");
--   2. `candidatas_da_leitura` devolve as peças ativas do painel que casam;
--   3. a Luna verifica cada candidata e fica só com as que são a peça;
--   4. `fatos_da_leitura` calcula os números sobre as verificadas, cada um com
--      as peças que o provam;
--   5. a Luna escreve, e cada frase cita o fato que a sustenta.
--
-- Medido em 23/09/2026: buscar "militar" no nome devolve quase só a COR verde
-- militar (macacões, regatas, calças) e nenhuma jaqueta napoleão. Por isso a
-- busca tem veto, a categoria vem da taxonomia, e o verificador existe.
--
-- O QUE AS DUAS FUNÇÕES GARANTEM
-- ==============================
--
-- * Só peça ativa do painel publicado: ofertável e vista na janela de sete
--   dias do dia publicado (a âncora da A57), fora do catálogo aposentado
--   numa troca de plataforma (A61). Nada de peça que sumiu virar prova.
-- * Sinais e vetos são texto, nunca padrão: `%` e `_` vindos da Luna são
--   escapados, cada um tem de 3 a 40 caracteres, e há no máximo 12 de cada.
--   A Luna lê texto de quem usa o app; nada que ela devolva vira expressão
--   regular dentro do banco.
-- * Cada fato traz `provas`: as peças que o sustentam. É o que a tela abre
--   quando a pessoa toca numa frase.
-- * Só a chave de serviço chama. A Edge Function da leitura é a porta.

create or replace function public._texto_da_leitura(p_itens text[])
returns text[]
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(array_agg(distinct '%' || replace(replace(replace(s, '\', '\\'), '%', '\%'), '_', '\_') || '%'),
                  '{}')
  from (
    select btrim(regexp_replace(lower(public.unaccent(x)), '\s+', ' ', 'g')) as s
    from unnest(coalesce(p_itens, '{}')) as x
  ) normalizado
  where length(s) between 3 and 40;
$function$;

revoke all on function public._texto_da_leitura(text[]) from public, anon, authenticated;

create or replace function public.candidatas_da_leitura(
  p_categorias text[],
  p_sinais text[],
  p_vetos text[] default '{}',
  p_limite integer default 60)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  painel date;
  sinais text[] := public._texto_da_leitura(p_sinais);
  vetos text[] := public._texto_da_leitura(p_vetos);
  limite integer := least(greatest(coalesce(p_limite, 60), 1), 100);
  resultado jsonb;
begin
  if coalesce(cardinality(p_sinais), 0) > 12 or coalesce(cardinality(p_vetos), 0) > 12
     or coalesce(cardinality(p_categorias), 0) > 8 then
    raise exception 'leitura: no maximo 12 sinais, 12 vetos e 8 categorias'
      using errcode = '22023';
  end if;
  if cardinality(sinais) = 0 then
    raise exception 'leitura: nenhum sinal valido (3 a 40 caracteres)'
      using errcode = '22023';
  end if;

  select o.observado_em into painel
  from public.observacoes_publicadas_do_painel o
  where o.segmento = 'feminino_casual_br';
  if painel is null then
    return jsonb_build_object('painel_observado_em', null, 'total', 0, 'pecas', '[]'::jsonb);
  end if;

  with ativos as (
    select p.id, p.titulo, p.url, p.imagem_url, p.marca_id,
           p.ultimo_preco_atual, p.ultimo_preco_original,
           ep.ultimo_avistamento_em,
           lower(public.unaccent(p.titulo)) as t
    from public.produtos p
    join public.estado_dos_produtos ep on ep.produto_id = p.id
    where p.segmento = 'feminino_casual_br'
      and ep.ofertavel is true
      and ep.ultimo_avistamento_em between painel - 7 and painel
      and not exists (select 1 from public.produtos_de_catalogo_aposentado ca
                       where ca.produto_id = p.id)
      and (coalesce(cardinality(p_categorias), 0) = 0
           or exists (select 1 from public.produto_termos pt
                       where pt.produto_id = p.id
                         and pt.termo_id = any (p_categorias)))
  ), casados as (
    select a.*,
           (select count(*) from unnest(sinais) s where a.t like s) as forca
    from ativos a
    where a.t like any (sinais)
      and not (a.t like any (vetos))
  )
  select jsonb_build_object(
    'painel_observado_em', painel,
    'total', (select count(*) from casados),
    'pecas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'titulo', c.titulo, 'marca', m.nome,
               'preco', c.ultimo_preco_atual, 'preco_original', c.ultimo_preco_original,
               'imagem_url', c.imagem_url,
               'url', public.url_publica_produto(c.url, m.nome),
               'visto_em', c.ultimo_avistamento_em, 'sinais_casados', c.forca)
             order by c.forca desc, c.ultimo_avistamento_em desc, c.id)
      from (select * from casados
            order by forca desc, ultimo_avistamento_em desc, id
            limit limite) c
      join public.marcas m on m.id = c.marca_id), '[]'::jsonb))
  into resultado;
  return resultado;
end;
$function$;

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
    select p.id, m.nome as marca, p.ultimo_preco_atual as preco,
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
        'pecas', (select count(*) from pecas where primeiro_avistamento >= painel - 29),
        'provas', coalesce((select jsonb_agg(id order by id) from pecas where primeiro_avistamento >= painel - 29), '[]')),
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

revoke all on function public.candidatas_da_leitura(text[], text[], text[], integer) from public, anon, authenticated;
revoke all on function public.fatos_da_leitura(bigint[], numeric) from public, anon, authenticated;
grant execute on function public.candidatas_da_leitura(text[], text[], text[], integer) to service_role;
grant execute on function public.fatos_da_leitura(bigint[], numeric) to service_role;

comment on function public.candidatas_da_leitura(text[], text[], text[], integer) is
  'A64: pecas ativas do painel publicado que casam com os sinais de construcao da leitura especifica e com nenhum veto; sinais sao texto escapado, nunca padrao.';
comment on function public.fatos_da_leitura(bigint[], numeric) is
  'A64: numeros da leitura especifica sobre as pecas verificadas, cada fato com as pecas que o provam.';
