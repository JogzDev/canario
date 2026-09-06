-- Laboratório descartável da 1.3. Aplicar DEPOIS de A51, nunca como migration.
-- O bootstrap registra o destino e o manifesto validado; o escritor só admite.
do $$
begin
  if current_database() !~ '^datadrobe_lab_[a-z0-9_]+$'
     or (inet_server_addr() is not null
         and inet_server_addr() not in ('127.0.0.1'::inet, '::1'::inet)) then
    raise exception 'lab_local_destination_required';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'lab_radar') then
    raise exception 'lab_schema_already_exists';
  end if;
  if exists (select 1 from pg_roles where rolname in
             ('datadrobe_lab_owner', 'datadrobe_lab_writer')) then
    raise exception 'lab_roles_already_exist';
  end if;
end;
$$;

create role datadrobe_lab_owner nologin nosuperuser nocreatedb nocreaterole
  noinherit bypassrls;
create role datadrobe_lab_writer login nosuperuser nocreatedb nocreaterole
  noinherit nobypassrls;
revoke create on schema public from public;
create schema lab_radar;
revoke all on schema lab_radar from public;
grant usage on schema lab_radar, public to datadrobe_lab_owner, datadrobe_lab_writer;

create table lab_radar.destino (
  singleton boolean primary key default true check (singleton),
  destination_id uuid not null unique,
  database_name text not null check (database_name ~ '^datadrobe_lab_[a-z0-9_]+$'),
  synthetic_only boolean not null default true check (synthetic_only),
  created_at timestamptz not null default clock_timestamp()
);

create table lab_radar.manifestos_autorizados (
  manifest_id text primary key check (manifest_id ~ '^[0-9a-f]{64}$'),
  destination_id uuid not null references lab_radar.destino(destination_id),
  manifesto jsonb not null check (jsonb_typeof(manifesto) = 'object'),
  conceito_snapshot jsonb not null,
  registered_at timestamptz not null default clock_timestamp(),
  check (manifesto ->> 'manifest_id' = manifest_id),
  check ((manifesto ->> 'destination_id')::uuid = destination_id),
  check (manifesto -> 'synthetic' = 'true'::jsonb)
);

create table lab_radar.recibos_admissao (
  receipt_id bigint generated always as identity primary key,
  logical_key text not null unique check (logical_key ~ '^[0-9a-f]{64}$'),
  manifest_id text not null unique references lab_radar.manifestos_autorizados,
  source_id text not null,
  source_item_external_id text not null,
  fact_id text not null,
  concept_id text not null,
  concept_version integer not null,
  extraction_version text not null,
  methodology_version text not null,
  template_version text not null,
  item_id bigint not null,
  evidence_id bigint not null,
  reading_id bigint not null,
  collection_run_id bigint not null,
  extraction_run_id bigint not null,
  brief_run_id bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (source_id, source_item_external_id, fact_id, concept_id,
          concept_version, extraction_version, methodology_version, template_version)
);

-- Sem FK para as linhas de negócio: a expiração pode removê-las, deixando
-- identidade e hashes no recibo. Reexecutar depois da poda falha explicitamente.
revoke all on all tables in schema lab_radar from public;
grant select on lab_radar.destino, lab_radar.manifestos_autorizados,
  lab_radar.recibos_admissao to datadrobe_lab_owner;
grant insert on lab_radar.recibos_admissao to datadrobe_lab_owner;
grant usage, select on sequence lab_radar.recibos_admissao_receipt_id_seq
  to datadrobe_lab_owner;

create function lab_radar._validar_destino_v1(p_destination_id uuid)
returns void language plpgsql
set search_path = pg_catalog, lab_radar, pg_temp as $$
begin
  if current_database() !~ '^datadrobe_lab_[a-z0-9_]+$'
     or (inet_server_addr() is not null
         and inet_server_addr() not in ('127.0.0.1'::inet, '::1'::inet))
     or not exists (
       select 1 from lab_radar.destino
       where singleton and destination_id = p_destination_id
         and database_name = current_database() and synthetic_only
     ) then
    raise exception 'lab_destination_mismatch';
  end if;
