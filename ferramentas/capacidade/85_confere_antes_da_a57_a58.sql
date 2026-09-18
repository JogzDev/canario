-- PASSO 85 · SO LEITURA. Estado exato imediatamente antes de A57/A58.

do $$
declare
  e record;
  oid regprocedure;
  obtido text;
begin
  for e in select * from (values
    ('public.eventos_recentes(text,integer)', '07333561282bacfd6dca91fb2d98a886'),
    ('public.computar_motor()', '40b79a54661765b4b95465aefbff0b4d'),
    ('public.similares_da_peca(text[],integer,numeric)', '56b0e7cd6372bb54caedbf2260a2be19'),
    ('public.similares_da_peca_amplo(text[],integer,numeric)', '0a935805b4a2437bb6cabd0fa46b186b'),
    ('public.computar_z()', '679f9c15255a939942e7240f46216f87'),
    ('public.podar_snapshots(integer)', 'ecb5b467106ad7657bea380056a4bbc2'),
    ('public.computar_indice()', 'f5a3bd9e528f333242d1877dd8666176')
  ) as x(assinatura, hash)
  loop
    oid := to_regprocedure(e.assinatura);
    if oid is null then raise exception 'ABORTAR: funcao ausente: %', e.assinatura; end if;
    select md5(regexp_replace(pg_get_functiondef(oid), '\s+', ' ', 'g')) into obtido;
    if obtido <> e.hash then
      raise exception 'ABORTAR: % tem hash %, esperado %', e.assinatura, obtido, e.hash;
    end if;
  end loop;
  if exists (select 1 from public.motor_execucoes where status in ('queued','running')) then
    raise exception 'ABORTAR: publicacao do motor em andamento';
  end if;
  if to_regclass('public.sortimento_diario') is not null
     or to_regclass('public.observacoes_publicadas_do_painel') is not null then
    raise exception 'ABORTAR: A57/A58 ja aplicada ou estado parcial inesperado';
  end if;
  raise notice 'estado anterior a A57/A58 confere';
end $$;

select min(data) as mais_antigo, max(data) as mais_novo,
       count(distinct data) as dias, count(*) as linhas
from public.snapshots;
