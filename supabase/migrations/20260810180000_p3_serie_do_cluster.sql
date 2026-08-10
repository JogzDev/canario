-- Série semanal do índice do cluster — o gráfico da tela da peça (A14).
--
-- POR QUE ELA EXISTE
-- ==================
--
-- O Figma da Bianca e do Davi traz "Métricas da peça" com um gráfico de linha.
-- Lido ao pé da letra, aquilo promete acompanhar A PEÇA DO USUÁRIO ao longo do
-- tempo — o closet que a §34 exclui, e que o dado não sustenta: a peça é do
-- cliente, não está no painel, e nenhuma marca que medimos vende ela.
--
-- Decisão do JP em 07/08: o gráfico passa a ser dos ATRIBUTOS dela. A tela fica
-- idêntica e a afirmação vira verdadeira — "vestido + preto + elastano" é um
-- recorte do mercado que a gente mede há cinco anos, e o movimento dele é
-- exatamente o que interessa a quem vai posicionar a peça.
--
-- O MESMO PESO DO PONTO, SEMANA A SEMANA
-- ======================================
--
-- `indice_do_cluster()` já pondera cada atributo pela raridade (K5): `liso`
-- descreve 61 peças de 100 e não pode pesar o mesmo que `festa_brilho`. Esta
-- função repete a MESMA ponderação e o MESMO recorte de categoria.
--
-- A raridade é chaveada por (categoria, termo_id) — nove linhas por termo, uma
-- por categoria mais `(todas)`. A primeira versão desta função esqueceu esse
-- recorte, o join multiplicou por nove, e ela reportou "27 atributos com peso"
-- para três atributos pedidos. O número saía plausível e estava errado.
--
-- O QUE NÃO ESPERAR: o último ponto do gráfico NÃO é igual ao número grande da
-- tela, e não deve ser. O número grande é a leitura mais recente de CADA
-- atributo, que pode vir de semanas diferentes; o ponto é o que havia NAQUELA
-- semana. Medido em 10/08 para vestido+preto+floral: −0,43 contra −0,57, com o
-- último ponto sustentado por um atributo só.
--
-- HONESTIDADE DA COBERTURA
-- ========================
--
-- Cada semana carrega `n_atributos` (quantos dos atributos pedidos tinham
-- leitura naquela semana). Semana com 1 de 3 atributos não é comparável com
-- semana com 3 de 3, e a tela precisa poder mostrar isso em vez de desenhar uma
-- linha contínua que finge cobertura constante. A regra 3 pede o caminho até a
-- origem; aqui ele é o número de atributos que sustentaram cada ponto.

create or replace function public.serie_do_cluster(
  termos text[],
  semanas integer default 52
)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with pedido as (
    select unnest(termos) as termo_id
  ),
  pesos as (
    -- Só atributo com raridade computada entra, igual ao ponto: sem peso não
    -- há como ponderar, e ponderar por 1 seria inventar um peso.
    select p.termo_id, r.peso
    from pedido p
    join public.raridade_do_atributo r on r.termo_id = p.termo_id
    where r.peso is not null
  ),
  pontos as (
    select i.semana,
           sum(i.indice * w.peso) / nullif(sum(w.peso), 0) as indice,
           count(*)                                        as n_atributos,
           sum(i.n_pernas)                                 as pernas_somadas
    from public.indices_semanais i
    join pesos w on w.termo_id = i.termo_id
    where i.segmento = 'feminino_casual_br'
      and i.indice is not null
      and i.estado is not null          -- §22: sem duas pernas não há direção
      and i.semana >= (current_date - (semanas * 7))
    group by i.semana
  )
  select jsonb_build_object(
    'unidade', 'desvios contra a própria história de cada atributo',
    'atributos_pedidos', coalesce(array_length(termos, 1), 0),
    'atributos_com_peso', (select count(*) from pesos),
    'semanas_pedidas', semanas,
    'pontos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'semana', semana,
               'indice', round(indice, 4),
               'n_atributos', n_atributos)
             order by semana)
      from pontos), '[]'::jsonb),
    'obs', 'Média ponderada pela raridade (K5), a mesma do número grande. '
        || 'Semana sem estado em nenhum atributo não vira ponto: a §22 só '
        || 'afirma direção com duas fontes concordando.'
  );
$$;

comment on function public.serie_do_cluster(text[], integer) is
  'A14: série semanal do índice do cluster, para o gráfico da tela da peça. É o movimento dos ATRIBUTOS da peça, e não da peça do usuário -- que não está no painel e a §34 exclui acompanhar.';

grant execute on function public.serie_do_cluster(text[], integer)
  to anon, authenticated;
