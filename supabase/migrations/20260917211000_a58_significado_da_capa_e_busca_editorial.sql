-- A58: a manchete conta o que promete, e a busca acha a materia.
--
-- POR QUE (1): A CAPA ESTAVA ERRADA, NAO SO IMPRECISA
-- ===================================================
--
-- A tela "Esta semana" pedia `eventos_recentes(tipo, 120)`, agrupava por marca
-- e escrevia a contagem da AMOSTRA como se fosse a do mercado. Medido em
-- 17/09/2026 sobre o dado que esta no app:
--
--   reposicao de 01/09: 505 eventos reais no painel, 120 entregues.
--     real     -> Le Lis Blanc 289 | C&A 52 | Farm 52 | Maria Filo 43
--     amostra  -> C&A 52 | Farm 17 | Lanca Perfume 15 | Le Lis Blanc 12
--   remarcacao de 02/09: 917 reais, 120 entregues.
--     real     -> Maria Filo 698 | Farm 115 | C&A 98
--     amostra  -> C&A 66 | Maria Filo 36 | Farm 17
--
-- A manchete deu a capa para a C&A quando a maior reposicao do dia foi da Le
-- Lis Blanc, e disse "Maria Filo baixou o preco de 36 pecas" quando foram 698.
-- O corte por `order by data desc, id desc` premia quem foi GRAVADO por
-- ultimo, nao quem repos mais -- parte do "peso da C&A" era ordem de insercao.
--
-- Esta funcao separa as duas coisas que estavam juntas: a AGREGACAO percorre a
-- populacao inteira da janela e conta PRODUTOS DISTINTOS; os EXEMPLOS (as
-- fotos dos cartoes) vem limitados por marca e nunca alimentam contagem. A
-- janela e explicita, ancorada no ultimo dia coletado, e a resposta devolve
-- `de`, `ate` e `dias_desde_o_fim` para a tela declarar idade em vez de
-- chamar dado de 15 dias de "esta semana".
--
-- `pecas_ofertadas` e `por_mil_ofertadas` viajam junto porque comparar marcas
-- de tamanhos diferentes exige denominador (DAT-04). A funcao NAO escolhe o
-- ranking: devolve as duas leituras e a ordenacao por contagem; qual vira
-- manchete e decisao de produto, tomada com o numero na mao.
--
-- POR QUE (2): "NAPOLEON JACKET" JA ESTAVA NO BANCO
-- =================================================
--
-- O JP pesquisou a expressao exata de uma manchete que o proprio app exibia e
-- recebeu apenas "Casacos e jaquetas": a busca reduz a frase a taxonomia e
-- descarta o resto em silencio. O titulo esta gravado -- 1 entre 172.649
-- artigos, Refinery29, 31/08/2026 --, mas `anon` nao le `artigos`.
--
-- `buscar_referencia_editorial` abre so o que a tela ja mostra hoje em "Na
-- imprensa" (titulo, veiculo, data, URL), pelo mesmo recorte de publico que o
-- painel admite (`publico_editorial <> 'masculino'`), sem `select` geral na
-- tabela. O corpo da materia NAO esta no banco: por isso a funcao devolve
-- referencia, nunca resumo -- titulo e metadado nao autorizam reconstituir
-- reportagem.
--
-- Sem indice de texto: `ilike` em 172 mil titulos custa uma varredura, medida
-- em ~0,1 s, e o teto do papel `anon` e 3 s. `pg_trgm` entra depois da folga
-- de espaco, se a medicao pedir.

