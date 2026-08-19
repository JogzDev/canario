-- P12: o motor para de apagar e reinserir as 208 mil ligações toda noite.
--
-- O MESMO PADRÃO DO P11, UMA TABELA ADIANTE
-- =========================================
--
-- `publicar_atributos` publicava a taxonomia assim:
--
--   delete from public.produto_termos where origem = 'titulo';
--   insert into public.produto_termos (produto_id, termo_id, origem)
--   select produto_id, termo_id, 'titulo' from public.motor_termos_stage ...
--
-- Apaga a tabela inteira e reescreve, toda execução do motor. Medido em
-- 19/08/2026: 208.811 linhas apagadas e 208.811 reinseridas por noite, para um
-- conjunto que quase não muda -- as ligações vêm do matcher sobre o TÍTULO do
-- produto, e título de produto não muda de um dia para o outro.
--
-- O custo não está no heap, que é pequeno (9,5 MiB úteis). Está no índice: são
-- duas estruturas, `produto_termos_pkey` e `produto_termos_por_termo`, e cada
-- noite apagava e reinseria 208 mil entradas nas duas. Antes do VACUUM FULL de
-- hoje a tabela estava com 22 MiB de heap e 32 MiB de índice para 9,5 MiB de
-- dado -- 43% de aproveitamento. Depois do VACUUM FULL: 11 e 15,8, com 86%.
--
-- Sem esta migração, aqueles 27 MiB voltam sozinhos em poucos dias.
--
-- A CORREÇÃO: MEXER SÓ NA DIFERENÇA
-- =================================
--
-- Duas anti-junções no lugar do apaga-tudo:
--
--   * apaga a ligação que existe e não está mais no stage;
--   * insere a ligação que está no stage e ainda não existe;
--   * quem está nos dois lados não é tocado -- que é a esmagadora maioria.
--
-- As duas são servidas por índice, por prefixo exato, sem varredura:
--
--   motor_termos_stage_pkey    (execucao, produto_id, termo_id)
--   produto_termos_pkey        (produto_id, termo_id, origem)
--
-- A PK do stage também garante que não há par (produto_id, termo_id) repetido
-- dentro de uma execução -- do contrário a inserção diferencial poderia tentar
-- gravar o mesmo par duas vezes e violar a PK de destino.
--
-- O ESCOPO `origem = 'titulo'` CONTINUA, E É ESSENCIAL
-- ====================================================
--
-- `produto_termos.origem` aceita 'titulo', 'visao' e 'manual'. Hoje as 208.811
-- linhas são todas 'titulo', mas o motor só é dono das dessa origem: ligação
-- vinda de visão ou curadoria manual não pode ser apagada por ele. A anti-junção
-- da remoção é escopada, como o `delete` era.
--
-- Produto que sai do catálogo não deixa ligação órfã: ele some do stage, então
-- suas ligações caem na primeira condição. (A FK para `produtos` já impediria o
-- órfão de existir de qualquer forma.)
--
-- O QUE O RETORNO PASSA A DIZER
-- =============================
--
-- `ligacoes` continua significando o total publicado, contado no stage, para não
-- quebrar quem lê `motor_execucoes.resultado`. `ligacoes_inseridas` e
-- `ligacoes_removidas` são novos e mostram o trabalho real -- devem ficar na casa
-- das dezenas ou centenas por noite. Se voltarem para as centenas de milhares,
-- alguma coisa está reescrevendo o conjunto inteiro de novo.
--
-- Reverter: voltar ao `delete ... where origem = 'titulo'` seguido do insert
-- direto do stage.

create or replace function public.publicar_atributos(p_execucao uuid,
                                                     p_total integer)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  produtos_stage integer;
  produtos_vivos integer;
  produtos_cobertos integer;
  produtos_alterados integer;
  ligacoes_publicadas integer;
  ligacoes_inseridas integer;
  ligacoes_removidas integer;
