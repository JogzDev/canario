-- PASSO 87 · SO LEITURA. Pós-condições do backend A57/A58.

do $$
declare
  e record;
  oid regprocedure;
  obtido text;
begin
  for e in select * from (values
    ('public.similares_da_peca_v2(text[],integer,numeric)', '5427b1ffd6419ff88b7b792dbd264ca7'),
    ('public.similares_da_peca_amplo_v2(text[],integer,numeric)', '4dcd52b9dea867a84016c1545f797bf6'),
    ('public.eventos_recentes(text,integer)', 'd88b25e2f60bc70fef1abc38d66a1fa4'),
    ('public.sortimento_observado(date)', '400b49eb431e22bcbe02faead78eccac'),
    ('public.computar_sortimento_diario(date)', '9cfc4a030580d9fdfd99fca756fd13a6'),
    ('public.resumo_de_eventos(text,integer,integer,date)', 'aaa29647183793c64ceb498c206634ea'),
    ('public.buscar_referencia_editorial(text,integer)', 'd50ef18c181d56f55e7ccc8dba9df6ad'),
    ('public.computar_motor()', 'bfd94356e44bf0e4319ff8f792a6afc0'),
    ('public.similares_da_peca(text[],integer,numeric)', '56b0e7cd6372bb54caedbf2260a2be19'),
    ('public.similares_da_peca_amplo(text[],integer,numeric)', '0a935805b4a2437bb6cabd0fa46b186b')
  ) as x(assinatura, hash)
  loop
    oid := to_regprocedure(e.assinatura);
    if oid is null then raise exception 'ABORTAR: funcao ausente: %', e.assinatura; end if;
    select md5(regexp_replace(pg_get_functiondef(oid), '\s+', ' ', 'g')) into obtido;
    if obtido <> e.hash then
      raise exception 'ABORTAR: % tem hash %, esperado %', e.assinatura, obtido, e.hash;
    end if;
  end loop;
  raise notice 'A57/A58 e consumidores antigos conferem por assinatura e hash';
end $$;

do $$
declare
  dias_snapshot integer;
  dias_sortimento integer;
  versoes integer;
begin
  if to_regclass('public.sortimento_diario') is null
     or to_regclass('public.observacoes_publicadas_do_painel') is null then
    raise exception 'ABORTAR: tabelas internas da A57/A58 ausentes';
  end if;
  select count(distinct data) into dias_snapshot from public.snapshots;
  select count(distinct data) into dias_sortimento from public.sortimento_diario;
  if dias_sortimento < dias_snapshot then
    raise exception 'ABORTAR: % dias de snapshot e so % denominadores', dias_snapshot, dias_sortimento;
  end if;
  select count(*) into versoes from supabase_migrations.schema_migrations
   where version in ('20260917210000','20260917211000');
  if versoes <> 2 then raise exception 'ABORTAR: A57/A58 nao fecham no ledger'; end if;

  if not has_function_privilege('anon', 'public.resumo_de_eventos(text,integer,integer,date)', 'execute')
     or not has_function_privilege('anon', 'public.buscar_referencia_editorial(text,integer)', 'execute')
     or not has_function_privilege('anon', 'public.similares_da_peca_amplo_v2(text[],integer,numeric)', 'execute')
     or not has_function_privilege('anon', 'public.similares_da_peca_amplo(text[],integer,numeric)', 'execute') then
    raise exception 'ABORTAR: contrato EXECUTE do app incompleto';
  end if;
  if has_function_privilege('anon', 'public.computar_sortimento_diario(date)', 'execute')
     or has_table_privilege('anon', 'public.observacoes_publicadas_do_painel', 'select') then
    raise exception 'ABORTAR: anon ganhou acesso interno indevido';
  end if;
  raise notice 'A57/A58: % dias de denominador, ledger e privilegios conferidos', dias_sortimento;
end $$;