create or replace function public.resumo_de_eventos(tipo_evento text,
                                                    dias integer default 7,
                                                    exemplos_por_marca integer default 6)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with par as (
    select least(greatest(coalesce($2, 7), 1), 31) as janela,
           least(greatest(coalesce($3, 6), 1), 12) as teto
  ), janela as (
    select par.janela, par.teto, lim.ate, lim.ate - (par.janela - 1) as de
    from par
    cross join lateral (
      select max(e.data) as ate
      from public.eventos e
      join public.produtos p on p.id = e.produto_id
      where e.tipo = $1
        and $1 in ('reposicao', 'remarcacao', 'saida_de_linha')
        and p.segmento = 'feminino_casual_br'
    ) lim
    where lim.ate is not null
  ), no_periodo as (
    select e.id, e.produto_id, e.data, e.detalhe, m.nome as marca,
           p.titulo, p.imagem_url,
           case when ep.ultimo_snapshot_em >= j.ate - 14
                then public.url_publica_produto(p.url, m.nome) end as url_da_peca,
           exists (select 1 from public.eventos h
                    where h.produto_id = e.produto_id
                      and h.tipo = e.tipo
                      and h.data < j.de) as repetida,
           (e.detalhe->>'queda_pct')::numeric as queda_pct
    from janela j
    join public.eventos e
      on e.tipo = $1 and e.data between j.de and j.ate
    join public.produtos p
      on p.id = e.produto_id and p.segmento = 'feminino_casual_br'
    join public.marcas m on m.id = p.marca_id
    join public.estado_dos_produtos ep on ep.produto_id = p.id
  ), sortimento as (
    -- Denominador da MESMA janela: produtos que a marca tinha ofertaveis
    -- quando a janela foi observada. Sem isso, "quem repos mais" premia
    -- automaticamente o maior catalogo.
    select m.nome as marca, count(*)::int as pecas_ofertadas
    from janela j
    join public.estado_dos_produtos ep
      on ep.ofertavel is true and ep.ultimo_avistamento_em >= j.de
    join public.produtos p
      on p.id = ep.produto_id and p.segmento = 'feminino_casual_br'
    join public.marcas m on m.id = p.marca_id
    group by m.nome
  ), tamanhos as (
    select np.marca, tam.valor as tamanho, count(*) as n
    from no_periodo np
    cross join lateral jsonb_array_elements_text(
      coalesce(np.detalhe->'tamanhos', '[]'::jsonb)) tam(valor)
    group by np.marca, tam.valor
  ), tamanhos_top as (
    select marca, jsonb_agg(tamanho order by posicao) as tamanhos
    from (
      select marca, tamanho,
             row_number() over (partition by marca order by n desc, tamanho) as posicao
      from tamanhos
    ) t
    where posicao <= 3
    group by marca
  ), exemplos as (
    select x.marca, jsonb_agg(jsonb_build_object(
             'peca', x.titulo,
             'imagem', x.imagem_url,
             'url_da_peca', x.url_da_peca,
             'data', x.data,
             'repetida', x.repetida,
             'queda_pct', x.queda_pct,
             'tamanhos', coalesce(x.detalhe->'tamanhos', '[]'::jsonb))
             order by x.posicao) as exemplos
    from (
      select np.*, row_number() over (
               partition by np.marca order by np.data desc, np.id desc) as posicao
      from no_periodo np
    ) x
    cross join janela j
    where x.posicao <= j.teto
    group by x.marca
  ), por_marca as (
    select np.marca,
           count(distinct np.produto_id)::int as pecas,
           count(*)::int as eventos,
           count(distinct np.produto_id) filter (where np.repetida)::int
             as pecas_repetidas,
           max(np.queda_pct) as maior_queda_pct
    from no_periodo np
    group by np.marca
  )
  select jsonb_build_object(
    'tipo', $1,
    'de', (select de from janela),
    'ate', (select ate from janela),
    'dias', (select janela from janela),
    'dias_desde_o_fim', (select current_date - ate from janela),
    'unidade', 'produtos distintos com evento na janela',
    'total_pecas', (select count(distinct produto_id)::int from no_periodo),
    'total_eventos', (select count(*)::int from no_periodo),
    'marcas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'marca', pm.marca,
        'pecas', pm.pecas,
        'eventos', pm.eventos,
        'pecas_repetidas', pm.pecas_repetidas,
        'maior_queda_pct', pm.maior_queda_pct,
        'pecas_ofertadas', s.pecas_ofertadas,
        'por_mil_ofertadas', case when coalesce(s.pecas_ofertadas, 0) > 0
          then round(1000.0 * pm.pecas / s.pecas_ofertadas, 1) end,
        'tamanhos', coalesce(tt.tamanhos, '[]'::jsonb),
        'exemplos', coalesce(ex.exemplos, '[]'::jsonb))
        order by pm.pecas desc, pm.marca)
      from por_marca pm
      left join sortimento s on s.marca = pm.marca
      left join tamanhos_top tt on tt.marca = pm.marca
      left join exemplos ex on ex.marca = pm.marca), '[]'::jsonb));
$function$;

comment on function public.resumo_de_eventos(text, integer, integer) is
  'A58: agregacao da janela inteira em produtos distintos, com denominador por marca; exemplos limitados nunca viram contagem.';

revoke all on function public.resumo_de_eventos(text, integer, integer) from public;
grant execute on function public.resumo_de_eventos(text, integer, integer)
  to anon, authenticated;

create or replace function public.buscar_referencia_editorial(expressao text,
                                                              limite integer default 5)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with par as (
    select btrim(coalesce($1, '')) as termo,
           least(greatest(coalesce($2, 5), 1), 10) as teto
  ), valida as (
    -- `%` e `_` do usuario sao escapados: a expressao e dado, nao padrao.
    select termo, teto,
           replace(replace(replace(termo, '\', '\\'), '%', '\%'), '_', '\_') as padrao
    from par
    where length(termo) between 3 and 80
  ), casam as (
    select a.id, a.titulo, a.veiculo, a.data_pub, a.url
    from valida v
    join public.artigos a on a.titulo ilike '%' || v.padrao || '%'
    where a.publico_editorial <> 'masculino'
  ), achados as (
    select * from casam
    order by data_pub desc nulls last, id desc
    limit (select teto from valida)
  )
  select jsonb_build_object(
    'expressao', (select termo from par),
    'buscavel', exists (select 1 from valida),
    'total', (select count(*)::int from casam),
    'materias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'titulo', titulo,
        'veiculo', veiculo,
        'data', data_pub,
        'url', url)
        order by data_pub desc nulls last, id desc)
      from achados), '[]'::jsonb));
$function$;

comment on function public.buscar_referencia_editorial(text, integer) is
  'A58: devolve referencia editorial (titulo, veiculo, data, URL) do mesmo recorte que o painel admite; nunca o corpo da materia, que o banco nao guarda.';

revoke all on function public.buscar_referencia_editorial(text, integer) from public;
grant execute on function public.buscar_referencia_editorial(text, integer)
  to anon, authenticated;