end;
$$;
revoke all on function lab_radar._validar_destino_v1(uuid) from public;
grant execute on function lab_radar._validar_destino_v1(uuid) to datadrobe_lab_owner;

create function lab_radar.registrar_destino_v1(p_destination_id uuid)
returns uuid language plpgsql
set search_path = pg_catalog, lab_radar, pg_temp as $$
begin
  if p_destination_id is null then raise exception 'lab_destination_required'; end if;
  if exists (select 1 from lab_radar.destino) then
    perform lab_radar._validar_destino_v1(p_destination_id);
    return p_destination_id;
  end if;
  insert into lab_radar.destino(destination_id, database_name)
    values (p_destination_id, current_database());
  perform lab_radar._validar_destino_v1(p_destination_id);
  return p_destination_id;
end;
$$;
revoke all on function lab_radar.registrar_destino_v1(uuid) from public;

create function lab_radar.registrar_manifesto_v1(p_manifest jsonb)
returns text language plpgsql
set search_path = pg_catalog, lab_radar, public, pg_temp as $$
declare
  v_snapshot jsonb;
  v_existing jsonb;
begin
  perform lab_radar._validar_destino_v1((p_manifest ->> 'destination_id')::uuid);
  if p_manifest ->> 'contract' is distinct from 'datadrobe_label_admission_manifest_v1'
     or p_manifest -> 'synthetic' is distinct from 'true'::jsonb then
    raise exception 'lab_synthetic_manifest_required';
  end if;
  select to_jsonb(c) into v_snapshot from public.conceitos_de_moda c
  where c.id = p_manifest ->> 'concept_id' and c.status = 'approved'
    and c.familia = 'fiber' and c.versao = (p_manifest ->> 'concept_version')::integer;
  if not found then raise exception 'lab_approved_fiber_concept_required'; end if;
  select manifesto into v_existing from lab_radar.manifestos_autorizados
    where manifest_id = p_manifest ->> 'manifest_id';
  if found then
    if v_existing is distinct from p_manifest then
      raise exception 'lab_anchor_conflict';
    end if;
    return p_manifest ->> 'manifest_id';
  end if;
  insert into lab_radar.manifestos_autorizados(
    manifest_id, destination_id, manifesto, conceito_snapshot)
  values (p_manifest ->> 'manifest_id',
          (p_manifest ->> 'destination_id')::uuid, p_manifest, v_snapshot);
  return p_manifest ->> 'manifest_id';
end;
$$;
revoke all on function lab_radar.registrar_manifesto_v1(jsonb) from public;

grant select on public.fontes_de_sinal, public.conceitos_de_moda,
  public.execucoes_de_pesquisa, public.itens_de_fonte,
  public.evidencias_de_sinal, public.leituras_de_mercado, public.leitura_evidencias
  to datadrobe_lab_owner;
grant insert (tipo, executor, codigo_sha, registro_sha256, metadados)
  on public.execucoes_de_pesquisa to datadrobe_lab_owner;
grant update (status, iniciada_em, terminada_em, itens_lidos, evidencias_geradas)
  on public.execucoes_de_pesquisa to datadrobe_lab_owner;
grant insert (fonte_id, execucao_id, id_externo, observado_em, tipo_conteudo,
  familia_origem, tipo_origem, geo, idioma, periodo_inicio, periodo_fim,
  unidade_original, transformacao_versao, conteudo_sha256, metadados)
  on public.itens_de_fonte to datadrobe_lab_owner;
grant insert (item_id, execucao_id, conceito_id, tipo, direcao, valor, resumo,
  territorio, periodo_inicio, periodo_fim, unidade, transformacao_versao,
  metodologia_versao) on public.evidencias_de_sinal to datadrobe_lab_owner;
grant insert (chave, execucao_id, conceito_id, semana, locale, territorio, titulo,
  resumo, estagio, metodologia_versao, lacunas)
  on public.leituras_de_mercado to datadrobe_lab_owner;
