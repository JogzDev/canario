-- Asserções da etapa 1: P21 (medição da cota) e P22 (sem reescrita idêntica).
--
-- Para cada caminho da P22, três perguntas, na ordem:
--
--   primeira escrita     o caminho continua escrevendo o que tem de escrever
--   reexecução idêntica  zero linhas reescritas -- pelos três instrumentos
--   mudança real         só as linhas cujo valor mudou ganham versão nova
--
-- "Linhas cujo valor mudou" é calculado de forma INDEPENDENTE da função, por
-- comparação com uma foto da tabela; a função tem de concordar com a foto, e
-- o contador da transação e o ctid têm de concordar com os dois.

-- VAREJO ---------------------------------------------------------------------

do $$
declare u bigint; i bigint; r int; begin
  u := lab.updates(); i := lab.inserts();
  r := public.computar_serie_varejo();
  assert r = 9, 'a primeira escrita do varejo deveria gravar 9 linhas e gravou ' || r;
  assert lab.inserts() - i = 9 and lab.updates() - u = 0,
    'primeira escrita e insercao, nao atualizacao';
  raise notice 'ok 1  varejo, primeira escrita: 9 linhas inseridas';
end $$;

do $$
declare u bigint; r int; carimbos_mudados int; begin
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_serie_varejo();
  assert r = 0, 'reexecutar o varejo sem mudanca deveria escrever 0 e escreveu ' || r;
  assert lab.updates() - u = 0, 'o executor gravou '
    || (lab.updates() - u) || ' atualizacoes numa reexecucao identica';
  assert lab.movidas() = 0, lab.movidas() || ' linhas ganharam versao fisica nova';
  select count(*) into carimbos_mudados
  from public.series_semanais s join pg_temp.lab_antes a using (id)
  where s.fonte = 'varejo' and s.meta->>'computado_em' is distinct from a.carimbo;
  assert carimbos_mudados = 0,
    'computado_em nao pode mudar quando o valor nao mudou; mudou em '
      || carimbos_mudados;
  raise notice 'ok 2  varejo, reexecucao: 0 escritas, 0 versoes novas, carimbo intacto';
end $$;

do $$
declare u bigint; r int; m bigint; fora int; begin
  -- O produto 20 deixa de ser ofertavel na terceira semana: o sortimento da
  -- semana cai de 20 para 19, e as tres linhas daquela semana mudam de valor
  -- (vestido muda so em n_amostra e no meta, que tambem e dado de negocio).
  update public.snapshots set ofertavel = false
   where produto_id = 20 and data = date '2026-08-24';
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_serie_varejo();
  m := lab.mudadas();
  assert m = 3, 'a mudanca deveria alterar as 3 linhas da semana e alterou ' || m;
  assert r = m and lab.updates() - u = m and lab.movidas() = m,
    'escritas (' || r || '), atualizacoes (' || (lab.updates() - u)
      || ') e versoes novas (' || lab.movidas() || ') deveriam ser ' || m;
  select count(*) into fora
  from public.series_semanais s join pg_temp.lab_antes a using (id)
  where s.fonte = 'varejo' and s.semana <> date '2026-08-24' and s.ctid::text <> a.versao;
  assert fora = 0, fora || ' linhas de outras semanas foram reescritas';
  raise notice 'ok 3  varejo, mudanca real: 3 de 9 linhas, so a semana afetada';
end $$;

-- EDITORIAL ------------------------------------------------------------------

do $$
declare r int; zeros int; begin
  perform lab.semear_editorial();
  r := public.computar_serie_editorial();
  -- 2 zeros materializados + 10 linhas normalizadas (6 de vestido, 4 de
  -- preto contando os dois zeros, que tambem ganham o meta da normalizacao).
  assert r = 12, 'a primeira passada do editorial deveria somar 12 e somou ' || r;
  select count(*) into zeros from public.series_semanais
   where fonte = 'editorial_br' and meta->>'zero_materializado' = 'true';
  assert zeros = 2, 'deveriam existir 2 zeros materializados e existem ' || zeros;
  raise notice 'ok 4  editorial, primeira escrita: 2 zeros + 10 normalizadas';
end $$;

