-- P10: o estágio do motor devolve as páginas de índice ao terminar.
--
-- MEDIDO EM 19/08/2026
-- ====================
--
-- `motor_termos_stage` e `motor_produtos_stage` ficam VAZIAS entre execuções do
-- motor -- 0 linhas vivas as duas -- e mesmo assim carregavam 16,7 MB de índice:
--
--   motor_termos_stage_pkey       11 MB    com 0 linhas
--   motor_produtos_stage_pkey    3,3 MB    com 0 linhas
--   os dois índices `criado`     2,3 MB    com 0 linhas
--
-- São 4,5% de todo o banco, num projeto que estava a 78,6% do limite do plano.
--
-- A CAUSA
-- =======
--
-- `preparar_stage_motor()` faz `truncate` no COMEÇO da execução, e truncate
-- devolve as páginas. Mas a limpeza do FIM, em `publicar_atributos()`, usa
-- `delete`. `delete` remove as linhas e deixa as páginas de índice alocadas --
-- vazias, mas ocupando disco.
--
-- Como o motor roda uma vez por dia, o estágio passa ~23 horas por dia segurando
-- 16,7 MB que não guardam nada. O `REINDEX` manual de 19/08 recuperou o espaço,
-- mas ele voltaria na execução seguinte: sem esta migração é enxugar gelo.
--
-- POR QUE `truncate` É SEGURO AQUI, E NÃO SÓ MENOR
-- ================================================
--
-- O `delete` era escrito com `where execucao = p_execucao` para não apagar a
-- preparação de outra execução. Essa preocupação não tem como se materializar:
--
--   * `preparar_stage_motor()` levanta exceção se existe execução `queued` ou
--     `running`, e trunca as duas tabelas antes de qualquer inserção;
--   * `solicitar_publicacao_motor()` levanta a mesma exceção antes de enfileirar.
--
-- Duas execuções nunca coexistem, então no momento da limpeza a única coisa nas
-- tabelas é a execução que está publicando. `truncate` remove exatamente o mesmo
-- conjunto de linhas que os dois `delete` removiam -- e a limpeza de resíduo de
-- dois dias vira redundante, porque não sobra resíduo.
--
-- `truncate` é transacional no Postgres: continua dentro da mesma transação de
-- `publicar_motor()`, e se um cálculo posterior falhar, ele é revertido junto e
-- o estágio volta a existir para diagnóstico. Nada muda nessa garantia.
--
-- O caminho de FALHA em `executar_publicacao_motor()` continua com `delete`, de
-- propósito: lá a transação da publicação já foi revertida, e o `delete` roda
-- numa transação nova onde uma execução concorrente é possível em teoria.
--
-- Reverter: trocar o `truncate` pelos dois `delete ... where execucao` e pelos
-- dois `delete ... where criado_em < now() - interval '2 days'`.

create or replace function public.publicar_atributos(p_execucao uuid,
                                                     p_total integer)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  produtos_stage integer;
  produtos_vivos integer;
  produtos_publicados integer;
  termos_publicados integer;
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

  -- DELETE + INSERT ficam invisíveis até o COMMIT desta chamada.
  delete from public.produto_termos where origem = 'titulo';

  insert into public.produto_termos (produto_id, termo_id, origem)
  select produto_id, termo_id, 'titulo'
  from public.motor_termos_stage
  where execucao = p_execucao;
  get diagnostics termos_publicados = row_count;

  update public.produtos p
  set segmento = s.segmento
  from public.motor_produtos_stage s
  where s.execucao = p_execucao and s.produto_id = p.id;
  get diagnostics produtos_publicados = row_count;

  if produtos_publicados <> p_total then
    raise exception
      'publicacao incompleta para %: esperados %, atualizados %',
      p_execucao, p_total, produtos_publicados;
  end if;

  -- P10: `truncate` no lugar de `delete`, para devolver as páginas de índice.
  -- Duas execuções nunca coexistem (ver o cabeçalho desta migração), então isto
  -- remove exatamente as mesmas linhas -- e dispensa a limpeza de resíduo de
  -- dois dias, que existia só para o caso que o truncate já resolve.
  truncate table public.motor_termos_stage, public.motor_produtos_stage;

  return jsonb_build_object(
    'produtos', produtos_publicados,
    'ligacoes', termos_publicados
  );
end;
$function$;

comment on function public.publicar_atributos(uuid, integer) is
  'Troca atômica da taxonomia publicada. P10: limpa o estágio com truncate, não delete, porque delete deixava 16,7 MB de página de índice alocada entre execuções.';
