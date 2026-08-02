-- PUBLICAÇÃO ATÔMICA DO MOTOR
--
-- Antes desta migration, o matcher apagava `produto_termos` ao começar e
-- reconstruía em centenas de chamadas REST. Uma falha no meio deixava a
-- taxonomia parcialmente vazia. Depois, sete RPCs publicavam resultados uma
-- a uma; se a última desse timeout, as seis primeiras já estavam visíveis.
--
-- A preparação abaixo nunca é legível pelo app. Uma transação curta publica
-- os atributos completos, e uma única RPC transacional publica todo o motor.

-- O lote completo medido hoje leva cerca de três minutos. A chamada única
-- precisa de margem sobre os 300s antigos para não reintroduzir o timeout que
-- esta migration elimina por desenho.
alter role service_role set statement_timeout = '900s';

create table public.motor_produtos_stage (
  execucao   uuid not null,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  segmento   text,
  criado_em  timestamptz not null default now(),
  primary key (execucao, produto_id)
);

create table public.motor_termos_stage (
  execucao   uuid not null,
  produto_id bigint not null references public.produtos(id) on delete cascade,
  termo_id   text not null references public.termos(id),
  criado_em  timestamptz not null default now(),
  primary key (execucao, produto_id, termo_id)
);

create index motor_produtos_stage_criado
  on public.motor_produtos_stage (criado_em);
create index motor_termos_stage_criado
  on public.motor_termos_stage (criado_em);

alter table public.motor_produtos_stage enable row level security;
alter table public.motor_termos_stage enable row level security;

revoke all on table public.motor_produtos_stage
  from public, anon, authenticated;
revoke all on table public.motor_termos_stage
  from public, anon, authenticated;
grant select, insert, update, delete on table public.motor_produtos_stage
  to service_role;
grant select, insert, update, delete on table public.motor_termos_stage
  to service_role;

create or replace function public.publicar_atributos(
  p_execucao uuid,
  p_total integer
)
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

  delete from public.motor_termos_stage where execucao = p_execucao;
  delete from public.motor_produtos_stage where execucao = p_execucao;

  -- Uma execução interrompida antes de publicar só deixa preparação
  -- invisível. Uma execução futura remove esse resíduo depois de dois dias.
  delete from public.motor_termos_stage
  where criado_em < now() - interval '2 days';
  delete from public.motor_produtos_stage
  where criado_em < now() - interval '2 days';

  return jsonb_build_object(
    'produtos', produtos_publicados,
    'ligacoes', termos_publicados
  );
end;
$function$;

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
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:publicacao-do-motor', 0));

  -- Atribuições separadas preservam a ordem; jsonb_build_object não garante
  -- a ordem de avaliação dos argumentos.
  r_eventos := public.computar_eventos();
  r_varejo := public.computar_serie_varejo();
  r_editorial := public.computar_serie_editorial();
  r_z := public.computar_z();
  r_indice := public.computar_indice();
  r_curva := public.computar_curva_tamanhos();
  r_raridade := public.computar_raridade();

  return jsonb_build_object(
    'computar_eventos', r_eventos,
    'computar_serie_varejo', r_varejo,
    'computar_serie_editorial', r_editorial,
    'computar_z', r_z,
    'computar_indice', r_indice,
    'computar_curva_tamanhos', r_curva,
    'computar_raridade', r_raridade
  );
end;
$function$;

create or replace function public.publicar_motor(
  p_execucao uuid,
  p_total integer
)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  atributos jsonb;
  calculos jsonb;
begin
  -- Funções chamadas dentro desta RPC compartilham a mesma transação. Se o
  -- último cálculo falhar, a troca de atributos também é revertida e o stage
  -- continua disponível para diagnóstico.
  atributos := public.publicar_atributos(p_execucao, p_total);
  calculos := public.computar_motor();
  return jsonb_build_object('atributos', atributos, 'calculos', calculos);
end;
$function$;

revoke execute on function public.publicar_atributos(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.computar_motor()
  from public, anon, authenticated;
revoke execute on function public.publicar_motor(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.publicar_atributos(uuid, integer)
  to service_role;
grant execute on function public.computar_motor()
  to service_role;
grant execute on function public.publicar_motor(uuid, integer)
  to service_role;

comment on function public.publicar_atributos(uuid, integer) is
  'Troca produto_termos de origem titulo e produtos.segmento atomicamente, '
  'somente depois de validar que todos os produtos chegaram ao stage.';
comment on function public.computar_motor() is
  'Executa todas as materializacoes do motor em uma transacao. Qualquer falha '
  'reverte o lote inteiro e preserva a leitura anterior.';
comment on function public.publicar_motor(uuid, integer) is
  'Publica atributos e todas as materializacoes na mesma transacao; uma falha '
  'em qualquer etapa preserva integralmente a leitura anterior.';