do $$
declare u bigint; i bigint; r int; begin
  perform lab.fotografar();
  u := lab.updates(); i := lab.inserts();
  r := public.computar_serie_editorial();
  assert r = 0, 'reexecutar o editorial deveria escrever 0 e escreveu ' || r;
  assert lab.updates() - u = 0 and lab.inserts() - i = 0,
    'reexecucao identica gravou ' || (lab.updates() - u) || ' atualizacoes e '
      || (lab.inserts() - i) || ' insercoes';
  assert lab.movidas() = 0, lab.movidas() || ' linhas ganharam versao fisica nova';
  raise notice 'ok 5  editorial, reexecucao: 0 escritas, 0 versoes novas';
end $$;

do $$
declare u bigint; r int; m bigint; begin
  -- O denominador de UMA semana muda: so as duas linhas daquela semana
  -- (vestido e preto) mudam de valor.
  update public.denominador_editorial set total_janela_4sem = 999
   where fonte = 'editorial_br' and semana = date '2026-08-24';
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_serie_editorial();
  m := lab.mudadas();
  assert m = 2, 'a mudanca deveria alterar 2 linhas e alterou ' || m;
  assert r = m and lab.updates() - u = m and lab.movidas() = m,
    'escritas (' || r || '), atualizacoes (' || (lab.updates() - u)
      || ') e versoes novas (' || lab.movidas() || ') deveriam ser ' || m;
  raise notice 'ok 6  editorial, mudanca real: 2 linhas, so a semana do denominador';
end $$;

-- Z --------------------------------------------------------------------------

do $$
declare r int; com_z int; begin
  perform lab.semear_busca();
  r := public.computar_z();
  select count(*) into com_z from public.series_semanais where z is not null;
  -- Nulo antes, valor depois: tem de escrever. Oito semanas por termo.
  assert r = 16 and com_z = 16,
    'a primeira passada do z deveria preencher 16 linhas e preencheu ' || r;
  raise notice 'ok 7  z, primeira escrita: 16 linhas de nulo para valor';
end $$;

do $$
declare u bigint; r int; nulos int; begin
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_z();
  assert r = 0, 'reexecutar o z deveria escrever 0 e escreveu ' || r;
  assert lab.updates() - u = 0, 'o executor gravou ' || (lab.updates() - u)
    || ' atualizacoes numa reexecucao identica';
  assert lab.movidas() = 0, lab.movidas() || ' linhas ganharam versao fisica nova';
  -- Nulo antes, nulo depois: e o caso que `=` erraria (nulo = nulo e nulo,
  -- nao verdadeiro) e `is distinct from` acerta.
  select count(*) into nulos from public.series_semanais where z is null;
  assert nulos > 0, 'o teste precisa de linhas com z nulo para valer';
  raise notice 'ok 8  z, reexecucao: 0 escritas; % linhas nulo->nulo intactas', nulos;
end $$;

do $$
declare u bigint; r int; m bigint; outro int; begin
  -- A semana 10 de vestido muda de valor. Mudam o z dela e o das semanas 11 a
  -- 15, cuja janela de 12 semanas a inclui. As semanas 8 e 9 e todo o preto
  -- ficam como estao.
  update public.series_semanais set valor_bruto = valor_bruto + 40
   where fonte = 'busca' and termo_id = 'vestido'
     and semana = date '2026-05-11' + 7 * 10;
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_z();
  m := lab.mudadas();
  assert m = 6, 'a mudanca deveria alterar o z de 6 linhas e alterou ' || m;
  assert r = m and lab.updates() - u = m and lab.movidas() = m,
    'escritas (' || r || '), atualizacoes (' || (lab.updates() - u)
      || ') e versoes novas (' || lab.movidas() || ') deveriam ser ' || m;
  select count(*) into outro
  from public.series_semanais s join pg_temp.lab_antes a using (id)
  where s.termo_id = 'preto' and s.fonte = 'busca' and s.ctid::text <> a.versao;
  assert outro = 0, outro || ' linhas de outra particao foram reescritas';
  raise notice 'ok 9  z, mudanca real: 6 linhas, so a janela afetada';
end $$;