begin
  -- A mesma trava é usada por `computar_motor`: publicação manual concorrente
  -- espera, em vez de misturar uma taxonomia com cálculos de outra execução.
  perform pg_advisory_xact_lock(
    hashtextextended('canario:publicacao-do-motor', 0));

  if p_execucao is null or p_total is null or p_total < 1 then
    raise exception 'execucao e total positivo sao obrigatorios';
  end if;

  select count(*) into produtos_stage
  from public.motor_produtos_stage
  where execucao = p_execucao;
  select count(*) into produtos_vivos from public.produtos;

  if produtos_stage <> p_total or produtos_vivos <> p_total then
    raise exception
      'stage incompleto para %: declarados %, preparados %, vivos %',
      p_execucao, p_total, produtos_stage, produtos_vivos;
  end if;

  select count(*) into ligacoes_publicadas
  from public.motor_termos_stage
  where execucao = p_execucao;

  -- O `analyze` NÃO é zelo: é o que decide entre 2 s e um motor travado.
  -- O stage é preenchido segundos antes desta chamada e o autovacuum ainda não
  -- passou por ele, então o planejador o vê como tabela vazia. Medido em
  -- 19/08/2026 com 208.811 linhas dos dois lados:
  --
  --   sem estatística   Nested Loop Anti Join com Seq Scan no stage
  --                     (uma varredura da tabela inteira por linha)
  --   com estatística   Merge Anti Join pelos dois índices
  --                     delete 2,05 s + insert 0,61 s
  --
  -- Isso não importava antes porque o `delete` era incondicional e o `insert`
  -- não tinha junção. Passa a importar agora, e por isso está aqui e não na
  -- esperança de que o autovacuum chegue a tempo.
  analyze public.motor_termos_stage;

  -- P12: só a diferença. O escopo `origem = 'titulo'` é obrigatório -- o motor
  -- não é dono das ligações de visão nem das manuais.
  delete from public.produto_termos pt
  where pt.origem = 'titulo'
    and not exists (
      select 1 from public.motor_termos_stage s
      where s.execucao = p_execucao
        and s.produto_id = pt.produto_id
        and s.termo_id = pt.termo_id);
  get diagnostics ligacoes_removidas = row_count;

  insert into public.produto_termos (produto_id, termo_id, origem)
  select s.produto_id, s.termo_id, 'titulo'
  from public.motor_termos_stage s
  where s.execucao = p_execucao
    and not exists (
      select 1 from public.produto_termos pt
      where pt.produto_id = s.produto_id
        and pt.termo_id = s.termo_id
        and pt.origem = 'titulo');
  get diagnostics ligacoes_inseridas = row_count;

  -- P11: completude medida ANTES de escrever, contra o stage, porque o update
  -- abaixo toca só o que mudou.
  select count(*) into produtos_cobertos
  from public.motor_produtos_stage s
  join public.produtos p on p.id = s.produto_id
  where s.execucao = p_execucao;

  if produtos_cobertos <> p_total then
    raise exception
      'publicacao incompleta para %: esperados %, cobertos %',
      p_execucao, p_total, produtos_cobertos;
  end if;

  -- P11: só o que mudou. `is distinct from` porque 10,8% dos segmentos são
  -- NULL, e `<>` com NULL devolve NULL.
  update public.produtos p
  set segmento = s.segmento
  from public.motor_produtos_stage s
  where s.execucao = p_execucao and s.produto_id = p.id
    and p.segmento is distinct from s.segmento;
  get diagnostics produtos_alterados = row_count;

  -- P10: `truncate` no lugar de `delete`, para devolver as páginas de índice.
  truncate table public.motor_termos_stage, public.motor_produtos_stage;

  return jsonb_build_object(
    'produtos', produtos_cobertos,
    'produtos_alterados', produtos_alterados,
    'ligacoes', ligacoes_publicadas,
    'ligacoes_inseridas', ligacoes_inseridas,
    'ligacoes_removidas', ligacoes_removidas
  );
end;
$function$;

comment on function public.publicar_atributos(uuid, integer) is
  'Troca atômica da taxonomia publicada. P10: limpa o estágio com truncate. P11: só escreve segmento que mudou. P12: ligações são diferenciais, em vez de apagar e reinserir 208 mil linhas por noite.';
