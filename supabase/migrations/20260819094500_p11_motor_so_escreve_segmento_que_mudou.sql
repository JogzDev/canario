-- P11: o motor para de reescrever 82 mil produtos por noite para não mudar nada.
--
-- O QUE A COLETA DE 19/08 REVELOU
-- ==============================
--
-- Foi a primeira coleta a rodar com P8 e P9 no lugar, e serviu de veredito:
--
--   antes   376.474.771 bytes   75,3% do plano
--   depois  486.141.075 bytes   97,2% do plano     +104,6 MiB numa noite
--
-- O portão de capacidade corta em 96%. A coleta seguinte seria bloqueada, e o
-- limite do plano (read-only) estava a 14 MB de distância.
--
-- P8 e P9 não bastaram. Eles deram folga de página (`fillfactor 70`) para que a
-- reescrita fosse HOT, mas não atacaram a reescrita em si -- e sobrou reescrita
-- demais para a folga absorver.
--
-- ONDE ESTAVA
-- ===========
--
-- `publicar_atributos` termina com:
--
--   update public.produtos p set segmento = s.segmento
--   from public.motor_produtos_stage s
--   where s.execucao = p_execucao and s.produto_id = p.id;
--
-- Sem cláusula de mudança. Isso reescreve TODOS os 82.666 produtos, toda noite.
-- A linha média de `produtos` tem ~1.079 bytes (medido no P8), então são ~89 MB
-- de tupla nova por execução do motor -- e o Postgres versiona a linha inteira,
-- não a coluna.
--
-- E `segmento` quase nunca muda. Medido em 19/08, a coluna tem DOIS valores:
--
--   feminino_casual_br   73.962 produtos   89,2%
--   nulo                  8.958 produtos   10,8%
--
-- Um produto não troca de segmento de um dia para o outro. A reescrita diária
-- grava, em quase todas as linhas, exatamente o valor que já estava lá.
--
-- Pior: `produtos_segmento` é índice sobre a coluna atualizada. Quando o valor
-- muda de fato, o update não pode ser HOT nem com folga de página, porque HOT
-- exige que nenhuma coluna indexada seja modificada. A folga do P8 só ajuda no
-- caso em que a escrita não precisava acontecer.
--
-- A CORREÇÃO
-- ==========
--
-- `and p.segmento is distinct from s.segmento`. Escreve só o que mudou.
-- `is distinct from` e não `<>` porque 10,8% dos valores são NULL, e `<>` com
-- NULL devolve NULL -- o que faria a cláusula descartar justamente as linhas
-- que precisam sair de nulo, ou entrar nele.
--
-- A GARANTIA DE COMPLETUDE NÃO SE PERDE
-- =====================================
--
-- Antes, `p_total` era conferido contra o número de linhas ATUALIZADAS, o que
-- só funcionava porque todas eram atualizadas sempre. Com a nova cláusula esse
-- número passa a ser "quantas mudaram", que é normalmente zero -- e a conferência
-- viraria um alarme falso todas as noites.
--
-- A pergunta que a guarda faz de verdade é "o stage cobre todos os produtos
-- vivos?". Ela agora é respondida por um count explícito do stage contra
-- `produtos`, ANTES de escrever: mesma garantia, medida na coisa certa.
--
-- O campo `produtos` do retorno continua significando cobertura, para não
-- quebrar quem lê `motor_execucoes.resultado`. `produtos_alterados` é novo e
-- mostra o trabalho real -- deve ficar perto de zero em noite normal, e é o
-- número a observar se o banco voltar a crescer.
--
-- Reverter: tirar a cláusula `is distinct from` e voltar a medir p_total por
-- `get diagnostics` do update.

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

  -- P11: a completude é medida ANTES de escrever, contra o stage, porque o
  -- update abaixo passa a tocar só o que mudou -- e "quantas linhas mudaram"
  -- não responde "o stage cobre todo mundo?".
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
  -- NULL, e `<>` com NULL devolve NULL -- descartaria exatamente as linhas que
  -- entram ou saem de nulo.
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
    'ligacoes', termos_publicados
  );
end;
$function$;

comment on function public.publicar_atributos(uuid, integer) is
  'Troca atômica da taxonomia publicada. P10: limpa o estágio com truncate. P11: só escreve segmento que mudou -- reescrever 82 mil linhas por noite para gravar o mesmo valor levou o banco de 75% a 97% numa coleta.';