do $$
declare u bigint; r int; m bigint; para_nulo int; begin
  -- Valor para NULO tambem e mudanca. Apagar a primeira semana de preto tira
  -- a semana 8 do minimo de oito semanas de historia: o z dela deixa de
  -- existir, e as semanas 9 a 12 mudam de media.
  delete from public.series_semanais
   where fonte = 'busca' and termo_id = 'preto' and semana = date '2026-05-11';
  perform lab.fotografar();
  u := lab.updates();
  r := public.computar_z();
  m := lab.mudadas();
  select count(*) into para_nulo
  from public.series_semanais s join pg_temp.lab_antes a using (id)
  where s.z is null and a.z is not null;
  assert para_nulo = 1, 'uma linha deveria ir de valor para nulo e foram ' || para_nulo;
  assert m = 5 and r = m and lab.updates() - u = m and lab.movidas() = m,
    'deveriam ser 5 escritas e foram ' || r || ' (mudadas ' || m || ')';
  raise notice 'ok 10 z, valor para nulo: 1 linha zerada, 5 escritas no total';
end $$;

-- A TABELA TERMINA IGUAL -----------------------------------------------------
--
-- A P22 nao pode mudar resultado, so escrita. Recalcular tudo a partir de
-- zero com as funcoes novas tem de dar exatamente a tabela que a sequencia
-- de passos incrementais deixou.
do $$
declare diferentes int; begin
  create temp table lab_incremental as
  select termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra,
         meta - 'computado_em' as meta
  from public.series_semanais;

  delete from public.series_semanais where fonte in ('varejo');
  update public.series_semanais set z = null;
  perform public.computar_serie_varejo();
  perform public.computar_serie_editorial();
  perform public.computar_z();

  select count(*) into diferentes from (
    (select termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra,
            meta - 'computado_em' from public.series_semanais
     except select * from lab_incremental)
    union all
    (select * from lab_incremental
     except select termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra,
                   meta - 'computado_em' from public.series_semanais)
  ) d;
  assert diferentes = 0,
    'recalcular do zero deveria dar a mesma tabela; ' || diferentes || ' linhas diferem';
  raise notice 'ok 11 recalculo do zero = resultado incremental: o significado nao mudou';
end $$;

-- P21 ------------------------------------------------------------------------

do $$
declare u jsonb; soma bigint; principal bigint; begin
  alter function public.uso_do_banco() owner to dono_como_em_producao;
  execute 'set local role service_role';
  u := public.uso_do_banco();
  execute 'reset role';

  select sum(pg_database_size(oid)) into soma from pg_database;
  principal := pg_database_size(current_database());
  assert (u->>'bytes_da_cota')::bigint = soma,
    'a cota deveria ser a soma de todos os bancos';
  assert (u->>'banco_principal_bytes')::bigint = principal,
    'o banco principal deveria ser o atual';
  assert (u->>'overhead_interno_bytes')::bigint = soma - principal
     and (u->>'overhead_interno_bytes')::bigint > 0,
    'o overhead deveria ser o resto, e positivo';
  assert (u->>'bytes')::bigint = soma,
    'a chave antiga passa a carregar o total: verificador antigo fica mais conservador';
  assert u->'por_banco' ? 'template0' and u->'por_banco' ? 'template1',
    'os bancos-modelo precisam aparecer pelo nome';
  raise notice 'ok 12 uso_do_banco: cota % = principal % + overhead % (dono nao superusuario)',
    soma, principal, soma - principal;
end $$;

do $$
begin
  begin
    execute 'set local role anon';
    perform public.uso_do_banco();
    execute 'reset role';
    assert false, 'anon nao pode ler o tamanho do banco';
  exception when insufficient_privilege then
    execute 'reset role';
  end;
  raise notice 'ok 13 uso_do_banco: service_role le, anon recebe 42501';
end $$;

-- P24 ------------------------------------------------------------------------
--
-- As datas do cru do laboratorio sao fixas (agosto de 2026), entao ficam
-- sempre mais velhas que o corte de 21 dias: todo o cru e "podavel". E o caso
-- de producao em 18/09, onde 16 dos 22 dias ja passaram do corte.

