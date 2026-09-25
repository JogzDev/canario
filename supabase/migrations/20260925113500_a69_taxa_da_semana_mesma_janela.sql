-- A69: uma semana de eventos nao pode ser dividida por um unico dia de
-- sortimento. Em 25/09, Dress To: 2.123 pecas remarcadas em sete dias,
-- 1.880 ofertadas no ultimo dia (113%), 6.226 com snapshot na janela (34,1%).
-- A nova taxa mede produtos distintos observados na mesma semana e inclui
-- eventos no denominador. Os campos A58 ficam para consumidores antigos;
-- a versao nova do app le apenas pecas_observadas/por_mil_observadas.
-- Nenhum historico de eventos, indice ou snapshot e reescrito.

create or replace function public.resumo_de_eventos(tipo_evento text,
                                                    dias integer default 7,
                                                    exemplos_por_marca integer default 6,
                                                    ate date default null)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with par as (
    select least(greatest(coalesce($2, 7), 1), 31) as janela,
           least(greatest(coalesce($3, 6), 1), 12) as teto
  ), janela as (
    -- JANELA COMUM AOS TIPOS. A ancora e a observacao do painel -- o ultimo
    -- dia em que o coletor viu o segmento --, ou um `ate` explicito de quem
    -- pergunta. Ancorar no ultimo evento DE CADA TIPO faria cada aba da tela
    -- falar de uma semana diferente e, pior, faria "nenhuma remarcacao nesta
    -- semana" recuar ate a ultima remarcacao registrada e apresenta-la como
    -- atual. Coleta recente sem eventos do tipo devolve zero nesta janela.
    select par.janela, par.teto, lim.ate, lim.ate - (par.janela - 1) as de
    from par
    cross join lateral (
      select coalesce($4, (
        select o.observado_em
        from public.observacoes_publicadas_do_painel o
        where o.segmento = 'feminino_casual_br')) as ate
    ) lim
    where lim.ate is not null
      and $1 in ('reposicao', 'remarcacao', 'saida_de_linha')
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
    -- Denominador OBSERVADO no fim da janela, nunca o estado de hoje. Sem
    -- linha para aquele dia, a marca sai sem denominador e a taxa nao e
    -- calculada.
    select m.nome as marca, sd.pecas_ofertadas
    from janela j
    join public.sortimento_diario sd
      on sd.data = j.ate and sd.segmento = 'feminino_casual_br'
    join public.marcas m on m.id = sd.marca_id
  ), observadas as (
    -- Mesma janela do numerador, para todas as modalidades de movimento.
    -- O evento tambem prova observacao: a uniao assegura que o numerador e
    -- subconjunto do denominador. Sem snapshot da marca nesta janela, a
    -- proporcao fica nula; evento antigo sozinho nao cria cobertura ficticia.
    select x.marca_id, count(*)::int as pecas_observadas
    from (
      select p.marca_id, s.produto_id
      from janela j
      join public.snapshots s on s.data between j.de and j.ate
      join public.produtos p on p.id = s.produto_id
        and p.segmento = 'feminino_casual_br'
      union
      select p.marca_id, e.produto_id
      from janela j
      join public.eventos e on e.data between j.de and j.ate
      join public.produtos p on p.id = e.produto_id
        and p.segmento = 'feminino_casual_br'
    ) x
    where exists (
      select 1 from janela j
      join public.snapshots s on s.data between j.de and j.ate
      join public.produtos p on p.id = s.produto_id
      where p.marca_id = x.marca_id
        and p.segmento = 'feminino_casual_br'
    )
    group by x.marca_id
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
  ), uma_por_peca as (
    -- Uma peca aparece uma vez na vitrine, pelo evento mais recente dela na
    -- janela. Sem isto, a peca que foi reposta tres vezes ocupa tres dos seis
    -- cartoes e a marca parece ter menos variedade do que tem.
    select distinct on (np.produto_id) np.*
    from no_periodo np
    order by np.produto_id, np.data desc, np.id desc
  ), escolhidos as (
    select x.*
    from (
      select u.*, row_number() over (
               partition by u.marca order by u.data desc, u.id desc) as posicao
      from uma_por_peca u
    ) x
    cross join janela j
    where x.posicao <= j.teto
  ), exemplos as (
    -- `ordinal` e `dias_desde_a_primeira` sao o sinal que o JP pediu em
    -- 31/07 -- "3a reposicao dos tamanhos PP/P em menos de 2 meses" --, e
    -- eram o unico motivo para a tela ainda depender de `eventos_recentes`.
    -- A subconsulta e por peca, entao roda DEPOIS do corte: no maximo 12 por
    -- marca, nunca sobre a populacao inteira da janela.
    select e.marca, jsonb_agg(jsonb_build_object(
             'peca', e.titulo,
             'imagem', e.imagem_url,
             'url_da_peca', e.url_da_peca,
             'data', e.data,
             'repetida', e.repetida,
             'ordinal', h.ordinal,
             'dias_desde_a_primeira', h.dias_desde_a_primeira,
             -- O `detalhe` inteiro, e nao campos escolhidos a dedo: e o mesmo
             -- objeto que `eventos_recentes` ja entrega, com `preco_de`,
             -- `preco_para`, `queda_pct` e `tamanhos`. A tela le os quatro
             -- para escrever "50% abaixo do preco anterior: R$ 799 -> R$ 400",
             -- e achatar aqui seria perder metade da frase.
             'detalhe', e.detalhe)
             order by e.posicao) as exemplos
    from escolhidos e
    cross join lateral (
      select count(*) filter (
               where (t.data, t.id) <= (e.data, e.id))::int as ordinal,
             nullif(e.data - min(t.data), 0) as dias_desde_a_primeira
      from public.eventos t
      where t.produto_id = e.produto_id and t.tipo = $1
    ) h
    group by e.marca
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
    'denominador_em', (select j.ate from janela j
                        where exists (select 1 from public.sortimento_diario sd
                                       where sd.data = j.ate
                                         and sd.segmento = 'feminino_casual_br')),
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
        'pecas_observadas', o.pecas_observadas,
        'por_mil_observadas', case when o.pecas_observadas > 0
          then round(1000.0 * pm.pecas / o.pecas_observadas, 1) end,
        'por_mil_ofertadas', case when coalesce(s.pecas_ofertadas, 0) > 0
          then round(1000.0 * pm.pecas / s.pecas_ofertadas, 1) end,
        'tamanhos', coalesce(tt.tamanhos, '[]'::jsonb),
        'exemplos', coalesce(ex.exemplos, '[]'::jsonb))
        order by pm.pecas desc, pm.marca)
      from por_marca pm
      left join sortimento s on s.marca = pm.marca
      left join public.marcas m on m.nome = pm.marca
      left join observadas o on o.marca_id = m.id
      left join tamanhos_top tt on tt.marca = pm.marca
      left join exemplos ex on ex.marca = pm.marca), '[]'::jsonb));
$function$;

comment on function public.resumo_de_eventos(text, integer, integer, date) is
  'A69: preserva A58; acrescenta proporcao por produtos distintos observados na mesma janela, com eventos incluidos no denominador e ausencia de snapshots declarada. Antes, Dress To tinha 2.123 eventos distintos / 1.880 pecas ofertadas no ultimo dia = 113%; na janela, 2.123 / 6.226 = 34,1%. A58: agregacao da janela inteira em produtos distintos, em janela comum ancorada na observacao do painel, com denominador observado no fim da janela; exemplos sem peca repetida e nunca alimentando contagem.';

revoke all on function public.resumo_de_eventos(text, integer, integer, date) from public;
-- acesso-publico: a tela semanal consulta esta agregacao sem revelar dados privados nem escrita.
grant execute on function public.resumo_de_eventos(text, integer, integer, date) to anon, authenticated;
