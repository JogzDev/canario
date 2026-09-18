-- PASSO 80 · SO LEITURA. Imediatamente antes de aplicar P21 a P25.
--
-- P21, P22, P24 e P25 substituem seis funcoes que estao em producao; P23 cria
-- a retencao do log. Se qualquer definicao ativa nao for mais a medida em
-- 18/09 -- alguem aplicou outra coisa pelo editor, por exemplo --, a migration
-- substituiria algo que ninguem revisou. Hash diferente e ABORTAR.

do $$
declare
  f record;
  esperado jsonb := jsonb_build_object(
    'computar_serie_varejo', '4a1b76d8d0b9d81086474a563006d6b5',
    'computar_serie_editorial', 'a56488dcf1e732973339e50442882c5e',
    'computar_z', 'a84c63a5c5acd5fa95a25fe7fd0df120',
    'computar_indice', 'ce2ffa99841a237ee1001071b46ee772',
    'uso_do_banco', '7c6355a6bd043f9d01108f01d465bc39',
    'podar_snapshots', 'c9b22fd0cc607449cbbf7b5aef7c77cf');
  encontradas int := 0;
begin
  for f in
    select p.proname,
           md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) as hash
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and esperado ? p.proname
  loop
    encontradas := encontradas + 1;
    if f.hash <> esperado->>f.proname then
      raise exception 'ABORTAR: % mudou desde 18/09 (hash %, esperado %)',
        f.proname, f.hash, esperado->>f.proname;
    end if;
  end loop;
  -- Funcao ausente tambem e divergencia: sem esta conta o laco passaria
  -- vazio e o passo sairia verde sem ter conferido nada.
  if encontradas <> 6 then
    raise exception 'ABORTAR: esperava 6 funcoes e achei %', encontradas;
  end if;

  if exists (select 1 from public.motor_execucoes
              where status in ('queued', 'running')) then
    raise exception 'ABORTAR: publicacao do motor em andamento';
  end if;

  -- A P24 so tem efeito enquanto a A58 nao existe. Se ela ja existir, a
  -- guarda e inerte e o risco da poda muda de natureza -- revisar antes.
  if to_regclass('public.sortimento_diario') is not null then
    raise exception 'REVISAR: sortimento_diario ja existe; a P24 seria inerte';
  end if;
  raise notice 'as seis funcoes sao as medidas em 18/09; motor parado; A58 ausente';
end $$;

-- O cru que a P24 protege, no momento da aplicacao.
select min(data) as mais_antigo, max(data) as mais_novo, count(distinct data) as dias,
       count(*) as linhas,
       count(*) filter (where data < current_date - 21) as linhas_alem_do_corte_de_hoje
from public.snapshots;
