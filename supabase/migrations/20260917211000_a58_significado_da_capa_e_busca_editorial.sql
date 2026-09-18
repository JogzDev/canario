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
-- fotos dos cartoes) vem limitados por marca, sem repetir peca, e nunca
-- alimentam contagem. A janela e explicita e a resposta devolve `de`, `ate` e
-- `dias_desde_o_fim` para a tela declarar idade em vez de chamar dado de 15
-- dias de "esta semana".
--
-- `pecas_ofertadas` e `por_mil_ofertadas` viajam junto porque comparar marcas
-- de tamanhos diferentes exige denominador (DAT-04). A funcao NAO escolhe o
-- ranking: devolve as duas leituras e a ordenacao por contagem; qual vira
-- manchete e decisao de produto, tomada com o numero na mao.
--
-- A JANELA E COMUM AOS TIPOS DE EVENTO
-- ====================================
--
-- A primeira versao ancorava a janela no ultimo evento DAQUELE TIPO
-- (`max(e.data) where e.tipo = $1`). Dois defeitos:
--
--   1. cada aba da tela falava de uma semana diferente, e as contagens de
--      reposicao e remarcacao deixavam de ser comparaveis entre si;
--   2. pior: ausencia recente virava atividade antiga. Uma coleta saudavel de
--      hoje sem nenhuma remarcacao recuava ate a ultima remarcacao registrada
--      -- semanas atras -- e apresentava aquele dia como "esta semana". O
--      defeito que a A57 corrigiu nos similares, com outro disfarce.
--
-- A ancora passa a ser a OBSERVACAO DO PAINEL (o ultimo dia em que o coletor
-- viu o segmento), comum aos tres tipos, ou um `ate` explicito de quem
-- pergunta. Coleta recente sem eventos do tipo devolve ZERO naquela janela,
-- que e a verdade, em vez de mudar de assunto.
--
-- O DENOMINADOR E OBSERVADO, NAO O ESTADO DE HOJE
-- ===============================================
--
-- A primeira versao desta funcao contava `estado_dos_produtos` no momento da
-- consulta e chamava isso de "sortimento da janela". Funciona por coincidencia
-- enquanto o banco esta congelado perto da data da janela, e passa a mentir no
-- dia em que a coleta voltar: a taxa de uma semana de agosto sairia dividida
-- pelo sortimento de hoje.
--
-- O denominador passa a ser o SORTIMENTO OBSERVADO NO FIM DA JANELA,
-- reconstruido dos snapshots e materializado em `sortimento_diario`. Duas
-- razoes para materializar em vez de reconstruir a cada consulta, as duas
-- medidas em 17/09/2026 contra o banco de producao:
--
--   lateral por produto (77.465 lookups) ....... 9,9 s
--   distinct on sobre 241 mil snapshots ........ 2,7 s
--   leitura de sortimento_diario ............... indice, milissegundos
--
-- O teto do papel `anon` e 3 s. Materializar tambem torna o denominador
-- auditavel e historico: 15 linhas por dia coletado, ~5,5 mil por ano.
--
-- Quando nao ha linha para a data da janela, `pecas_ofertadas` e
-- `por_mil_ofertadas` voltam nulos e `denominador_em` vem nulo. Sem
-- denominador a tela mostra contagem absoluta e cala a taxa -- nunca
-- substitui o denominador da janela pelo de hoje.
--
-- E SO CONTA QUEM FOI OBSERVADO NAQUELE DIA (P17)
-- ===============================================
--
-- `snapshot` e diferencial: o coletor so abre linha quando preco, grade ou
-- ofertabilidade mudam -- mas reabre de qualquer jeito a cada 7 dias
-- (batimento semanal da B3, `_precisa_snapshot`). Por isso o ultimo snapshot
-- de um produto vale por 7 dias e nao para sempre: e a mesma regra que a P17
-- ja usa na serie (`s.data + 6`).
--
-- A primeira versao pegava `distinct on (produto_id) ... where s.data <= alvo`
-- SEM piso: um produto visto em maio, nunca mais revisto, continuava contando
-- como ofertavel em setembro. O denominador inchava com catalogo morto e a
-- taxa de todas as marcas saia menor do que e. A janela agora e
-- `alvo - 6 .. alvo`.
--
-- RECOMPUTAR UM DIA CORRIGE PARA BAIXO, NAO SO PARA CIMA
-- ======================================================
--
-- `on conflict do update` sozinho e um upsert que nunca apaga: se uma marca
-- deixa de ter pecas ofertaveis num dia ja computado, a linha antiga fica la,
-- fantasma, e a taxa continua sendo dividida por um sortimento que nao existe
-- mais. A recomputacao remove os grupos que sumiram do calculo -- inclusive os
-- que passam a zero.
--
-- Com uma excecao declarada: dia SEM NENHUM snapshot na janela e dia nao
-- observado (nunca coletado, ou ja podado pelos 21 dias da A42). Recomputar um
-- dia desses apagaria o denominador historico e o trocaria por zero. A funcao
-- sai sem tocar em nada.
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