do $$
declare r int; velhas_antes int; velhas_depois int; begin
  select count(*) into velhas_antes from public.snapshots
   where data < current_date - 21;
  assert velhas_antes > 0, 'o teste precisa de cru mais velho que o corte';
  r := public.podar_snapshots(21);
  select count(*) into velhas_depois from public.snapshots
   where data < current_date - 21;
  assert r = 0 and velhas_depois = velhas_antes,
    'sem sortimento_diario a poda deveria apagar 0 e apagou ' || r;
  raise notice 'ok 14 poda: sem o denominador da A58, 0 de % linhas velhas apagadas',
    velhas_antes;
end $$;

do $$
declare r int; velhas_antes int; velhas_depois int; begin
  select count(*) into velhas_antes from public.snapshots
   where data < current_date - 21;
  -- A A58 cria a tabela. A partir dai a poda e a da A42, sem mudanca.
  create table public.sortimento_diario (data date);
  r := public.podar_snapshots(21);
  select count(*) into velhas_depois from public.snapshots
   where data < current_date - 21;
  assert r = velhas_antes and velhas_depois = 0,
    'com a tabela da A58 a poda deveria apagar as ' || velhas_antes
      || ' linhas velhas e apagou ' || r;
  drop table public.sortimento_diario;
  raise notice 'ok 15 poda: com a tabela da A58, volta a ser a da A42 (% apagadas)', r;
end $$;

do $$
begin
  begin
    perform public.podar_snapshots(20);
    assert false, 'o piso de 21 dias precisa continuar valendo';
  exception when raise_exception then
    null;
  end;
  raise notice 'ok 16 poda: piso de 21 dias intacto';
end $$;

-- P25 ------------------------------------------------------------------------

do $$
declare r int; esperadas int; inseridas bigint; begin
  select count(*) into esperadas from (
    select distinct termo_id, segmento, semana
    from public.series_semanais
    where z is not null and fonte in ('busca', 'editorial_br')
  ) x;
  inseridas := lab.inserts_indices();
  r := public.computar_indice();
  assert esperadas > 0 and r = esperadas,
    'a primeira escrita deveria inserir ' || esperadas || ' indices e inseriu ' || r;
  assert lab.inserts_indices() - inseridas = esperadas,
    'o executor nao inseriu os ' || esperadas || ' indices esperados';
  raise notice 'ok 17 indice, primeira escrita: % linhas inseridas', esperadas;
end $$;

do $$
declare r int; u bigint; carimbos_mudados int; begin
  perform lab.fotografar_indices();
  u := lab.updates_indices();
  r := public.computar_indice();
  assert r = 0, 'reexecutar o indice sem mudanca deveria escrever 0 e escreveu ' || r;
  assert lab.updates_indices() - u = 0,
    'o executor gravou ' || (lab.updates_indices() - u) || ' indices identicos';
  assert lab.indices_movidos() = 0,
    lab.indices_movidos() || ' indices ganharam versao fisica nova';
  select count(*) into carimbos_mudados
  from public.indices_semanais i join pg_temp.lab_indices_antes a using (id)
  where i.computado_em is distinct from a.carimbo_coluna
     or i.meta->>'computado_em' is distinct from a.carimbo_meta;
  assert carimbos_mudados = 0,
    'carimbos nao podem mudar sem resultado novo; mudaram em ' || carimbos_mudados;
  raise notice 'ok 18 indice, reexecucao: 0 escritas, 0 versoes novas, carimbos intactos';
end $$;

do $$
declare r int; u bigint; m bigint; t text; s text; d date;
        indice_antes numeric; indice_depois numeric; begin
  select termo_id, segmento, semana into t, s, d
  from public.series_semanais
  where fonte = 'busca' and z is not null
  order by semana desc, termo_id limit 1;
  select indice into indice_antes from public.indices_semanais
   where termo_id = t and segmento = s and semana = d;
  update public.series_semanais set z = z + 0.5
   where termo_id = t and segmento = s and semana = d and fonte = 'busca';
  perform lab.fotografar_indices();
  u := lab.updates_indices();
  r := public.computar_indice();
  m := lab.indices_mudados();
  select indice into indice_depois from public.indices_semanais
   where termo_id = t and segmento = s and semana = d;
  assert r = 1 and m = 1 and lab.updates_indices() - u = 1
     and lab.indices_movidos() = 1,
    'mudar o z da ultima semana deveria reescrever exatamente 1 indice';
  assert indice_depois is distinct from indice_antes,
    'o indice da celula alterada deveria mudar';
  raise notice 'ok 19 indice, mudanca real: apenas a ultima semana afetada';
