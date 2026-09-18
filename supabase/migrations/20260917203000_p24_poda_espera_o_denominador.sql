-- P24: o cru nao e podado enquanto o denominador da A58 nao existir.
--
-- O CONFLITO QUE ESTA MIGRATION RESOLVE
-- =====================================
--
-- A ordem aprovada para a etapa 1 e: recuperar espaco, aplicar a prevencao,
-- retomar a coleta e OBSERVAR o crescimento -- e so depois publicar A57/A58.
-- Mas a primeira publicacao do motor depois da retomada chama
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
-- Enquanto a guarda estiver ativa com a coleta rodando, `snapshots` cresce sem
-- poda: 11.579 linhas por dia em media (254.736 / 22), ~148 bytes por linha
-- viva no heap e ~95 bytes nos dois indices -- cerca de 2,7 MB por dia, 19 MB
-- por semana. Isso sai da folga que a etapa 1 recupera. O roteiro trata como
-- criterio de reavaliacao: se a A58 nao for aplicada dentro da janela de
-- observacao, a decisao volta para a mesa -- nunca e resolvida apagando
-- snapshot.
--
-- ALTERNATIVAS, E POR QUE NAO ESTAS
-- =================================
--
-- Manter a coleta parada ate a A58 nao custa espaco, mas inverte a ordem
-- aprovada: nao haveria crescimento para observar antes de publicar.
-- Aplicar so a parte da A58 que cria `sortimento_diario` antes da retomada
-- resolve sem custo, mas separa uma migration que foi revisada inteira. As
-- duas sao decisao de produto; esta guarda e a unica que nao muda nada alem
-- da poda.

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
