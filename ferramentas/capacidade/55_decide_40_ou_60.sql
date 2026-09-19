-- PASSO 55 · SO LEITURA. Decide entre 40 e 60 depois do passo 50.
--
-- `VACUUM FULL public.artigos` reescreve tabela e indices, inclusive
-- `artigos_url_key`. Os caminhos sao mutuamente exclusivos:
--
--   cota <= 400 MB               -> nenhum
--   cota - ganho_40 <= 400 MB    -> somente 40
--   cota - ganho_40 > 400 MB     -> somente 60

do $$
declare
  teto bigint := coalesce(nullif(current_setting('datadrobe.teto_bytes', true), '')::bigint,
                          400000000);
  cota bigint := (select sum(pg_database_size(oid)) from pg_database);
  url_atual bigint := pg_relation_size('public.artigos_url_key');
  url_recem bigint := (select round(sum(((8 + pg_column_size(url) + 7) / 8) * 8 + 4)
                                    / 0.90 * 1.01)
                         from public.artigos);
  ganho_40 bigint := greatest(url_atual - url_recem, 0);
  vivo bigint := (select sum(pg_column_size(t.*) + 4) from public.artigos t);
  pkey_recem bigint := (select round(count(*) * 20 / 0.90 * 1.01) from public.artigos);
  ganho_60 bigint := greatest(pg_relation_size('public.artigos', 'main')
                              - round(vivo * 1.02), 0)
                     + greatest(pg_relation_size('public.artigos_pkey') - pkey_recem, 0)
                     + ganho_40;
  decisao text;
begin
  if cota <= teto then
    decisao := 'NENHUM: a cota ja esta dentro do teto';
  elsif url_atual <= url_recem * 1.10 then
    decisao := 'PARAR: artigos_url_key ja foi reconstruido; o 40 ou o 60 ja rodou';
  elsif cota - ganho_40 <= teto then
    decisao := 'PASSO 40: o reindex sozinho basta';
  else
    decisao := 'PASSO 60: o reindex sozinho nao basta; vacuum full reescreve heap e indices juntos';
  end if;
  raise notice 'DECISAO 40/60: % | cota % · teto % · ganho estimado do 40 % · do 60 %',
    decisao, cota, teto, ganho_40, ganho_60;
end $$;
