-- Carregar como bootstrap depois de schema_admissao.sql. O harness fornece
-- lab.fixture, prepara os anchors, exercita concorrência em conexões writer
-- e então chama executar_testes_admissao_v1(fixture).

create function lab_radar.preparar_fixture_de_teste_v1(p_fixture jsonb)
returns void language plpgsql
set search_path = pg_catalog, lab_radar, public, pg_temp as $$
declare
  m jsonb := p_fixture -> 'manifest';
  d jsonb := p_fixture -> 'concept_dossier';
  r jsonb := p_fixture -> 'concept_review';
begin
  if jsonb_typeof(m) is distinct from 'object' or m -> 'synthetic' <> 'true'::jsonb
     or d ->> 'family' is distinct from 'fiber' or r ->> 'status' is distinct from 'approved'
     or r -> 'synthetic' is distinct from 'true'::jsonb then
    raise exception 'lab_test_fixture_invalid';
  end if;
  perform lab_radar.registrar_destino_v1((m ->> 'destination_id')::uuid);
  if not exists(select 1 from public.conceitos_de_moda where id=d ->> 'id') then
    insert into public.conceitos_de_moda(id,familia,rotulo_pt,definicao,aliases_pt,
      exemplos_positivos,exemplos_negativos,protocolo_promocao_versao,
      volume_observado,volume_minimo_exigido)
    values (d ->> 'id',d ->> 'family',d ->> 'label_pt',d ->> 'definition',
      array(select jsonb_array_elements_text(d -> 'aliases')),
      array(select jsonb_array_elements_text(d -> 'positive_examples')),
      array(select jsonb_array_elements_text(d -> 'negative_examples')),
      d ->> 'promotion_protocol_version',jsonb_array_length(d -> 'supporting_subject_ids'),
      (d ->> 'minimum_evidence_count')::integer);
    perform public.revisar_conceito_de_moda(d ->> 'id','approved','SIMULADO_CONCEITO');
  end if;
  perform lab_radar.registrar_manifesto_v1(m);
end;
$$;
revoke all on function lab_radar.preparar_fixture_de_teste_v1(jsonb) from public;