grant insert (leitura_id, evidencia_id, papel, ordem, nota)
  on public.leitura_evidencias to datadrobe_lab_owner;
grant usage, select on sequence public.execucoes_de_pesquisa_id_seq,
  public.itens_de_fonte_id_seq, public.evidencias_de_sinal_id_seq,
  public.leituras_de_mercado_id_seq to datadrobe_lab_owner;
grant execute on function public._url_https_segura_13(text),
  public._host_da_url_13(text), public._url_no_escopo_13(text,text,text),
  public._jsonb_sem_dados_brutos_13(jsonb),
  public._textos_revisaveis_13(text[],integer,integer) to datadrobe_lab_owner;

create function lab_radar.admitir_etiqueta_v1(p_manifest jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, lab_radar, public, pg_temp as $$
declare
  v_keys text[];
  v_expected text[] := array[
    'contract','manifest_id','logical_key','destination_id','source_package_id',
    'reviewed_package_id','review_batch_id','review_submission_sha256',
    'adjudication_submission_sha256','concept_review_sha256','fact_id',
    'review_subject_id','source_id','source_registry_sha256','source_contract_sha256',
    'authorization_sha256','code_sha','materializer_version','extraction_version',
    'methodology_version','template_version','concept_id','concept_version',
    'concept_contract_sha256','source_item_external_id','content_sha256',
    'observed_at','period_start','period_end','geo','language','unit','value',
    'summary','title','reading_summary','gaps','week','locale','synthetic'
  ];
  v_anchor lab_radar.manifestos_autorizados%rowtype;
  v_receipt lab_radar.recibos_admissao%rowtype;
  v_source public.fontes_de_sinal%rowtype;
  v_concept public.conceitos_de_moda%rowtype;
  v_field text;
  v_hash text;
  v_collection bigint;
  v_extraction bigint;
  v_brief bigint;
  v_item bigint;
  v_evidence bigint;
  v_reading bigint;
  v_observed timestamptz;
  v_start date;
  v_end date;
  v_week date;
  v_gaps text[];
  v_result jsonb;
begin
  if jsonb_typeof(p_manifest) is distinct from 'object'
     or octet_length(p_manifest::text) > 32768 then
    raise exception 'lab_manifest_invalid';
  end if;
  select array_agg(k order by k) into v_keys from jsonb_object_keys(p_manifest) k;
  select array_agg(k order by k) into v_expected from unnest(v_expected) k;
  if v_keys is distinct from v_expected then raise exception 'lab_manifest_fields_invalid'; end if;
  perform lab_radar._validar_destino_v1((p_manifest ->> 'destination_id')::uuid);
  if p_manifest ->> 'contract' is distinct from 'datadrobe_label_admission_manifest_v1'
     or p_manifest -> 'synthetic' is distinct from 'true'::jsonb then
    raise exception 'lab_synthetic_manifest_required';
  end if;
  foreach v_field in array array['manifest_id','logical_key','source_package_id',
      'reviewed_package_id','review_batch_id','concept_review_sha256','fact_id',
      'review_subject_id','source_registry_sha256','source_contract_sha256',
      'authorization_sha256','concept_contract_sha256','content_sha256'] loop
    if jsonb_typeof(p_manifest -> v_field) is distinct from 'string'
       or (p_manifest ->> v_field) !~ '^[0-9a-f]{64}$' then
      raise exception 'lab_manifest_hash_invalid:%', v_field;
    end if;
  end loop;
  if jsonb_typeof(p_manifest -> 'review_submission_sha256') is distinct from 'array'
     or jsonb_array_length(p_manifest -> 'review_submission_sha256') <> 2 then
    raise exception 'lab_two_reviews_required';
  end if;
  for v_hash in select jsonb_array_elements_text(p_manifest -> 'review_submission_sha256') loop
    if v_hash !~ '^[0-9a-f]{64}$' then raise exception 'lab_review_hash_invalid'; end if;
  end loop;
  if p_manifest #>> '{review_submission_sha256,0}' = p_manifest #>> '{review_submission_sha256,1}'
     or (p_manifest -> 'adjudication_submission_sha256' <> 'null'::jsonb
         and (p_manifest ->> 'adjudication_submission_sha256') !~ '^[0-9a-f]{64}$') then
    raise exception 'lab_review_hash_invalid';
  end if;
  select * into v_anchor from lab_radar.manifestos_autorizados
    where manifest_id = p_manifest ->> 'manifest_id';
  if not found or v_anchor.manifesto is distinct from p_manifest then
    raise exception 'lab_manifest_not_anchored';
  end if;
  -- Lock comum ao A51 vem primeiro: evita inversão com revogação/poda.
  perform pg_advisory_xact_lock(hashtextextended('canario:market-intelligence-13',0));
  select * into v_source from public.fontes_de_sinal
    where id = p_manifest ->> 'source_id';
  if not found or not v_source.ativa or v_source.status <> 'green'
     or v_source.url_scope <> 'internal' or v_source.tier <> 'T0'
     or v_source.autorizacao_expira_em <= current_date
     or v_source.termos_revisados_em <= current_date - 365
     or v_source.retencao_fatos_dias < 1
     or v_source.registro_sha256 <> p_manifest ->> 'source_registry_sha256'
     or v_source.contrato_sha256 <> p_manifest ->> 'source_contract_sha256'
     or v_source.autorizacao_sha256 <> p_manifest ->> 'authorization_sha256' then
    raise exception 'lab_source_contract_invalid';
  end if;
  select * into v_concept from public.conceitos_de_moda
    where id = p_manifest ->> 'concept_id';
  if not found or v_concept.status <> 'approved' or v_concept.familia <> 'fiber'
     or v_concept.versao <> (p_manifest ->> 'concept_version')::integer
     or to_jsonb(v_concept) is distinct from v_anchor.conceito_snapshot then
    raise exception 'lab_concept_contract_changed';
  end if;
  v_observed := (p_manifest ->> 'observed_at')::timestamptz;
  v_start := (p_manifest ->> 'period_start')::date;
  v_end := (p_manifest ->> 'period_end')::date;
  v_week := (p_manifest ->> 'week')::date;
  if v_observed is null or v_start is null or v_end is null or v_week is null
     or v_end < v_start or v_end > (v_observed at time zone 'UTC')::date
     or v_observed > clock_timestamp() + interval '10 minutes'
     or v_observed + make_interval(days => v_source.retencao_fatos_dias) <= clock_timestamp()
     or extract(isodow from v_week) <> 1 then
    raise exception 'lab_observation_time_invalid';
  end if;
  if p_manifest ->> 'unit' is distinct from 'declared_composition_percentage'
     or jsonb_typeof(p_manifest -> 'value') is distinct from 'object'
     or jsonb_typeof(p_manifest #> '{value,percentage}') is distinct from 'number'
     or (p_manifest #>> '{value,percentage}')::numeric not between 0 and 100
     or jsonb_typeof(p_manifest #> '{value,part_id}') is distinct from 'string'
     or length(p_manifest #>> '{value,part_id}') not between 1 and 120
     or ((p_manifest -> 'value') - 'percentage' - 'part_id') <> '{}'::jsonb then
    raise exception 'lab_composition_value_invalid';
  end if;
  if p_manifest ->> 'code_sha' !~ '^[0-9a-f]{7,64}$'
     or p_manifest ->> 'locale' is distinct from 'pt-BR'
     or p_manifest ->> 'geo' is distinct from 'BR'
     or p_manifest ->> 'summary' not like 'FICTÍCIO —%'
     or p_manifest ->> 'title' not like 'FICTÍCIO —%'
     or p_manifest ->> 'reading_summary' not like 'FICTÍCIO —%'
     or jsonb_typeof(p_manifest -> 'gaps') is distinct from 'array'
     or jsonb_array_length(p_manifest -> 'gaps') not between 1 and 12 then
    raise exception 'lab_reading_contract_invalid';
  end if;
  select array_agg(x) into v_gaps from jsonb_array_elements_text(p_manifest -> 'gaps') x;
  if not public._textos_revisaveis_13(v_gaps,12,3000) then
    raise exception 'lab_reading_gaps_invalid';
  end if;
  select * into v_receipt from lab_radar.recibos_admissao r
  where r.logical_key = p_manifest ->> 'logical_key'
     or (r.source_id = p_manifest ->> 'source_id'
         and r.source_item_external_id = p_manifest ->> 'source_item_external_id'
         and r.fact_id = p_manifest ->> 'fact_id'
         and r.concept_id = p_manifest ->> 'concept_id'
         and r.concept_version = (p_manifest ->> 'concept_version')::integer
         and r.extraction_version = p_manifest ->> 'extraction_version'
         and r.methodology_version = p_manifest ->> 'methodology_version'
         and r.template_version = p_manifest ->> 'template_version');
  if found then
    if v_receipt.manifest_id <> p_manifest ->> 'manifest_id'
       or v_receipt.logical_key <> p_manifest ->> 'logical_key' then
      raise exception 'lab_logical_identity_conflict';
    end if;
    if not exists (
      select 1 from public.itens_de_fonte i
      join public.evidencias_de_sinal e on e.item_id=i.id
      join public.leituras_de_mercado l on l.id=v_receipt.reading_id
      join public.leitura_evidencias le on le.leitura_id=l.id and le.evidencia_id=e.id
      where i.id=v_receipt.item_id and e.id=v_receipt.evidence_id
        and i.expira_em > now() and e.expira_em > now()
        and e.status='draft' and l.status='draft' and l.estagio='insufficient'
        and e.valor=p_manifest -> 'value' and e.resumo=p_manifest ->> 'summary'
        and l.titulo=p_manifest ->> 'title' and l.resumo=p_manifest ->> 'reading_summary'
        and l.cobertura='{}'::jsonb and e.conceito_versao=v_concept.versao
        and le.papel='supports' and le.ordem=1
    ) or (select count(*) from public.execucoes_de_pesquisa
          where id in (v_receipt.collection_run_id,v_receipt.extraction_run_id,v_receipt.brief_run_id)
            and status='success' and executor='local_deterministic') <> 3 then
      raise exception 'lab_receipt_result_not_current';
    end if;
    return (to_jsonb(v_receipt) - array['source_id','source_item_external_id','fact_id',
      'concept_id','concept_version','extraction_version','methodology_version','template_version',
      'created_at']) || jsonb_build_object('outcome','reused');
  end if;

  insert into public.execucoes_de_pesquisa(tipo,executor,codigo_sha,registro_sha256,metadados)
  values ('collection','local_deterministic',p_manifest ->> 'code_sha',
    p_manifest ->> 'source_registry_sha256',jsonb_build_object(
      'synthetic',true,'manifest_id',p_manifest ->> 'manifest_id')) returning id into v_collection;
  update public.execucoes_de_pesquisa set status='running',iniciada_em=clock_timestamp()
    where id=v_collection;
  insert into public.itens_de_fonte(fonte_id,execucao_id,id_externo,observado_em,
    tipo_conteudo,familia_origem,tipo_origem,geo,idioma,periodo_inicio,periodo_fim,
    unidade_original,transformacao_versao,conteudo_sha256,metadados)
  values (v_source.id,v_collection,p_manifest ->> 'source_item_external_id',v_observed,
    'product','datadrobe_label_synthetic','retail_observation',p_manifest ->> 'geo',
    p_manifest ->> 'language',v_start,v_end,p_manifest ->> 'unit',
    p_manifest ->> 'materializer_version',p_manifest ->> 'content_sha256',
    jsonb_build_object('synthetic',true,'source_package_id',p_manifest ->> 'source_package_id'))
  returning id into v_item;
  update public.execucoes_de_pesquisa set status='success',terminada_em=clock_timestamp(),itens_lidos=1
    where id=v_collection;

  insert into public.execucoes_de_pesquisa(tipo,executor,codigo_sha,registro_sha256,metadados)
  values ('extraction','local_deterministic',p_manifest ->> 'code_sha',
    p_manifest ->> 'source_registry_sha256',jsonb_build_object('synthetic',true,
      'reviewed_package_id',p_manifest ->> 'reviewed_package_id',
      'fact_id',p_manifest ->> 'fact_id','concept_review_sha256',p_manifest ->> 'concept_review_sha256'))
  returning id into v_extraction;
  update public.execucoes_de_pesquisa set status='running',iniciada_em=clock_timestamp()
    where id=v_extraction;
  insert into public.evidencias_de_sinal(item_id,execucao_id,conceito_id,tipo,direcao,
    valor,resumo,territorio,periodo_inicio,periodo_fim,unidade,transformacao_versao,metodologia_versao)
  values (v_item,v_extraction,v_concept.id,'composition','present',p_manifest -> 'value',
    p_manifest ->> 'summary',p_manifest ->> 'geo',v_start,v_end,p_manifest ->> 'unit',
    p_manifest ->> 'extraction_version',p_manifest ->> 'methodology_version')
  returning id into v_evidence;
  update public.execucoes_de_pesquisa set status='success',terminada_em=clock_timestamp(),
    itens_lidos=1,evidencias_geradas=1 where id=v_extraction;

  insert into public.execucoes_de_pesquisa(tipo,executor,codigo_sha,registro_sha256,metadados)
  values ('brief_generation','local_deterministic',p_manifest ->> 'code_sha',
    p_manifest ->> 'source_registry_sha256',jsonb_build_object('synthetic',true,
      'template_version',p_manifest ->> 'template_version','manifest_id',p_manifest ->> 'manifest_id'))
  returning id into v_brief;
  update public.execucoes_de_pesquisa set status='running',iniciada_em=clock_timestamp()
    where id=v_brief;
  insert into public.leituras_de_mercado(chave,execucao_id,conceito_id,semana,locale,
    territorio,titulo,resumo,estagio,metodologia_versao,lacunas)
  values ('lab_' || (p_manifest ->> 'logical_key'),v_brief,v_concept.id,v_week,
    p_manifest ->> 'locale',p_manifest ->> 'geo',p_manifest ->> 'title',
    p_manifest ->> 'reading_summary','insufficient',p_manifest ->> 'methodology_version',v_gaps)
  returning id into v_reading;
  insert into public.leitura_evidencias(leitura_id,evidencia_id,papel,ordem)
    values (v_reading,v_evidence,'supports',1);
  update public.execucoes_de_pesquisa set status='success',terminada_em=clock_timestamp(),itens_lidos=1
    where id=v_brief;
  insert into lab_radar.recibos_admissao(logical_key,manifest_id,source_id,source_item_external_id,
    fact_id,concept_id,concept_version,extraction_version,methodology_version,template_version,
    item_id,evidence_id,reading_id,collection_run_id,extraction_run_id,brief_run_id)
  values (p_manifest ->> 'logical_key',p_manifest ->> 'manifest_id',v_source.id,
    p_manifest ->> 'source_item_external_id',p_manifest ->> 'fact_id',v_concept.id,v_concept.versao,
    p_manifest ->> 'extraction_version',p_manifest ->> 'methodology_version',
    p_manifest ->> 'template_version',v_item,v_evidence,v_reading,v_collection,v_extraction,v_brief)
  returning * into v_receipt;
  v_result := to_jsonb(v_receipt) - array['source_id','source_item_external_id','fact_id',
    'concept_id','concept_version','extraction_version','methodology_version','template_version','created_at'];
  return v_result || jsonb_build_object('outcome','created');
end;
$$;
alter function lab_radar.admitir_etiqueta_v1(jsonb) owner to datadrobe_lab_owner;
revoke all on function lab_radar.admitir_etiqueta_v1(jsonb) from public;
grant execute on function lab_radar.admitir_etiqueta_v1(jsonb) to datadrobe_lab_writer;
comment on schema lab_radar is
  'P1: somente banco local descartável e dados sintéticos. Não aplicar em Supabase/produção.';
