-- P24: o cru nao e podado enquanto o denominador da A58 nao existir.
--
-- O CONFLITO QUE ESTA MIGRATION RESOLVE
-- =====================================
--
-- A ordem aprovada para a etapa 1 e: recuperar espaco, aplicar a prevencao,
-- publicar o backend A57/A58, retomar a coleta e OBSERVAR o crescimento antes
-- de liberar o app consumidor. Ainda assim, entre a P24 e a A58 -- ou se a
-- A58 falhar e precisar ser revertida -- uma publicacao manual do motor chama
-- `podar_snapshots(21)` (A42), que apaga todo snapshot com
-- `data < current_date - 21`. O corte e de CALENDARIO, nao de dado: com a
-- coleta parada desde 02/09, ele avancou sozinho. Medido em 18/09/2026, em
-- leitura:
--
--   snapshots: 254.736 linhas, 22 dias (12/08 a 02/09)
--   corte de hoje: 28/08
--   a primeira poda apagaria 202.050 linhas -- 16 dos 22 dias
--
-- Esses dias sao a UNICA fonte do denominador que a A58 reconstroi em
-- `sortimento_diario`. Apagados, a taxa por mil de agosto deixa de existir em
-- qualquer lugar, e a A58 nasce sem historico. E cada dia de espera avanca o
-- corte em mais um dia.
--
-- O QUE MUDA
-- ==========
--
-- `podar_snapshots` passa a devolver 0 sem apagar nada enquanto a tabela
-- `public.sortimento_diario` nao existir. Quando a A58 for aplicada, ela cria
-- a tabela, reconstroi o historico a partir destes mesmos snapshots e poe o
-- calculo do dia antes da poda dentro de `computar_motor` -- e a partir dai a
-- guarda fica inerte e a poda volta a funcionar como na A42.
--
-- Piso de 21 dias, assinatura, dono e permissoes: iguais aos da A42.
--
-- O CUSTO, MEDIDO, E DECLARADO
-- ============================
--
-- A coleta permanece parada enquanto esta guarda estiver ativa. Se o backend
-- A58 nao puder ser aplicado na mesma janela, a retomada e cancelada: nunca se
-- troca a fonte historica por crescimento sem poda nem se resolve o impasse
-- apagando snapshot.
--
-- ALTERNATIVAS, E POR QUE NAO ESTAS
-- =================================
--
-- Publicar apenas a parte da A58 que cria `sortimento_diario` separaria uma
-- migration revisada como unidade. A guarda conserva o cru durante a pequena
-- janela entre migrations; a A58 completa a torna inerte antes da retomada.

create or replace function public.podar_snapshots(p_retencao_dias integer default 21)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  removidas integer := 0;
begin
  if p_retencao_dias < 21 then
    raise exception 'retencao de snapshots abaixo do piso seguro de 21 dias';
  end if;

  -- P24: sem o denominador materializado, o cru e a unica fonte dele.
  if to_regclass('public.sortimento_diario') is null then
    return 0;
  end if;

  delete from public.snapshots
  where data < (current_date - p_retencao_dias);
  get diagnostics removidas = row_count;
  return removidas;
end;
$function$;

comment on function public.podar_snapshots(integer) is
  'A42 + P24: conserva 21 dias de dado cru e nao poda nada enquanto sortimento_diario (A58) nao existir; a serie semanal materializada permanece historica.';

revoke execute on function public.podar_snapshots(integer)
  from public, anon, authenticated;
grant execute on function public.podar_snapshots(integer) to service_role;