end $$;

do $$
declare r int; u bigint; m bigint; t text; s text; d date;
        indice_antes numeric; indice_depois numeric; begin
  select termo_id, segmento, semana, indice into t, s, d, indice_antes
  from public.indices_semanais order by semana desc, termo_id limit 1;
  insert into public.series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  values (t, s, 'editorial_intl', d, 1, 0.25, 1,
          jsonb_build_object('fonte', 'contexto_do_teste'));
  perform lab.fotografar_indices();
  u := lab.updates_indices();
  r := public.computar_indice();
  m := lab.indices_mudados();
  select indice into indice_depois from public.indices_semanais
   where termo_id = t and segmento = s and semana = d;
  assert r = 1 and m = 1 and lab.updates_indices() - u = 1
     and lab.indices_movidos() = 1,
    'mudar apenas o contexto deveria atualizar exatamente 1 meta';
  assert indice_depois is not distinct from indice_antes,
    'uma perna de contexto nao pode mover o numero do indice';
  raise notice 'ok 20 indice, contexto: meta muda em 1 linha, numero fica intacto';
end $$;

do $$
declare r int; inseridas bigint; t text; s text; d date; begin
  select termo_id, segmento, max(semana) + 7 into t, s, d
  from public.series_semanais where fonte = 'busca'
  group by termo_id, segmento order by termo_id limit 1;
  insert into public.series_semanais
    (termo_id, segmento, fonte, semana, valor_bruto, z, n_amostra, meta)
  values (t, s, 'busca', d, 1, null, null,
          jsonb_build_object('fonte', 'nulo_do_teste'));
  update public.series_semanais set z = 2
   where termo_id = t and segmento = s and semana = d and fonte = 'busca';
  inseridas := lab.inserts_indices();
  r := public.computar_indice();
  assert r = 1 and lab.inserts_indices() - inseridas = 1,
    'nulo para valor deveria inserir exatamente 1 indice';
  assert exists (select 1 from public.indices_semanais
                  where termo_id = t and segmento = s and semana = d),
    'o indice novo nao foi materializado';
  raise notice 'ok 21 indice, nulo para valor: 1 linha inserida';
end $$;

do $$
declare r int; removidas bigint; atualizadas bigint; t text; s text; d date; begin
  select termo_id, segmento, max(semana) into t, s, d
  from public.series_semanais where meta->>'fonte' = 'nulo_do_teste'
  group by termo_id, segmento;
  update public.series_semanais set z = null
   where termo_id = t and segmento = s and semana = d and fonte = 'busca';
  removidas := lab.deletes_indices();
  atualizadas := lab.updates_indices();
  r := public.computar_indice();
  assert r = 0, 'o contrato legado nao conta deletes no retorno; devolveu ' || r;
  assert lab.deletes_indices() - removidas = 1
     and lab.updates_indices() - atualizadas = 0,
    'valor para nulo deveria apagar 1 indice e atualizar 0';
  assert not exists (select 1 from public.indices_semanais
                      where termo_id = t and segmento = s and semana = d),
    'a leitura sem nenhuma base continuou materializada';
  raise notice 'ok 22 indice, valor para nulo: 1 leitura sem base removida';
end $$;

do $$
declare diferentes int; begin
  create temp table lab_indices_incremental as
  select termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas,
         meta - 'computado_em' as meta
  from public.indices_semanais;

  truncate public.indices_semanais restart identity;
  perform public.computar_indice();

  select count(*) into diferentes from (
    (select termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas,
            meta - 'computado_em' from public.indices_semanais
     except select * from lab_indices_incremental)
    union all
    (select * from lab_indices_incremental
     except select termo_id, segmento, semana, indice, estado, pernas_ativas, n_pernas,
                   meta - 'computado_em' from public.indices_semanais)
  ) d;
  assert diferentes = 0,
    'recalcular indices do zero deveria dar a mesma tabela; '
      || diferentes || ' linhas diferem';
  raise notice 'ok 23 indice, recalculo do zero = incremental: significado preservado';
end $$;