create table if not exists public.sortimento_diario (
  data date not null,
  marca_id bigint not null references public.marcas(id) on delete cascade,
  segmento text not null,
  pecas_ofertadas integer not null,
  primary key (data, marca_id, segmento)
);

comment on table public.sortimento_diario is
  'A58: sortimento ofertavel por marca no fim de cada dia observado, reconstruido dos snapshots. Denominador auditavel das comparacoes entre marcas.';

alter table public.sortimento_diario enable row level security;
revoke all on table public.sortimento_diario from anon, authenticated;

-- O calculo de um dia, em um lugar so: a reconstrucao e usada tanto para
-- gravar quanto para decidir o que apagar, e duas copias divergiriam.
create or replace function public.sortimento_observado(alvo date)
returns table (marca_id bigint, segmento text, pecas_ofertadas integer)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with ultimo as (
    -- P17: o snapshot vale por sete dias, nao para sempre. Quem nao foi
    -- observado dentro da janela nao entra no denominador daquele dia.
    select distinct on (s.produto_id) s.produto_id, s.ofertavel
    from public.snapshots s
    where s.data between alvo - 6 and alvo
    order by s.produto_id, s.data desc
  )
  select p.marca_id, p.segmento, count(*)::int
  from ultimo u
  join public.produtos p on p.id = u.produto_id
  where u.ofertavel is true
    and p.segmento is not null
  group by p.marca_id, p.segmento;
$function$;

comment on function public.sortimento_observado(date) is
  'A58: sortimento ofertavel por (marca, segmento) no dia, pela janela de observacao de sete dias da P17.';

revoke all on function public.sortimento_observado(date) from public, anon, authenticated;
grant execute on function public.sortimento_observado(date) to service_role;

-- Reconstroi um dia. Roda com a chave de servico, no fim da coleta saudavel e
-- ANTES da poda; nunca no caminho da consulta.
create or replace function public.computar_sortimento_diario(dia date default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  alvo date;
  observado boolean;
  gravadas integer;
  removidas integer;
begin
  alvo := coalesce(dia, (select max(s.data) from public.snapshots s));
  if alvo is null then
    return 0;
  end if;

  -- Dia sem snapshot na janela e dia NAO OBSERVADO. Pode ser um dia que nunca
  -- foi coletado ou um dia cujo cru a poda ja levou (21 dias, A42). Nos dois
  -- casos, recomputar apagaria o denominador historico e o trocaria por zero.
  select exists (select 1 from public.snapshots s
                  where s.data between alvo - 6 and alvo)
    into observado;
  if not observado then
    return 0;
  end if;

  -- Calcula uma vez e usa duas: apagar o fantasma e gravar o que mudou.
  -- `to_regclass` em vez de `drop ... if exists` porque a segunda avisa em
  -- NOTICE a cada chamada, e o backfill chama uma vez por dia coletado.
  if to_regclass('pg_temp.sortimento_calculado') is not null then
    drop table pg_temp.sortimento_calculado;
  end if;
  create temp table pg_temp.sortimento_calculado on commit drop as
  select * from public.sortimento_observado(alvo);

  -- Linha fantasma: grupo que existia numa execucao anterior deste mesmo dia
  -- e sumiu do calculo -- a marca que passou a zero ofertaveis, o segmento que
  -- mudou. Sem isto, recomputar so corrige para cima.
  delete from public.sortimento_diario sd
  where sd.data = alvo
    and not exists (select 1 from pg_temp.sortimento_calculado c
                     where c.marca_id = sd.marca_id
                       and c.segmento = sd.segmento);
  get diagnostics removidas = row_count;

  insert into public.sortimento_diario (data, marca_id, segmento, pecas_ofertadas)
  select alvo, c.marca_id, c.segmento, c.pecas_ofertadas
  from pg_temp.sortimento_calculado c
  on conflict (data, marca_id, segmento) do update
    set pecas_ofertadas = excluded.pecas_ofertadas
    -- P11: escrever so o que mudou.
    where public.sortimento_diario.pecas_ofertadas
          is distinct from excluded.pecas_ofertadas;
  get diagnostics gravadas = row_count;

  drop table pg_temp.sortimento_calculado;
  -- Zero significa "nada mudou": reexecutar o mesmo dia e barato e silencioso.
  return gravadas + removidas;
end;
$function$;

revoke all on function public.computar_sortimento_diario(date) from public, anon, authenticated;
-- A coleta e o motor rodam com a chave de servico. Sem este grant a funcao
-- existe e nao roda: `revoke ... from public` tira o default de EXECUTE de
-- todo mundo, inclusive de quem precisa chamar.
grant execute on function public.computar_sortimento_diario(date) to service_role;

-- Historico disponivel: a retencao de snapshots cobre 22 dias (12/08 a 02/09
-- em 17/09/2026). Fora dessa janela nao existe denominador, e a funcao de
-- consulta declara isso em vez de inventar.
do $$
declare
  d date;
begin
  for d in select distinct s.data from public.snapshots s order by 1 loop
    perform public.computar_sortimento_diario(d);
  end loop;
end $$;

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
        select max(ep.ultimo_avistamento_em)
        from public.estado_dos_produtos ep
        join public.produtos p on p.id = ep.produto_id
        where p.segmento = 'feminino_casual_br')) as ate
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
      select u.*, row_number() over (
               partition by u.marca order by u.data desc, u.id desc) as posicao
      from uma_por_peca u
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