create function lab_radar._test_exigir_v1(p_ok boolean,p_name text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'lab_test_failed:%',p_name; end if;
end;
$$;
revoke all on function lab_radar._test_exigir_v1(boolean,text) from public;

-- Executa o ataque com privilégios da sessão writer, nunca como dono da RPC.
create function lab_radar._test_writer_error_v1(p_sql text,p_expected text)
returns void language plpgsql
set search_path = pg_catalog, lab_radar, public, pg_temp as $$
declare v_error text;
begin
  begin
    execute 'set local role datadrobe_lab_writer';
    execute p_sql;
  exception when others then
    v_error := sqlerrm;
  end;
  execute 'reset role';
  if v_error is null or position(p_expected in v_error) = 0 then
    -- O SQL entra na mensagem porque a versao anterior dizia so
    -- "expected:permission denied;actual:success", e essa frase serve para
    -- SETE casos diferentes deste arquivo. Uma falha que nao diz qual ataque
    -- passou obriga a bissecar o teste na mao para descobrir o que o banco
    -- deixou de barrar -- que e justamente a informacao mais urgente.
    raise exception 'lab_test_expected_error:%;actual:%;sql:%',
      p_expected,coalesce(v_error,'success'),left(p_sql,160);
  end if;
end;
$$;
revoke all on function lab_radar._test_writer_error_v1(text,text) from public;

create function lab_radar._test_fail_link_v1()
returns trigger language plpgsql as $$
begin
  raise exception 'lab_injected_link_failure';
end;
$$;
revoke all on function lab_radar._test_fail_link_v1() from public;

create function lab_radar.executar_testes_admissao_v1(p_fixture jsonb)
returns jsonb language plpgsql
set search_path = pg_catalog, lab_radar, public, pg_temp as $$
declare
  m jsonb := p_fixture -> 'manifest';
  x jsonb;
  first_result jsonb;
  second_result jsonb;
  n_runs bigint;
  n_items bigint;
  n_evidence bigint;
  n_readings bigint;
  n_receipts bigint;
  v_function text;
  v_table text;
  v_error text;
  v_bad_manifest_id text := repeat('a',64);
begin
  perform lab_radar.preparar_fixture_de_teste_v1(p_fixture);
  perform lab_radar._test_exigir_v1(
    not (select rolsuper or rolbypassrls or rolcreatedb or rolcreaterole
         from pg_roles where rolname='datadrobe_lab_writer'),'writer_role_restricted');
  perform lab_radar._test_exigir_v1(
    not pg_has_role('datadrobe_lab_writer','service_role','MEMBER')
    and not pg_has_role('datadrobe_lab_writer','datadrobe_lab_owner','MEMBER'),
    'writer_no_privileged_membership');
  foreach v_table in array array['fontes_de_sinal','conceitos_de_moda','itens_de_fonte',
      'evidencias_de_sinal','leituras_de_mercado','execucoes_de_pesquisa','leitura_evidencias'] loop
    perform lab_radar._test_exigir_v1(
      not has_table_privilege('datadrobe_lab_writer','public.' || v_table,'SELECT,INSERT,UPDATE,DELETE'),
      'writer_no_direct_' || v_table);
  end loop;
  foreach v_function in array array[
    'public.revisar_conceito_de_moda(text,text,text,text)',
    'public.revisar_evidencia_de_sinal(bigint,text,text,text)',
    'public.publicar_leitura_de_mercado(bigint,text)',
    'public.podar_itens_de_fonte_13(integer)',
    'lab_radar.registrar_destino_v1(uuid)',
    'lab_radar.registrar_manifesto_v1(jsonb)'] loop
    perform lab_radar._test_exigir_v1(
      not has_function_privilege('datadrobe_lab_writer',v_function,'EXECUTE'),
      'writer_no_execute_' || v_function);
  end loop;

  execute 'set local role datadrobe_lab_writer';
  first_result := lab_radar.admitir_etiqueta_v1(m);
  second_result := lab_radar.admitir_etiqueta_v1(m);
  execute 'reset role';
  perform lab_radar._test_exigir_v1(second_result ->> 'outcome'='reused'
    and first_result - 'outcome' = second_result - 'outcome','idempotent_same_ids');
  perform lab_radar._test_exigir_v1((select count(*)=1 from lab_radar.recibos_admissao),
    'one_receipt');
  perform lab_radar._test_exigir_v1((select count(*)=3 from public.execucoes_de_pesquisa)
    and (select bool_and(status='success' and executor='local_deterministic'
      and tokens_entrada=0 and tokens_saida=0 and chamadas_web=0 and custo_usd=0)
      from public.execucoes_de_pesquisa),'three_successful_free_executions');
  perform lab_radar._test_exigir_v1((select count(*)=1 from public.itens_de_fonte)
    and (select count(*)=1 from public.evidencias_de_sinal)
    and (select count(*)=1 from public.leituras_de_mercado)
    and (select count(*)=1 from public.leitura_evidencias),'cardinality_one');
  perform lab_radar._test_exigir_v1((select bool_and(status='draft' and tipo='composition'
    and direcao='present' and confianca_extracao is null and revisada_por is null)
    from public.evidencias_de_sinal),'evidence_draft_without_invented_confidence');
  perform lab_radar._test_exigir_v1((select bool_and(status='draft' and estagio='insufficient'
    and cobertura='{}'::jsonb and cardinality(lacunas)>0 and publicada_por is null)
    from public.leituras_de_mercado),'reading_insufficient_private');

  perform lab_radar._test_writer_error_v1(format(
    'select public.publicar_leitura_de_mercado(%s,''attack'')',first_result ->> 'reading_id'),
    'permission denied');
  perform lab_radar._test_writer_error_v1(format(
    'select public.revisar_evidencia_de_sinal(%s,''approved'',''attack'')',first_result ->> 'evidence_id'),
    'permission denied');
  -- OS DOIS `set role` SAIRAM DAQUI EM 05/09, E O MOTIVO IMPORTA.
  --
  -- Eles afirmavam que o escritor nao consegue escalar privilegio virando
  -- `service_role` ou `datadrobe_lab_owner`. A afirmacao esta certa; o teste
  -- estava no lugar errado, e por isso NAO PODIA falhar.
  --
  -- O PostgreSQL decide `SET ROLE` pelo **session_user**, e nao pelo papel
  -- corrente. Aqui dentro a sessao e a do administrador (o dono do cluster,
  -- superusuario), e `set local role datadrobe_lab_writer` troca so o papel
  -- corrente. Resultado medido na primeira execucao: `set role service_role`
  -- devolveu SUCESSO, o teste acusou o proprio arranjo e nao o banco.
  --
  -- E o defeito interessante e o inverso do que aconteceu: bastava alguem ter
  -- escrito a expectativa como "sucesso" para a suite ficar verde afirmando
  -- uma protecao que ela nunca exercitou. O caso vive agora em
  -- `teste_concorrencia.mjs`, onde existe conexao autenticada como escritor e
  -- o `session_user` e o certo. Ver a checagem `escalada_por_set_role_negada`.
  perform lab_radar._test_writer_error_v1(
    'insert into public.termos(id,status) values (''lab_attack'',''aprovado'')','permission denied');
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.registrar_manifesto_v1(%L::jsonb)',m),'permission denied');
  perform lab_radar._test_writer_error_v1(
    'update lab_radar.destino set database_name=''production''','permission denied');

  x := m || jsonb_build_object('summary','FICTÍCIO — alterado depois do anchor');
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_manifest_not_anchored');
  x := m || jsonb_build_object('destination_id','00000000-0000-0000-0000-000000000000');
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_destination_mismatch');
  x := m || jsonb_build_object('synthetic',false);
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_synthetic_manifest_required');
  x := m || jsonb_build_object('publication_status','published');
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_manifest_fields_invalid');

  -- Âncoras alteradas a seguir são ataques SINTÉTICOS preparados pelo admin.
  -- A credencial writer não consegue registrar nenhuma delas.
  x := m || jsonb_build_object('manifest_id',repeat('b',64),'logical_key',repeat('c',64));
  perform lab_radar.registrar_manifesto_v1(x);
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_logical_identity_conflict');
  x := m || jsonb_build_object('manifest_id',repeat('d',64),'summary','FICTÍCIO — conteúdo conflitante');
  perform lab_radar.registrar_manifesto_v1(x);
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_logical_identity_conflict');
  x := m || jsonb_build_object('manifest_id',repeat('e',64),'source_contract_sha256',repeat('0',64));
  perform lab_radar.registrar_manifesto_v1(x);
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_source_contract_invalid');
  x := m || jsonb_build_object('manifest_id',repeat('f',64),'observed_at',
    (clock_timestamp()+interval '1 day')::text);
  perform lab_radar.registrar_manifesto_v1(x);
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_observation_time_invalid');

  -- Falha depois de item, evidência e leitura inseridos: tudo deve voltar.
  select count(*) into n_runs from public.execucoes_de_pesquisa;
  select count(*) into n_items from public.itens_de_fonte;
  select count(*) into n_evidence from public.evidencias_de_sinal;
  select count(*) into n_readings from public.leituras_de_mercado;
  select count(*) into n_receipts from lab_radar.recibos_admissao;
  x := m || jsonb_build_object('manifest_id',v_bad_manifest_id,
    'logical_key',repeat('1',64),'fact_id',repeat('2',64),
    'source_item_external_id','lab:failure-injection:isolated-item');
  perform lab_radar.registrar_manifesto_v1(x);
  execute 'create trigger lab_test_fail_link before insert on public.leitura_evidencias '
    || 'for each row execute function lab_radar._test_fail_link_v1()';
  perform lab_radar._test_writer_error_v1(format(
    'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',x),'lab_injected_link_failure');
  execute 'drop trigger lab_test_fail_link on public.leitura_evidencias';
  perform lab_radar._test_exigir_v1(
    (select count(*) from public.execucoes_de_pesquisa)=n_runs
    and (select count(*) from public.itens_de_fonte)=n_items
    and (select count(*) from public.evidencias_de_sinal)=n_evidence
    and (select count(*) from public.leituras_de_mercado)=n_readings
    and (select count(*) from lab_radar.recibos_admissao)=n_receipts,
    'late_failure_rolls_back_all_business_rows');

  -- Mesmo a consulta pública autorizada tem resultado vazio para ambos papéis.
  execute 'set local role anon';
  select count(*) into n_items from public.listar_leituras_de_mercado_publicadas();
  select count(*) into n_evidence from public.evidencias_da_leitura_publicada(
    (first_result ->> 'reading_id')::bigint);
  execute 'reset role';
  perform lab_radar._test_exigir_v1(n_items=0 and n_evidence=0,'anon_sees_no_drafts');
  execute 'set local role authenticated';
  select count(*) into n_items from public.listar_leituras_de_mercado_publicadas();
  select count(*) into n_evidence from public.evidencias_da_leitura_publicada(
    (first_result ->> 'reading_id')::bigint);
  execute 'reset role';
  perform lab_radar._test_exigir_v1(n_items=0 and n_evidence=0,'authenticated_sees_no_drafts');

  -- Drift do conceito é exercitado em subtransação e revertido no fim do caso.
  begin
    update public.conceitos_de_moda set rotulo_pt=rotulo_pt || ' corrigido',versao=versao+1
      where id=m ->> 'concept_id';
    perform lab_radar._test_writer_error_v1(format(
      'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',m),'lab_concept_contract_changed');
    raise exception using errcode='ZX001',message='rollback_concept_test';
  exception when sqlstate 'ZX001' then null;
  end;
  -- Revogação e expiração nunca se transformam em replay bem-sucedido.
  begin
    update public.fontes_de_sinal set ativa=false where id=m ->> 'source_id';
    perform lab_radar._test_writer_error_v1(format(
      'select lab_radar.admitir_etiqueta_v1(%L::jsonb)',m),'lab_source_contract_invalid');
    raise exception using errcode='ZX002',message='rollback_source_test';
  exception when sqlstate 'ZX002' then null;
  end;

  return jsonb_build_object('status','passed','synthetic',true,'receipt',first_result,
    'checks',array['restricted_writer','privilege_escalation_denied_in_session','anchored_manifest',
      'destination_binding','cardinality_one','idempotency','logical_identity_conflicts',
      'source_and_concept_drift','late_failure_atomicity','public_drafts_invisible']);
end;
$$;
revoke all on function lab_radar.executar_testes_admissao_v1(jsonb) from public;

select lab_radar.preparar_fixture_de_teste_v1(current_setting('lab.fixture')::jsonb);
