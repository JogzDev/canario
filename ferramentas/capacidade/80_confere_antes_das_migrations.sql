-- PASSO 80 · SO LEITURA. Imediatamente antes de aplicar P21 a P25.
--
-- P21, P22, P24 e P25 substituem seis funcoes que estao em producao; P23 cria
-- a retencao do log. Se qualquer definicao ativa nao for mais a medida em
-- 18/09 -- alguem aplicou outra coisa pelo editor, por exemplo --, a migration
-- substituiria algo que ninguem revisou. Hash diferente e ABORTAR.

do $$
declare
  e record;
  oid regprocedure;
  obtido text;
begin
  for e in select * from (values
    ('public.computar_serie_varejo()', '4a1b76d8d0b9d81086474a563006d6b5'),
    ('public.computar_serie_editorial()', 'a56488dcf1e732973339e50442882c5e'),
    ('public.computar_z()', 'a84c63a5c5acd5fa95a25fe7fd0df120'),
    ('public.computar_indice()', 'ce2ffa99841a237ee1001071b46ee772'),
    ('public.uso_do_banco()', '7c6355a6bd043f9d01108f01d465bc39'),
    ('public.podar_snapshots(integer)', 'c9b22fd0cc607449cbbf7b5aef7c77cf')
  ) as x(assinatura, hash)
  loop
    oid := to_regprocedure(e.assinatura);
    if oid is null then
      raise exception 'ABORTAR: funcao ausente: %', e.assinatura;
    end if;
    select md5(regexp_replace(pg_get_functiondef(oid), '\s+', ' ', 'g')) into obtido;
    if obtido <> e.hash then
      raise exception 'ABORTAR: % mudou desde 18/09 (hash %, esperado %)',
        e.assinatura, obtido, e.hash;
    end if;
  end loop;

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