comment on function public.resumo_de_eventos(text, integer, integer, date) is
  'A58: agregacao da janela inteira em produtos distintos, em janela comum ancorada na observacao do painel, com denominador observado no fim da janela; exemplos sem peca repetida e nunca alimentando contagem.';

revoke all on function public.resumo_de_eventos(text, integer, integer, date) from public;
grant execute on function public.resumo_de_eventos(text, integer, integer, date)
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
    -- `%` e `_` do usuario sao escapados: a expressao e dado, nao padrao. A
    -- barra vem primeiro porque ela e o proprio caractere de escape do LIKE:
    -- escapar `%` antes de `\` dobraria a barra que acabou de ser escrita.
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

-- O DENOMINADOR SE RECONSTROI NO FIM DA COLETA SAUDAVEL, ANTES DA PODA
-- ====================================================================
--
-- O lugar nao e o workflow: e aqui. `computar_motor` so roda depois do portao
-- de saude do pipeline diario, roda com a chave de servico, roda numa unica
-- transacao com o lock da publicacao -- e e ele que chama a poda. Colocar a
-- reconstrucao um passo antes de `podar_snapshots(21)` torna impossivel podar
-- um dia sem antes ter gravado o denominador dele, mesmo que alguem reordene o
-- YAML depois. Dia podado e dia irreconstruivel: e uma porta de sentido unico.
create or replace function public.computar_motor()
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  r_eventos integer;
  r_varejo integer;
  r_editorial integer;
  r_z integer;
  r_indice integer;
  r_curva integer;
  r_raridade integer;
  r_sortimento integer;
  r_snapshots_removidos integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:publicacao-do-motor', 0));

  r_eventos := public.computar_eventos();
  r_varejo := public.computar_serie_varejo();
  r_editorial := public.computar_serie_editorial();
  r_z := public.computar_z();
  r_indice := public.computar_indice();
  r_curva := public.computar_curva_tamanhos();
  r_raridade := public.computar_raridade();

  -- A58: ultima chance de ler o cru do dia. Depois da poda, o denominador
  -- daquele dia nao existe mais em lugar nenhum.
  r_sortimento := public.computar_sortimento_diario();

  -- Todos os consumidores do cru ja terminaram; mantemos o piso seguro da A30.
  r_snapshots_removidos := public.podar_snapshots(21);

  return jsonb_build_object(
    'computar_eventos', r_eventos,
    'computar_serie_varejo', r_varejo,
    'computar_serie_editorial', r_editorial,
    'computar_z', r_z,
    'computar_indice', r_indice,
    'computar_curva_tamanhos', r_curva,
    'computar_raridade', r_raridade,
    'computar_sortimento_diario', r_sortimento,
    'snapshots_removidos', r_snapshots_removidos
  );
end;
$function$;

comment on function public.computar_motor() is
  'A58: mesma sequencia da A42 com a reconstrucao do denominador diario imediatamente antes da poda do cru.';

revoke execute on function public.computar_motor()
  from public, anon, authenticated;
grant execute on function public.computar_motor() to service_role;
