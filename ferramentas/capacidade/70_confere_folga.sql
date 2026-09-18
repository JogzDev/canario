-- PASSO 70 · SO LEITURA. O portao entre a recuperacao e a prevencao.
--
-- Sai com erro -- e o executor com codigo 1 -- se qualquer condicao da
-- etapa 1 nao estiver cumprida. Verde aqui e a autorizacao tecnica para
-- aplicar P21, P22, P23 e P24; a autorizacao de fato continua sendo de voces.

do $$
declare
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
begin
  -- Pelo menos 20% de folga real, medida como a plataforma mede.
  if cota > 400000000 then
    raise exception 'FOLGA INSUFICIENTE: cota % bytes = % do limite; a meta e ate 400.000.000',
      cota, round(100.0 * cota / 500000000, 1) || '%';
  end if;
  -- Escrita liberada. `off` aqui e o que o Supabase mostra quando o projeto
  -- nao esta em somente-leitura; o painel pode demorar ate um dia para
  -- refletir a metrica nova.
  if current_setting('default_transaction_read_only') <> 'off' then
    raise exception 'ESCRITA BLOQUEADA: default_transaction_read_only = %',
      current_setting('default_transaction_read_only');
  end if;
  raise notice 'folga ok: cota % bytes (% do limite), escrita liberada',
    cota, round(100.0 * cota / 500000000, 1) || '%';
end $$;

select (select sum(pg_database_size(oid)) from pg_database)::bigint as cota_bytes,
       pg_database_size(current_database()) as principal_bytes,
       (select coalesce(sum(size), 0) from pg_ls_waldir())::bigint as wal_bytes;
