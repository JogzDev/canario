-- A51: fundação paralela de inteligência de mercado da 1.3.
--
-- Esta migração não amplia `termos`, `produto_termos` ou `series_semanais`.
-- A taxonomia e as séries da 1.2 continuam congeladas; pesquisa, extração e
-- curadoria da 1.3 nascem num domínio próprio até terem cobertura comprovada.
--
-- O contrato é evidence-first:
--   * fonte sem direito de coleta aprovado não recebe item;
--   * evidência nasce draft e só uma revisão explícita a aprova ou rejeita;
--   * leitura nasce draft e só uma função transacional pode publicá-la;
--   * anon/authenticated veem apenas o que participa de leitura published;
--   * itens crus são metadados compactos e expiram; evidência publicada fica.

-- Helpers puros usados pelos CHECKs. URL com query é bloqueada nesta primeira
-- fundação: um parâmetro só será persistido quando um adaptador futuro trouxer
-- allowlist de chaves específica da fonte. Isso evita token/PII na trilha.
create or replace function public._url_https_segura_13(p_url text)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select length(p_url) <= 2048
    and p_url ~ '^https://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?([.][a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+(/[A-Za-z0-9._~!$&''()*+,;=:@%/-]*)?$'
    and p_url !~ '[?#[:space:][:cntrl:]]'
    and p_url !~* '/([.]|%2e)([.]|%2e)?(/|$)'
    and regexp_replace(
      substring(p_url from 9), '%[0-9A-Fa-f]{2}', '', 'g') !~ '%'
    and p_url !~* '(%0[0-9a-f]|%1[0-9a-f]|%7f|%25|%2f|%3f|%23|%5c)';
$$;

create or replace function public._host_da_url_13(p_url text)
returns text
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select lower(split_part(substring(p_url from 9), '/', 1));
$$;

create or replace function public._url_no_escopo_13(
  p_url text,
  p_base_host text,
  p_url_scope text
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select public._url_https_segura_13(p_url)
    and (
      (p_url_scope = 'exact_host'
       and public._host_da_url_13(p_url) = p_base_host)
      or
      (p_url_scope = 'domain_tree'
       and (
         public._host_da_url_13(p_url) = p_base_host
         or public._host_da_url_13(p_url) like '%.' || p_base_host
       ))
    );
$$;

create or replace function public._jsonb_sem_dados_brutos_13(p_valor jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_chave text;
  v_chave_normalizada text;
  v_filho jsonb;
begin
  if p_valor is null then return true; end if;
  if jsonb_typeof(p_valor) = 'object' then
    for v_chave, v_filho in select key, value from jsonb_each(p_valor)
    loop
      if length(v_chave) > 120 or v_chave ~ '[[:cntrl:]]' then
        return false;
      end if;
      -- Normalizar separadores/casing fecha variantes como `rawText`,
      -- `raw_text`, `article-body` e `source_content`. Hashes e contagens
      -- continuam permitidos (`raw_text_sha256`, `content_length`) porque não
      -- terminam no nome de um corpo bruto ou segredo.
      v_chave_normalizada := regexp_replace(
        lower(v_chave), '[^a-z0-9]+', '', 'g');
      if v_chave_normalizada = any(array[
        'apikey', 'authorization', 'body', 'comments', 'content', 'cookie',
        'fulltext', 'html', 'image', 'password', 'payload', 'prompt', 'raw',
        'rawhtml', 'rawtext', 'secret', 'sourcecontent', 'thumbnail', 'token',
        'transcript'
      ]) or v_chave_normalizada ~ '(article|page|request|response)(body|content)$' then
        return false;
      end if;
      if not public._jsonb_sem_dados_brutos_13(v_filho) then return false; end if;
    end loop;
  elsif jsonb_typeof(p_valor) = 'array' then
    for v_filho in select value from jsonb_array_elements(p_valor)
    loop
      if not public._jsonb_sem_dados_brutos_13(v_filho) then return false; end if;
    end loop;
  elsif jsonb_typeof(p_valor) = 'string'
        and octet_length(p_valor #>> '{}') > 2000 then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public._textos_revisaveis_13(
  p_textos text[],
  p_max_itens integer,
  p_max_bytes integer
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select cardinality(p_textos) <= p_max_itens
    and octet_length(array_to_string(p_textos, '|')) <= p_max_bytes
    and not exists (
      select 1 from unnest(p_textos) as t(valor)
      where t.valor is null
         or length(btrim(t.valor)) not between 1 and 500
    );
$$;

-- -------------------------------------------------------------------------
-- 1. Vocabulário da 1.3, separado da taxonomia de tendência da 1.2
-- -------------------------------------------------------------------------

create table public.conceitos_de_moda (
  id                 text primary key,
  familia            text not null,
  parent_id          text references public.conceitos_de_moda(id) on delete restrict,
  rotulo_pt          text not null,
  rotulo_en          text,
  definicao          text not null,
  aliases_pt         text[] not null default '{}'::text[],
  aliases_en         text[] not null default '{}'::text[],
  exemplos_positivos text[] not null default '{}'::text[],
  exemplos_negativos text[] not null default '{}'::text[],
  protocolo_promocao_versao text,
  volume_observado   integer not null default 0,
  volume_minimo_exigido integer not null default 1,
  status             text not null default 'proposed',
  versao             integer not null default 1,
  revisada_em        timestamptz,
  revisada_por       text,
  motivo_rejeicao    text,
  retirada_em        timestamptz,
  retirada_por       text,
  motivo_retirada    text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  constraint conceitos_id_estavel check (
    id ~ '^[a-z0-9][a-z0-9_]{1,79}$'
  ),
  constraint conceitos_familia_controlada check (familia in (
    'product_category', 'color', 'print', 'fiber', 'fabric_construction',
    'surface_finish', 'texture', 'apparent_weight', 'shape', 'fit', 'length',
    'construction_detail', 'styling', 'accessory', 'occasion', 'aesthetic'
  )),
  constraint conceitos_status_controlado check (
    status in ('proposed', 'approved', 'rejected', 'retired')
  ),
  constraint conceitos_sem_auto_parent check (parent_id is null or parent_id <> id),
  constraint conceitos_rotulos_limitados check (
    length(btrim(rotulo_pt)) between 1 and 120
    and (rotulo_en is null or length(btrim(rotulo_en)) between 1 and 120)
    and length(btrim(definicao)) between 1 and 1000
  ),
  constraint conceitos_aliases_compactos check (
    cardinality(aliases_pt) + cardinality(aliases_en) <= 32
    and public._textos_revisaveis_13(aliases_pt || aliases_en, 32, 4096)
  ),
  constraint conceitos_exemplos_compactos check (
    public._textos_revisaveis_13(exemplos_positivos, 16, 4096)
    and public._textos_revisaveis_13(exemplos_negativos, 16, 4096)
  ),
  constraint conceitos_volume_e_protocolo_validos check (
    volume_observado between 0 and 1000000
    and volume_minimo_exigido between 1 and 1000000
    and (
      protocolo_promocao_versao is null
      or length(btrim(protocolo_promocao_versao)) between 1 and 120
    )
  ),
  constraint conceitos_promocao_comprovada check (
    status not in ('approved', 'retired')
    or (
      cardinality(aliases_pt) + cardinality(aliases_en) > 0
      and cardinality(exemplos_positivos) > 0
      and cardinality(exemplos_negativos) > 0
      and protocolo_promocao_versao is not null
      and volume_observado >= volume_minimo_exigido
    )
  ),
  constraint conceitos_revisao_coerente check (
    (
      status = 'proposed'
      and revisada_em is null and revisada_por is null
      and motivo_rejeicao is null and retirada_em is null
      and retirada_por is null and motivo_retirada is null
    )
    or (
      status = 'approved'
      and revisada_em is not null and revisada_por is not null
      and motivo_rejeicao is null and retirada_em is null
      and retirada_por is null and motivo_retirada is null
    )
    or (
      status = 'rejected'
      and revisada_em is not null and revisada_por is not null
      and motivo_rejeicao is not null and retirada_em is null
      and retirada_por is null and motivo_retirada is null
    )
    or (
      status = 'retired'
      and revisada_em is not null and revisada_por is not null
      and motivo_rejeicao is null and retirada_em is not null
      and retirada_por is not null and motivo_retirada is not null
    )
  ),
  constraint conceitos_revisores_limitados check (
    (revisada_por is null or length(btrim(revisada_por)) between 1 and 160)
    and (retirada_por is null or length(btrim(retirada_por)) between 1 and 160)
    and (motivo_rejeicao is null or length(btrim(motivo_rejeicao)) between 1 and 1000)
    and (motivo_retirada is null or length(btrim(motivo_retirada)) between 1 and 1000)
    and (revisada_em is null or revisada_em <= now() + interval '10 minutes')
    and (retirada_em is null or retirada_em <= now() + interval '10 minutes')
  ),
  constraint conceitos_versao_positiva check (versao > 0)
);

comment on table public.conceitos_de_moda is
  'A51: ontologia hierárquica da 1.3. Não substitui nem amplia automaticamente a taxonomia aprovada da 1.2.';

create table public.mapeamentos_de_conceito_legado (
  conceito_id       text not null references public.conceitos_de_moda(id) on delete restrict,
  termo_id          text not null references public.termos(id) on delete restrict,
  relacao           text not null,
  nota              text,
  criado_em         timestamptz not null default now(),
  primary key (conceito_id, termo_id),
  constraint mapeamentos_relacao_controlada check (relacao in (
    'exact', 'broader', 'narrower', 'related'
  )),
  constraint mapeamentos_nota_limitada check (
    nota is null or length(btrim(nota)) between 1 and 500
  )
);

comment on table public.mapeamentos_de_conceito_legado is
  'A51: ponte explícita, muitos-para-muitos, entre um conceito da 1.3 e `termos` da 1.2. A relação descreve o conceito novo em relação ao termo legado.';

-- -------------------------------------------------------------------------
-- 2. Registro de fontes e portão explícito de direitos
-- -------------------------------------------------------------------------

create table public.fontes_de_sinal (
  id                       text primary key,
  nome                     text not null,
  sensor                   text not null,
  tier                     text not null,
  metodo                   text not null,
  status                   text not null default 'red',
  ai_processing            text not null default 'none',
  openai_retention_mode    text not null default 'none',
  display_rights           text not null default 'none',
  retencao_dias            integer not null default 0,
  retencao_fatos_dias      integer not null default 0,
  base_url                 text not null default '',
  base_host                text,
  url_scope                text not null,
  termos_url               text not null,
  termos_versao            text not null,
  termos_revisados_em      date not null,
  autorizacao_sha256       text,
  aprovada_por             text,
  aprovada_em              date,
  autorizacao_expira_em    date,
  contrato_sha256          text not null,
  registro_sha256          text not null,
  observacao               text not null,
  ativa                    boolean not null default false,
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now(),
  constraint fontes_id_estavel check (
    length(id) between 1 and 80
    and id ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint fontes_tier_controlado check (tier in ('T0', 'T1', 'T2', 'T3')),
  constraint fontes_status_controlado check (status in ('green', 'yellow', 'red')),
  constraint fontes_ai_controlada check (
    ai_processing in ('none', 'facts', 'full_text')
  ),
  constraint fontes_openai_retencao_controlada check (
    openai_retention_mode in ('none', 'standard_30d')
  ),
  constraint fontes_escopo_controlado check (
    url_scope in ('internal', 'exact_host', 'domain_tree')
  ),
  constraint fontes_exibicao_controlada check (display_rights in (
    'own_content', 'facts_and_canonical_link', 'link_only',
    'official_metadata_with_attribution', 'licensed_content', 'none'
  )),
  constraint fontes_campos_limitados check (
    length(btrim(nome)) between 1 and 160
    and length(btrim(sensor)) between 1 and 80
    and length(btrim(metodo)) between 1 and 120
    and length(base_url) <= 2048
    and length(termos_url) between 1 and 2048
    and length(btrim(termos_versao)) between 1 and 160
    and (aprovada_por is null or length(btrim(aprovada_por)) between 1 and 160)
    and length(btrim(observacao)) between 1 and 2000
  ),
  constraint fontes_origem_e_termos_validos check (
    (
      tier = 'T0' and metodo = 'curadoria_interna'
      and base_url = ''
      and base_host is null
      and url_scope = 'internal'
      and termos_url = 'GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md'
    )
    or (
      public._url_https_segura_13(base_url)
      and base_host is not null
      and base_host ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?([.][a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
      and public._host_da_url_13(base_url) = base_host
      and url_scope in ('exact_host', 'domain_tree')
      and public._url_https_segura_13(termos_url)
    )
  ),
  constraint fontes_scout_escopo_explicito check (
    metodo <> 'hosted_web_search_domain_tree'
    or (
      url_scope = 'domain_tree'
      and base_url = 'https://' || base_host
    )
  ),
  constraint fontes_green_origem_inteira check (
    status <> 'green'
    or url_scope = 'internal'
    or base_url = 'https://' || base_host
  ),
  constraint fontes_green_elegivel check (
    status <> 'green'
    or (
      tier <> 'T3'
      and display_rights <> 'none'
      and retencao_fatos_dias > 0
    )
  ),
  constraint fontes_ai_retencao_coerente check (
    (ai_processing = 'none' and openai_retention_mode = 'none')
    or (
      ai_processing in ('facts', 'full_text')
      and openai_retention_mode = 'standard_30d'
      and retencao_dias >= 30
    )
  ),
  constraint fontes_retencao_limitada check (
    retencao_dias between 0 and 90
    and retencao_fatos_dias between 0 and 3650
  ),
  constraint fontes_revisao_nao_futura check (
    termos_revisados_em <= current_date
  ),
  constraint fontes_aprovacao_coerente check (
    (
      autorizacao_sha256 is null and aprovada_por is null
      and aprovada_em is null and autorizacao_expira_em is null
    )
    or (
      autorizacao_sha256 is not null
      and autorizacao_sha256 ~ '^[0-9a-f]{64}$'
      and aprovada_por is not null
      and aprovada_em is not null
      and autorizacao_expira_em is not null
      and aprovada_em <= current_date
      and autorizacao_expira_em >= aprovada_em
    )
  ),
  constraint fontes_green_tem_aprovacao check (
    status <> 'green'
    or (
      autorizacao_sha256 is not null
      and aprovada_por is not null
      and aprovada_em is not null
      and autorizacao_expira_em is not null
    )
  ),
  constraint fontes_hash_registro_valido check (
    contrato_sha256 ~ '^[0-9a-f]{64}$'
    and
    registro_sha256 ~ '^[0-9a-f]{64}$'
  )
);

comment on table public.fontes_de_sinal is
  'A51: espelho do registro de direitos da 1.3. `ativa` mantém a linha vigente; só `status=green`, IA e retenção OpenAI compatíveis, termos atuais e retenção factual positiva atravessam o portão de itens.';

-- Espelho determinístico de `anexos/fontes_radar.csv`. `contrato_sha256` usa
-- JSON compacto da linha com chaves lexicográficas; `registro_sha256` usa os
-- bytes integrais do CSV. O teste offline recalcula ambos e exige paridade.
insert into public.fontes_de_sinal (
  id, nome, sensor, tier, metodo, status, ai_processing,
  openai_retention_mode, display_rights, retencao_dias,
  retencao_fatos_dias, base_url, base_host, url_scope, termos_url,
  termos_versao, termos_revisados_em, autorizacao_sha256, aprovada_por,
  aprovada_em, autorizacao_expira_em, contrato_sha256, registro_sha256,
  observacao, ativa
) values
  ('datadrobe_curadoria_interna', 'DataDrobe — curadoria e fatos próprios', 'curadoria_propria', 'T0', 'curadoria_interna', 'green', 'full_text', 'standard_30d', 'own_content', 30, 3650, '', null, 'internal', 'GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md', '1.0.0', '2026-08-31', 'adc6fba462d0e10c53a08857cba8a4875c4c5d7b77a84875e9e2cb5ab6d9db49', 'jpscoliveira', '2026-08-31', '2027-08-31', '1faf19de3b2ed6c844acee7711fd78b90db8b9f40206533ec24ad73c33e095ba', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Fonte interna sem origem web; o Scout deve ignorá-la', true),
  ('google_trends_alpha', 'Google Trends API alpha', 'interesse_de_busca', 'T1', 'api_oficial_alpha', 'yellow', 'none', 'none', 'none', 0, 0, 'https://developers.google.com/search/apis/trends', 'developers.google.com', 'exact_host', 'https://developers.google.com/search/apis/trends', 'alpha-consultada-2026-08-31', '2026-08-31', null, null, null, null, '190310f5dc06cff02d86240a0ef1895b07a9ea45ca533b9ebaaed817b4540f92', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Aguardando concessão de acesso e revisão do escopo contratado', true),
  ('pinterest_trends_api', 'Pinterest Trends API', 'inspiracao_visual', 'T1', 'api_oficial_trends', 'red', 'none', 'none', 'none', 0, 0, 'https://api.pinterest.com', 'api.pinterest.com', 'exact_host', 'https://policy.pinterest.com/en/developer-guidelines', 'leitura-2026-08-18', '2026-08-18', null, null, null, null, 'c7fe2efac4328991102cf8f95ef69ee23257abf51680bbdb5618460bb06e0436', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Bloqueada até autorização escrita que cubra análise comercial e processamento por IA', true),
  ('guardian_open_platform_commercial', 'Guardian Open Platform — Commercial', 'cobertura_editorial', 'T1', 'api_oficial_commercial', 'yellow', 'none', 'none', 'link_only', 0, 0, 'https://www.theguardian.com', 'www.theguardian.com', 'exact_host', 'https://open-platform.theguardian.com/access/', 'commercial-consultado-2026-08-31', '2026-08-31', null, null, null, null, '4930571438c76497fe206a5b4f128b1622113e3288461d84980e63ae28865cd2', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Aguardando chave e licença Commercial com escopo de uso e IA aprovado', true),
  ('youtube_data_api_curated', 'YouTube Data API — canais curados', 'publicacao_de_creators', 'T1', 'api_oficial_canais_curados', 'yellow', 'none', 'none', 'official_metadata_with_attribution', 0, 0, 'https://www.youtube.com', 'www.youtube.com', 'exact_host', 'https://developers.google.com/youtube/terms/developer-policies', 'developer-policies-consultadas-2026-08-31', '2026-08-31', null, null, null, null, '66338f2f2e97b14ff5f98be9125dfc2e27d3ff8628e6989f9aa0f93ca34bae99', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Aguardando allowlist humana de canais validação de precisão e adequação às políticas', true),
  ('guardian_rss_manual', 'Guardian Fashion RSS — descoberta manual', 'cobertura_editorial', 'T2', 'rss_publico_descoberta_manual', 'yellow', 'none', 'none', 'link_only', 0, 0, 'https://www.theguardian.com/fashion', 'www.theguardian.com', 'exact_host', 'https://open-platform.theguardian.com/access/', 'commercial-consultado-2026-08-31', '2026-08-31', null, null, null, null, 'd653f40a72430539a1fe3180f855810a3c5a6cf93a2f990cbe766512e4a1975f', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'RSS público não substitui a licença Commercial exigida para uso no produto', true),
  ('pinterest_scraping_web', 'Pinterest web — scraping', 'inspiracao_visual', 'T3', 'scraping_web_social', 'red', 'none', 'none', 'none', 0, 0, 'https://www.pinterest.com', 'www.pinterest.com', 'exact_host', 'https://policy.pinterest.com/en/developer-guidelines', 'leitura-2026-08-18', '2026-08-18', null, null, null, null, 'ff231841e1d453cf95ad68a94e371d53bb8ef418a5232f9fc626c57175632766', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Automação e extração fora da API são proibidas por padrão', true),
  ('youtube_scraping_web', 'YouTube web — scraping', 'publicacao_de_creators', 'T3', 'scraping_web_social', 'red', 'none', 'none', 'none', 0, 0, 'https://www.youtube.com', 'www.youtube.com', 'exact_host', 'https://developers.google.com/youtube/terms/developer-policies', 'developer-policies-consultadas-2026-08-31', '2026-08-31', null, null, null, null, 'e458e7231e00dbbf00c7a1a91b23bab452b5874a91300577f3373248f884b47e', '2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075', 'Não usar scraping download de vídeo thumbnail comentário ou fallback privado', true);

-- -------------------------------------------------------------------------
-- 3. Execuções auditáveis e com custo limitado por linha
-- -------------------------------------------------------------------------

create table public.execucoes_de_pesquisa (
  id                    bigint generated always as identity primary key,
  tipo                  text not null,
  executor              text not null,
  status                text not null default 'queued',
  modelo                text,
  prompt_version        text,
  openai_project_id     text,
  openai_retention_mode text,
  service_tier          text,
  response_id           text,
  codigo_sha            text not null,
  registro_sha256       text not null,
  solicitada_em         timestamptz not null default now(),
  iniciada_em           timestamptz,
  terminada_em          timestamptz,
  itens_lidos           integer not null default 0,
  evidencias_geradas    integer not null default 0,
  tokens_entrada        integer not null default 0,
  tokens_saida          integer not null default 0,
  chamadas_web          integer not null default 0,
  custo_usd             numeric(12,6) not null default 0,
  erro                  text,
  metadados             jsonb not null default '{}'::jsonb,
  constraint execucoes_tipo_controlado check (tipo in (
    'collection', 'research', 'extraction', 'aggregation',
    'brief_generation', 'backfill'
  )),
  constraint execucoes_status_controlado check (status in (
    'queued', 'running', 'success', 'failed', 'cancelled'
  )),
  constraint execucoes_executor_controlado check (executor in (
    'local_deterministic', 'source_api', 'openai_responses', 'human_review'
  )),
  constraint execucoes_identidade_limitada check (
    (modelo is null or length(btrim(modelo)) between 1 and 120)
    and (prompt_version is null or length(btrim(prompt_version)) between 1 and 120)
    and (openai_project_id is null or openai_project_id ~ '^proj_[A-Za-z0-9_-]{6,200}$')
    and (response_id is null or response_id ~ '^resp_[A-Za-z0-9_-]{6,200}$')
    and codigo_sha ~ '^[0-9a-f]{7,64}$'
    and registro_sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint execucoes_rota_coerente check (
    (
      executor = 'openai_responses'
      and modelo is not null
      and modelo ~ '^gpt-5[.]6-luna(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$'
      and prompt_version is not null
      and openai_project_id is not null
      and openai_retention_mode is not null
      and openai_retention_mode = 'standard_30d'
      and service_tier is not null
      and service_tier = 'default'
    )
    or (
      executor <> 'openai_responses'
      and modelo is null and prompt_version is null
      and openai_project_id is null and openai_retention_mode is null
      and service_tier is null and response_id is null
      and chamadas_web = 0 and tokens_entrada = 0 and tokens_saida = 0
      and custo_usd = 0
    )
  ),
  constraint execucoes_contadores_nao_negativos check (
    itens_lidos >= 0 and evidencias_geradas >= 0
    and tokens_entrada >= 0 and tokens_saida >= 0
    and chamadas_web between 0 and 100 and custo_usd >= 0
  ),
  constraint execucoes_relogio_coerente check (
    (status = 'queued' and iniciada_em is null and terminada_em is null)
    or (status = 'running' and iniciada_em is not null and terminada_em is null)
    or (status in ('success', 'failed', 'cancelled')
        and iniciada_em is not null and terminada_em is not null
        and terminada_em >= iniciada_em)
  ),
  constraint execucoes_erro_coerente check (
    (status = 'failed' and erro is not null
      and erro ~ '^[a-z0-9_:-]{1,120}$')
    or (status <> 'failed' and erro is null)
  ),
  constraint execucoes_metadados_compactos check (
    jsonb_typeof(metadados) = 'object'
    and octet_length(metadados::text) <= 8192
    and public._jsonb_sem_dados_brutos_13(metadados)
  )
);

comment on table public.execucoes_de_pesquisa is
  'A51: proveniência de coleta/pesquisa/extração, incluindo modelo, prompt, SHA, tokens e custo; nunca é pública.';

-- -------------------------------------------------------------------------
-- 4. Itens de fonte: URL e metadados, nunca cópia integral do conteúdo
-- -------------------------------------------------------------------------

create table public.itens_de_fonte (
  id                 bigint generated always as identity primary key,
  fonte_id           text not null references public.fontes_de_sinal(id) on delete restrict,
  execucao_id        bigint not null references public.execucoes_de_pesquisa(id) on delete restrict,
  id_externo         text,
  url_canonica       text,
  titulo             text,
  publicado_em       timestamptz,
  observado_em       timestamptz not null default now(),
  tipo_conteudo      text not null,
  familia_origem     text not null,
  tipo_origem        text not null,
  geo                text not null,
  idioma             text not null,
  periodo_inicio     date not null,
  periodo_fim        date not null,
  unidade_original   text not null,
  transformacao_versao text not null,
  conteudo_sha256    text not null,
  termos_versao      text not null,
  fonte_contrato_sha256 text not null,
  autorizacao_sha256 text not null,
  metadados          jsonb not null default '{}'::jsonb,
  expira_em          timestamptz not null,
  criado_em          timestamptz not null default now(),
  constraint itens_fonte_url_https check (
    url_canonica is null or public._url_https_segura_13(url_canonica)
  ),
  constraint itens_fonte_tem_identidade check (
    url_canonica is not null or id_externo is not null
  ),
  constraint itens_fonte_tipo_controlado check (tipo_conteudo in (
    'post', 'video', 'pin', 'article', 'product', 'look',
    'show', 'search_result', 'manual_note', 'other'
  )),
  constraint itens_fonte_origem_controlada check (tipo_origem in (
    'original_report', 'press_release', 'syndication',
    'commentary', 'retail_observation'
  )),
  constraint itens_fonte_campos_limitados check (
    (id_externo is null or length(id_externo) <= 500)
    and (titulo is null or length(titulo) <= 500)
    and length(btrim(familia_origem)) between 1 and 160
    and length(btrim(termos_versao)) between 1 and 160
    and length(btrim(geo)) between 1 and 40
    and length(btrim(idioma)) between 1 and 16
    and length(btrim(unidade_original)) between 1 and 120
    and length(btrim(transformacao_versao)) between 1 and 120
  ),
  constraint itens_fonte_hash_valido check (
    conteudo_sha256 ~ '^[0-9a-f]{64}$'
    and fonte_contrato_sha256 ~ '^[0-9a-f]{64}$'
    and autorizacao_sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint itens_fonte_periodo_coerente check (
    periodo_fim >= periodo_inicio
    and periodo_fim <= observado_em::date
  ),
  constraint itens_fonte_relogio_coerente check (
    (publicado_em is null or publicado_em <= observado_em + interval '10 minutes')
    and observado_em <= now() + interval '10 minutes'
    and expira_em > observado_em
  ),
  constraint itens_fonte_metadados_compactos check (
    jsonb_typeof(metadados) = 'object'
    and octet_length(metadados::text) <= 4096
    and public._jsonb_sem_dados_brutos_13(metadados)
  ),
  constraint itens_fonte_url_unica unique (fonte_id, url_canonica)
);

comment on table public.itens_de_fonte is
  'A51: metadado rastreável de um item externo. Sem corpo de artigo, imagem ou vídeo; drafts expiram conforme a fonte.';

-- -------------------------------------------------------------------------
-- 5. Evidência estruturada, revisão humana e imutabilidade depois da revisão
-- -------------------------------------------------------------------------

create table public.evidencias_de_sinal (
  id                         bigint generated always as identity primary key,
  item_id                    bigint not null references public.itens_de_fonte(id) on delete restrict,
  execucao_id                bigint not null references public.execucoes_de_pesquisa(id) on delete restrict,
  conceito_id                text not null references public.conceitos_de_moda(id) on delete restrict,
  tipo                       text not null,
  direcao                    text not null default 'present',
  valor                      jsonb not null default '{}'::jsonb,
  resumo                     text not null,
  territorio                 text not null,
  periodo_inicio             date not null,
  periodo_fim                date not null,
  unidade                    text not null,
  transformacao_versao       text not null,
  conceito_versao            integer not null,
  confianca_extracao         numeric(5,4),
  metodologia_versao         text not null,
  status                     text not null default 'draft',
  revisada_em                timestamptz,
  revisada_por               text,
  motivo_rejeicao            text,
  revogada_em                timestamptz,
  motivo_revogacao           text,
  expira_em                  timestamptz not null,
  criada_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  constraint evidencias_tipo_controlado check (tipo in (
    'mention', 'visual_presence', 'composition', 'assortment',
    'movement', 'context', 'absence'
  )),
  constraint evidencias_direcao_controlada check (direcao in (
    'present', 'rising', 'stable', 'falling', 'absent', 'mixed', 'not_applicable'
  )),
  constraint evidencias_status_controlado check (
    status in ('draft', 'approved', 'rejected', 'revoked')
  ),
  constraint evidencias_valor_compacto check (
    jsonb_typeof(valor) = 'object'
    and octet_length(valor::text) <= 4096
    and public._jsonb_sem_dados_brutos_13(valor)
  ),
  constraint evidencias_campos_limitados check (
    length(btrim(resumo)) between 1 and 1000
    and length(btrim(territorio)) between 1 and 80
    and length(btrim(unidade)) between 1 and 120
    and length(btrim(transformacao_versao)) between 1 and 120
    and length(btrim(metodologia_versao)) between 1 and 120
    and (revisada_por is null or length(btrim(revisada_por)) between 1 and 160)
    and (motivo_rejeicao is null or length(btrim(motivo_rejeicao)) between 1 and 1000)
    and (motivo_revogacao is null or length(btrim(motivo_revogacao)) between 1 and 1000)
  ),
  constraint evidencias_periodo_coerente check (
    periodo_fim >= periodo_inicio and conceito_versao > 0
    and expira_em > criada_em
  ),
  constraint evidencias_confianca_de_extracao check (
    confianca_extracao is null
    or (confianca_extracao >= 0 and confianca_extracao <= 1)
  ),
  constraint evidencias_revisao_coerente check (
    (status = 'draft' and revisada_em is null and revisada_por is null
      and motivo_rejeicao is null and revogada_em is null
      and motivo_revogacao is null)
    or (status = 'approved' and revisada_em is not null and revisada_por is not null
      and motivo_rejeicao is null and revogada_em is null
      and motivo_revogacao is null)
    or (status = 'rejected' and revisada_em is not null and revisada_por is not null
      and motivo_rejeicao is not null and revogada_em is null
      and motivo_revogacao is null)
    or (status = 'revoked' and revogada_em is not null
      and motivo_revogacao is not null)
  ),
  constraint evidencias_sem_duplicata_na_execucao
    unique (item_id, conceito_id, tipo, execucao_id)
);

comment on column public.evidencias_de_sinal.confianca_extracao is
  'Confiança técnica da extração do item, nunca probabilidade de adoção, venda ou sucesso.';

-- -------------------------------------------------------------------------
-- 6. Leituras editoriais e ligações explícitas supports/contradicts/context
-- -------------------------------------------------------------------------

create table public.leituras_de_mercado (
  id                    bigint generated always as identity primary key,
  chave                 text not null,
  execucao_id           bigint not null references public.execucoes_de_pesquisa(id) on delete restrict,
  conceito_id           text references public.conceitos_de_moda(id) on delete restrict,
  semana                date not null,
  locale                text not null default 'pt-BR',
  territorio            text not null,
  titulo                text not null,
  resumo                text not null,
  estagio               text not null,
  metodologia_versao    text not null,
  lacunas               text[] not null default '{}'::text[],
  cobertura             jsonb not null default '{}'::jsonb,
  status                text not null default 'draft',
  publicada_em          timestamptz,
  publicada_por         text,
  retirada_em           timestamptz,
  retirada_por          text,
  motivo_retirada       text,
  criada_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  constraint leituras_chave_estavel check (
    chave ~ '^[a-z0-9][a-z0-9_]{1,99}$'
  ),
  constraint leituras_semana_iso check (extract(isodow from semana) = 1),
  constraint leituras_locale_limitado check (
    locale ~ '^[a-z]{2}(-[A-Z]{2})?$' and length(locale) <= 8
  ),
  constraint leituras_estagio_descritivo check (estagio in (
    'global_only', 'br_editorial_observed', 'br_search_observed',
    'br_retail_early', 'br_retail_broad', 'cooling',
    'divergent', 'insufficient'
  )),
  constraint leituras_status_controlado check (
    status in ('draft', 'published', 'withdrawn')
  ),
  constraint leituras_campos_limitados check (
    length(btrim(titulo)) between 1 and 180
    and length(btrim(resumo)) between 1 and 2000
    and length(btrim(territorio)) between 1 and 80
    and length(btrim(metodologia_versao)) between 1 and 120
    and (publicada_por is null or length(btrim(publicada_por)) between 1 and 160)
    and (retirada_por is null or length(btrim(retirada_por)) between 1 and 160)
    and (motivo_retirada is null or length(btrim(motivo_retirada)) between 1 and 1000)
  ),
  constraint leituras_cobertura_compacta check (
    jsonb_typeof(cobertura) = 'object'
    and octet_length(cobertura::text) <= 4096
    and public._jsonb_sem_dados_brutos_13(cobertura)
  ),
  constraint leituras_lacunas_compactas check (
    cardinality(lacunas) between 0 and 12
    and octet_length(array_to_string(lacunas, '|')) <= 3000
  ),
  constraint leituras_publicacao_coerente check (
    (status = 'draft' and publicada_em is null and publicada_por is null
      and retirada_em is null and retirada_por is null and motivo_retirada is null)
    or (status = 'published' and publicada_em is not null and publicada_por is not null
      and retirada_em is null and retirada_por is null and motivo_retirada is null)
    or (status = 'withdrawn' and publicada_em is not null and publicada_por is not null
      and retirada_em is not null and retirada_por is not null
      and motivo_retirada is not null)
  ),
  constraint leituras_chave_semana_locale unique (chave, semana, locale)
);

create table public.leitura_evidencias (
  leitura_id       bigint not null references public.leituras_de_mercado(id) on delete cascade,
  evidencia_id     bigint not null references public.evidencias_de_sinal(id) on delete cascade,
  papel            text not null,
  ordem            smallint not null,
  nota             text,
  primary key (leitura_id, evidencia_id),
  constraint leitura_evidencias_papel_controlado check (
    papel in ('supports', 'contradicts', 'context')
  ),
  constraint leitura_evidencias_ordem_limitada check (ordem between 1 and 100),
  constraint leitura_evidencias_nota_limitada check (
    nota is null or length(btrim(nota)) between 1 and 500
  ),
  constraint leitura_evidencias_ordem_unica unique (leitura_id, papel, ordem)
);

comment on table public.leituras_de_mercado is
  'A51: leitura descritiva da 1.3. Estágios representam evidência observada, nunca previsão ou probabilidade.';

-- -------------------------------------------------------------------------
-- 7. Índices: caminhos de publicação, auditoria e poda sem varredura larga
-- -------------------------------------------------------------------------

create index conceitos_familia_status
  on public.conceitos_de_moda (familia, status, id);
create index conceitos_parent
  on public.conceitos_de_moda (parent_id) where parent_id is not null;
create index mapeamentos_legado_por_termo
  on public.mapeamentos_de_conceito_legado (termo_id, conceito_id);
create index fontes_sensor_ativas
  on public.fontes_de_sinal (sensor, status, id)
  where ativa and status = 'green';
create index execucoes_status_tempo
  on public.execucoes_de_pesquisa (status, solicitada_em desc);
create unique index execucoes_response_id_unico
  on public.execucoes_de_pesquisa (response_id)
  where response_id is not null;
create unique index itens_fonte_id_externo_unico
  on public.itens_de_fonte (fonte_id, id_externo)
  where id_externo is not null;
create index itens_fonte_publicacao
  on public.itens_de_fonte (fonte_id, publicado_em desc nulls last, id);
create index itens_execucao
  on public.itens_de_fonte (execucao_id, id);
create index itens_expiracao
  on public.itens_de_fonte (expira_em, id);
create index evidencias_conceito_aprovadas
  on public.evidencias_de_sinal (conceito_id, criada_em desc, id)
  where status = 'approved';
create index evidencias_item
  on public.evidencias_de_sinal (item_id, id);
create index evidencias_execucao
  on public.evidencias_de_sinal (execucao_id, id);
create index leituras_publicadas_semana
  on public.leituras_de_mercado (semana desc, id)
  where status = 'published';
create index leitura_evidencias_por_evidencia
  on public.leitura_evidencias (evidencia_id, leitura_id);

-- -------------------------------------------------------------------------
-- 8. Triggers de integridade
-- -------------------------------------------------------------------------

create or replace function public._marcar_atualizado_em_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- UPDATE de fonte adquire o mesmo lock global antes de o PostgreSQL bloquear
-- qualquer linha. Isso mantém a ordem advisory -> fonte -> leitura/evidência
-- usada pela publicação e evita o ciclo fonte -> leitura contra leitura ->
-- fonte durante uma revogação concorrente.
create or replace function public._serializar_escritas_criticas_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));
  return null;
end;
$$;

create or replace function public._validar_hierarquia_conceito_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_familia text;
  v_status text;
begin
  if new.parent_id is not null then
    select familia, status into v_familia, v_status
    from public.conceitos_de_moda
    where id = new.parent_id;

    if not found then
      raise exception 'concept_parent_not_found';
    end if;
    if v_familia <> new.familia then
      raise exception 'concept_parent_family_mismatch';
    end if;
    if new.status = 'approved' and v_status <> 'approved' then
      raise exception 'approved_concept_requires_approved_parent';
    end if;
    if exists (
      with recursive ancestrais(id, parent_id) as (
        select c.id, c.parent_id
        from public.conceitos_de_moda c
        where c.id = new.parent_id
        union
        select c.id, c.parent_id
        from public.conceitos_de_moda c
        join ancestrais a on c.id = a.parent_id
      )
      select 1 from ancestrais where id = new.id
    ) then
      raise exception 'concept_hierarchy_cycle';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'approved' and new.status <> 'approved'
     and exists (
       select 1 from public.conceitos_de_moda filho
       where filho.parent_id = old.id and filho.status = 'approved'
     ) then
    raise exception 'approved_concept_has_approved_children';
  end if;
  return new;
end;
$$;

create or replace function public._validar_versao_conceito_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_contrato_mudou boolean;
begin
  if tg_op = 'DELETE' then
    if old.status in ('approved', 'retired') then
      raise exception 'approved_or_retired_concept_cannot_be_deleted';
    end if;
    return old;
  end if;
  if new.versao < old.versao then
    raise exception 'concept_version_cannot_decrease';
  end if;
  if old.status = 'approved'
     and new.status not in ('approved', 'retired') then
    raise exception 'approved_concept_can_only_be_retired';
  end if;
  if old.status = 'retired' and new.status <> 'retired' then
    raise exception 'retired_concept_cannot_be_reactivated';
  end if;

  v_contrato_mudou := row(
    new.familia, new.parent_id, new.rotulo_pt, new.rotulo_en,
    new.definicao, new.aliases_pt, new.aliases_en,
    new.exemplos_positivos, new.exemplos_negativos,
    new.protocolo_promocao_versao, new.volume_observado,
    new.volume_minimo_exigido, new.status, new.versao
  ) is distinct from row(
    old.familia, old.parent_id, old.rotulo_pt, old.rotulo_en,
    old.definicao, old.aliases_pt, old.aliases_en,
    old.exemplos_positivos, old.exemplos_negativos,
    old.protocolo_promocao_versao, old.volume_observado,
    old.volume_minimo_exigido, old.status, old.versao
  );
  if old.status = 'approved' and v_contrato_mudou
     and new.versao <> old.versao + 1 then
    raise exception 'approved_concept_change_requires_next_version';
  end if;
  return new;
end;
$$;

create or replace function public._retirar_leituras_de_conceito_alterado_13()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_motivo text;
begin
  if old.status = 'approved' and row(
       new.familia, new.parent_id, new.rotulo_pt, new.rotulo_en,
       new.definicao, new.aliases_pt, new.aliases_en,
       new.exemplos_positivos, new.exemplos_negativos,
       new.protocolo_promocao_versao, new.volume_observado,
       new.volume_minimo_exigido, new.status, new.versao
     ) is distinct from row(
       old.familia, old.parent_id, old.rotulo_pt, old.rotulo_en,
       old.definicao, old.aliases_pt, old.aliases_en,
       old.exemplos_positivos, old.exemplos_negativos,
       old.protocolo_promocao_versao, old.volume_observado,
       old.volume_minimo_exigido, old.status, old.versao
     ) then
    v_motivo := 'concept_contract_changed:' || new.id;
    with recursive conceitos_afetados(id) as (
      select new.id
      union all
      select c.id
      from public.conceitos_de_moda c
      join conceitos_afetados pai on c.parent_id = pai.id
    )
    update public.leituras_de_mercado l
    set status = 'withdrawn',
        titulo = 'Leitura retirada',
        resumo = 'Conteúdo removido por expiração, revogação ou correção editorial.',
        lacunas = '{}'::text[],
        cobertura = '{}'::jsonb,
        retirada_em = now(),
        retirada_por = 'concept_gate',
        motivo_retirada = v_motivo
    where l.status = 'published'
      and (
        l.conceito_id in (select id from conceitos_afetados)
        or exists (
          select 1
          from public.leitura_evidencias le
          join public.evidencias_de_sinal e on e.id = le.evidencia_id
          where le.leitura_id = l.id
            and e.conceito_id in (select id from conceitos_afetados)
        )
      );

    with recursive conceitos_afetados(id) as (
      select new.id
      union all
      select c.id
      from public.conceitos_de_moda c
      join conceitos_afetados pai on c.parent_id = pai.id
    )
    update public.evidencias_de_sinal e
    set status = 'revoked',
        revogada_em = now(),
        motivo_revogacao = v_motivo
    where e.conceito_id in (select id from conceitos_afetados)
      and e.status <> 'revoked';
  end if;
  return new;
end;
$$;

create or replace function public._validar_mapeamento_legado_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.conceitos_de_moda c
    where c.id = new.conceito_id and c.status = 'approved'
  ) then
    raise exception 'legacy_mapping_requires_approved_concept';
  end if;
  if not exists (
    select 1 from public.termos t
    where t.id = new.termo_id and t.status = 'aprovado'
  ) then
    raise exception 'legacy_mapping_requires_approved_term';
  end if;
  return new;
end;
$$;

create or replace function public._validar_fonte_do_item_13()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_fonte public.fontes_de_sinal%rowtype;
  v_execucao public.execucoes_de_pesquisa%rowtype;
  v_expiracao_maxima timestamptz;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select * into v_fonte
  from public.fontes_de_sinal
  where id = new.fonte_id
  for key share;
  if not found or not v_fonte.ativa or v_fonte.status <> 'green'
     or v_fonte.retencao_fatos_dias < 1
     or v_fonte.autorizacao_expira_em <= current_date then
    raise exception 'source_rights_not_approved';
  end if;
  if v_fonte.termos_revisados_em <= current_date - (
       case when v_fonte.tier = 'T0' then 365 else 90 end) then
    raise exception 'source_terms_review_expired';
  end if;

  select * into v_execucao
  from public.execucoes_de_pesquisa
  where id = new.execucao_id
  for key share;
  if not found
     or v_execucao.tipo not in ('collection', 'backfill')
     or v_execucao.executor not in ('local_deterministic', 'source_api')
     or v_execucao.status not in ('running', 'success')
     or v_execucao.registro_sha256 <> v_fonte.registro_sha256 then
    raise exception 'source_collection_execution_not_approved';
  end if;

  if v_fonte.url_scope = 'internal' then
    if new.url_canonica is not null or new.id_externo is null then
      raise exception 'internal_source_requires_only_stable_external_id';
    end if;
  elsif new.url_canonica is null
     or not public._url_no_escopo_13(
       new.url_canonica, v_fonte.base_host, v_fonte.url_scope) then
    raise exception 'source_item_outside_allowed_origin';
  end if;

  if new.observado_em > clock_timestamp() + interval '10 minutes' then
    raise exception 'source_item_observed_in_future';
  end if;

  new.termos_versao := v_fonte.termos_versao;
  new.fonte_contrato_sha256 := v_fonte.contrato_sha256;
  new.autorizacao_sha256 := v_fonte.autorizacao_sha256;

  v_expiracao_maxima := new.observado_em
    + make_interval(days => v_fonte.retencao_fatos_dias);
  if new.expira_em is null then
    new.expira_em := v_expiracao_maxima;
  elsif new.expira_em > v_expiracao_maxima then
    raise exception 'source_item_retention_exceeded';
  end if;
  return new;
end;
$$;

create or replace function public._proteger_evidencia_13()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_item public.itens_de_fonte%rowtype;
  v_fonte public.fontes_de_sinal%rowtype;
  v_execucao public.execucoes_de_pesquisa%rowtype;
  v_execucao_item public.execucoes_de_pesquisa%rowtype;
  v_conceito public.conceitos_de_moda%rowtype;
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(
      hashtextextended('canario:market-intelligence-13', 0));
    if new.status <> 'draft' then
      raise exception 'evidence_must_start_draft';
    end if;
    select * into v_item from public.itens_de_fonte
    where id = new.item_id for key share;
    if not found or v_item.expira_em <= now() then
      raise exception 'evidence_requires_current_source_item';
    end if;
    select * into v_execucao_item from public.execucoes_de_pesquisa
    where id = v_item.execucao_id for key share;
    if not found or v_execucao_item.status <> 'success' then
      raise exception 'evidence_requires_successful_collection';
    end if;
    select * into v_execucao from public.execucoes_de_pesquisa
    where id = new.execucao_id for key share;
    if not found
       or v_execucao.tipo not in ('extraction', 'research', 'backfill')
       or v_execucao.executor not in ('local_deterministic', 'openai_responses')
       or v_execucao.status not in ('running', 'success') then
      raise exception 'evidence_extraction_execution_not_approved';
    end if;
    select * into v_fonte from public.fontes_de_sinal
    where id = v_item.fonte_id for key share;
    if not found or not v_fonte.ativa or v_fonte.status <> 'green'
       or v_fonte.autorizacao_expira_em <= current_date
       or v_fonte.contrato_sha256 <> v_item.fonte_contrato_sha256
       or v_fonte.autorizacao_sha256 <> v_item.autorizacao_sha256
       or v_fonte.termos_versao <> v_item.termos_versao then
      raise exception 'evidence_source_contract_changed';
    end if;
    if v_execucao.executor = 'openai_responses' and not (
      v_fonte.ai_processing in ('facts', 'full_text')
      and v_fonte.openai_retention_mode = 'standard_30d'
      and v_fonte.retencao_dias >= 30
      and v_execucao.openai_retention_mode = 'standard_30d'
      and v_execucao.service_tier = 'default'
    ) then
      raise exception 'evidence_openai_processing_not_authorized';
    end if;
    select * into v_conceito from public.conceitos_de_moda
    where id = new.conceito_id for key share;
    if not found or v_conceito.status <> 'approved' then
      raise exception 'evidence_requires_approved_concept';
    end if;
    if new.periodo_inicio < v_item.periodo_inicio
       or new.periodo_fim > v_item.periodo_fim
       or new.territorio <> v_item.geo then
      raise exception 'evidence_scope_exceeds_source_item';
    end if;
    new.conceito_versao := v_conceito.versao;
    new.expira_em := v_item.expira_em;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if row(new.item_id, new.execucao_id, new.conceito_id, new.tipo,
           new.direcao, new.valor, new.resumo, new.territorio,
           new.periodo_inicio, new.periodo_fim, new.unidade,
           new.transformacao_versao, new.conceito_versao,
           new.confianca_extracao, new.metodologia_versao,
           new.expira_em, new.criada_em)
       is distinct from
       row(old.item_id, old.execucao_id, old.conceito_id, old.tipo,
           old.direcao, old.valor, old.resumo, old.territorio,
           old.periodo_inicio, old.periodo_fim, old.unidade,
           old.transformacao_versao, old.conceito_versao,
           old.confianca_extracao, old.metodologia_versao,
           old.expira_em, old.criada_em) then
      raise exception 'reviewed_evidence_is_immutable';
    end if;
    if old.status = 'draft' and new.status in ('approved', 'rejected') then
      return new;
    end if;
    if old.status <> 'revoked' and new.status = 'revoked'
       and new.revogada_em is not null and new.motivo_revogacao is not null then
      return new;
    end if;
    raise exception 'reviewed_evidence_is_immutable';
  end if;

  if exists (
    select 1
    from public.leitura_evidencias le
    join public.leituras_de_mercado l on l.id = le.leitura_id
    where le.evidencia_id = old.id
      and l.status = 'published'
  ) then
    raise exception 'published_evidence_cannot_be_deleted';
  end if;
  return old;
end;
$$;

create or replace function public._proteger_item_publicado_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    if new.expira_em > old.expira_em
       or row(new.fonte_id, new.execucao_id, new.id_externo,
              new.url_canonica, new.titulo, new.publicado_em,
              new.observado_em, new.tipo_conteudo, new.familia_origem,
              new.tipo_origem, new.geo, new.idioma, new.periodo_inicio,
              new.periodo_fim, new.unidade_original,
              new.transformacao_versao, new.conteudo_sha256,
              new.termos_versao, new.fonte_contrato_sha256,
              new.autorizacao_sha256, new.metadados, new.criado_em)
          is distinct from
          row(old.fonte_id, old.execucao_id, old.id_externo,
              old.url_canonica, old.titulo, old.publicado_em,
              old.observado_em, old.tipo_conteudo, old.familia_origem,
              old.tipo_origem, old.geo, old.idioma, old.periodo_inicio,
              old.periodo_fim, old.unidade_original,
              old.transformacao_versao, old.conteudo_sha256,
              old.termos_versao, old.fonte_contrato_sha256,
              old.autorizacao_sha256, old.metadados, old.criado_em) then
      raise exception 'source_item_is_immutable';
    end if;
    return new;
  end if;
  if exists (
    select 1 from public.evidencias_de_sinal e where e.item_id = old.id
  ) then
    raise exception 'source_item_with_evidence_cannot_be_deleted';
  end if;
  return old;
end;
$$;

create or replace function public._proteger_execucao_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'queued' then
      raise exception 'execution_must_start_queued';
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'execution_is_append_only';
  end if;
  if old.status in ('success', 'failed', 'cancelled') then
    raise exception 'terminal_execution_is_immutable';
  end if;
  if row(new.tipo, new.executor, new.modelo, new.prompt_version,
         new.openai_project_id, new.openai_retention_mode,
         new.service_tier, new.codigo_sha, new.registro_sha256,
         new.solicitada_em)
     is distinct from
     row(old.tipo, old.executor, old.modelo, old.prompt_version,
         old.openai_project_id, old.openai_retention_mode,
         old.service_tier, old.codigo_sha, old.registro_sha256,
         old.solicitada_em) then
    raise exception 'execution_identity_is_immutable';
  end if;
  if old.status = 'queued' and new.status not in ('running', 'cancelled') then
    raise exception 'invalid_execution_transition';
  end if;
  if old.status = 'running'
     and new.status not in ('running', 'success', 'failed', 'cancelled') then
    raise exception 'invalid_execution_transition';
  end if;
  if new.status = 'success' and new.executor = 'openai_responses'
     and (new.response_id is null
          or new.tokens_entrada + new.tokens_saida = 0) then
    raise exception 'openai_success_requires_auditable_usage';
  end if;
  return new;
end;
$$;

create or replace function public._proteger_leitura_13()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'reading_must_start_draft';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'published_reading_cannot_be_deleted';
    end if;
    return old;
  end if;

  if old.status = 'withdrawn' then
    raise exception 'withdrawn_reading_is_immutable';
  end if;
  if old.status = 'published' then
    if new.status <> 'withdrawn'
       or new.titulo <> 'Leitura retirada'
       or new.resumo <> 'Conteúdo removido por expiração, revogação ou correção editorial.'
       or cardinality(new.lacunas) <> 0
       or new.cobertura <> '{}'::jsonb
       or row(new.chave, new.execucao_id, new.conceito_id, new.semana,
              new.locale, new.territorio, new.estagio,
              new.metodologia_versao,
              new.publicada_em, new.publicada_por)
          is distinct from
          row(old.chave, old.execucao_id, old.conceito_id, old.semana,
              old.locale, old.territorio, old.estagio,
              old.metodologia_versao,
              old.publicada_em, old.publicada_por) then
      raise exception 'published_reading_is_immutable';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public._proteger_vinculo_de_leitura_13()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_leitura_id bigint;
  v_status text;
  v_conceito_da_leitura text;
  v_conceito_da_evidencia text;
  v_status_da_evidencia text;
  v_expiracao_da_evidencia timestamptz;
begin
  v_leitura_id := case when tg_op = 'DELETE' then old.leitura_id else new.leitura_id end;
  select status, conceito_id into v_status, v_conceito_da_leitura
  from public.leituras_de_mercado
  where id = v_leitura_id
  for update;
  if not found then raise exception 'reading_not_found'; end if;

  -- A poda pode remover a trilha privada somente depois de a leitura ter
  -- virado um tombstone e a evidência ter sido revogada ou expirado. O caso
  -- normal de edição continua restrito ao draft.
  if tg_op = 'DELETE' and v_status = 'withdrawn' then
    select status, expira_em
      into v_status_da_evidencia, v_expiracao_da_evidencia
    from public.evidencias_de_sinal
    where id = old.evidencia_id;
    if not found or (
      v_status_da_evidencia in ('rejected', 'revoked')
      or v_expiracao_da_evidencia <= now()
    ) then
      return old;
    end if;
  end if;
  if v_status is distinct from 'draft' then
    raise exception 'reading_evidence_links_are_immutable_after_publication';
  end if;
  if tg_op <> 'DELETE' and new.papel in ('supports', 'contradicts')
     and v_conceito_da_leitura is not null then
    select conceito_id into v_conceito_da_evidencia
    from public.evidencias_de_sinal
    where id = new.evidencia_id
    for key share;
    if not found then raise exception 'evidence_not_found'; end if;
    if v_conceito_da_evidencia is distinct from v_conceito_da_leitura then
      raise exception 'reading_evidence_concept_mismatch';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger conceitos_atualizado_em_13
before update on public.conceitos_de_moda
for each row execute function public._marcar_atualizado_em_13();
create trigger conceitos_serializam_mudanca_13
before update or delete on public.conceitos_de_moda
for each statement execute function public._serializar_escritas_criticas_13();
create trigger conceitos_hierarquia_13
before insert or update of parent_id, familia, status on public.conceitos_de_moda
for each row execute function public._validar_hierarquia_conceito_13();
create trigger conceitos_versao_13
before update or delete on public.conceitos_de_moda
for each row execute function public._validar_versao_conceito_13();
create trigger conceitos_mudanca_retira_leituras_13
after update of familia, parent_id, rotulo_pt, rotulo_en, definicao,
                aliases_pt, aliases_en, exemplos_positivos,
                exemplos_negativos, protocolo_promocao_versao,
                volume_observado, volume_minimo_exigido, status, versao
on public.conceitos_de_moda
for each row execute function public._retirar_leituras_de_conceito_alterado_13();

create trigger mapeamentos_legado_validos_13
before insert or update on public.mapeamentos_de_conceito_legado
for each row execute function public._validar_mapeamento_legado_13();

create trigger fontes_atualizado_em_13
before update on public.fontes_de_sinal
for each row execute function public._marcar_atualizado_em_13();
create trigger fontes_serializam_mudanca_13
before update on public.fontes_de_sinal
for each statement execute function public._serializar_escritas_criticas_13();

create trigger execucoes_serializam_mudanca_13
before update or delete on public.execucoes_de_pesquisa
for each statement execute function public._serializar_escritas_criticas_13();
create trigger execucoes_append_only_13
before insert or update or delete on public.execucoes_de_pesquisa
for each row execute function public._proteger_execucao_13();

create trigger itens_fonte_direitos_13
before insert or update of fonte_id, url_canonica, termos_versao,
                           observado_em
on public.itens_de_fonte
for each row execute function public._validar_fonte_do_item_13();
create trigger itens_fonte_publicados_protegidos_13
before update or delete on public.itens_de_fonte
for each row execute function public._proteger_item_publicado_13();

create trigger evidencias_atualizado_em_13
before update on public.evidencias_de_sinal
for each row execute function public._marcar_atualizado_em_13();
create trigger evidencias_protegidas_13
before insert or update or delete on public.evidencias_de_sinal
for each row execute function public._proteger_evidencia_13();

create trigger leituras_atualizado_em_13
before update on public.leituras_de_mercado
for each row execute function public._marcar_atualizado_em_13();
create trigger leituras_serializam_mudanca_13
before update or delete on public.leituras_de_mercado
for each statement execute function public._serializar_escritas_criticas_13();
create trigger leituras_protegidas_13
before insert or update or delete on public.leituras_de_mercado
for each row execute function public._proteger_leitura_13();
create trigger leitura_evidencias_serializam_mudanca_13
before insert or update or delete on public.leitura_evidencias
for each statement execute function public._serializar_escritas_criticas_13();
create trigger leitura_evidencias_protegidas_13
before insert or update or delete on public.leitura_evidencias
for each row execute function public._proteger_vinculo_de_leitura_13();

-- -------------------------------------------------------------------------
-- 9. Transições explícitas de revisão, publicação, retirada e retenção
-- -------------------------------------------------------------------------

create or replace function public.revisar_conceito_de_moda(
  p_conceito_id text,
  p_decisao text,
  p_revisada_por text,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_conceito public.conceitos_de_moda%rowtype;
begin
  if p_decisao is null or p_decisao not in ('approved', 'rejected') then
    raise exception 'invalid_concept_decision';
  end if;
  if p_revisada_por is null
     or length(btrim(p_revisada_por)) not between 1 and 160 then
    raise exception 'concept_reviewer_required';
  end if;
  if p_decisao = 'rejected'
     and (p_motivo is null
          or length(btrim(p_motivo)) not between 1 and 1000) then
    raise exception 'concept_rejection_reason_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select * into v_conceito
  from public.conceitos_de_moda
  where id = p_conceito_id
  for update;
  if not found then raise exception 'concept_not_found'; end if;
  if v_conceito.status <> 'proposed' then
    raise exception 'concept_already_reviewed';
  end if;
  if p_decisao = 'approved' and not (
    cardinality(v_conceito.aliases_pt)
      + cardinality(v_conceito.aliases_en) > 0
    and cardinality(v_conceito.exemplos_positivos) > 0
    and cardinality(v_conceito.exemplos_negativos) > 0
    and v_conceito.protocolo_promocao_versao is not null
    and v_conceito.volume_observado >= v_conceito.volume_minimo_exigido
  ) then
    raise exception 'concept_promotion_evidence_incomplete';
  end if;

  update public.conceitos_de_moda
  set status = p_decisao,
      revisada_em = now(),
      revisada_por = btrim(p_revisada_por),
      motivo_rejeicao = case
        when p_decisao = 'rejected' then btrim(p_motivo)
      end
  where id = p_conceito_id;

  return jsonb_build_object(
    'conceito_id', p_conceito_id,
    'status', p_decisao,
    'versao', v_conceito.versao
  );
end;
$$;

create or replace function public.retirar_conceito_de_moda(
  p_conceito_id text,
  p_retirada_por text,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_versao integer;
begin
  if p_retirada_por is null
     or length(btrim(p_retirada_por)) not between 1 and 160
     or p_motivo is null
     or length(btrim(p_motivo)) not between 1 and 1000 then
    raise exception 'concept_retirement_fields_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select versao into v_versao
  from public.conceitos_de_moda
  where id = p_conceito_id and status = 'approved'
  for update;
  if not found then raise exception 'approved_concept_not_found'; end if;

  update public.conceitos_de_moda
  set status = 'retired',
      versao = v_versao + 1,
      retirada_em = now(),
      retirada_por = btrim(p_retirada_por),
      motivo_retirada = btrim(p_motivo)
  where id = p_conceito_id;

  return jsonb_build_object(
    'conceito_id', p_conceito_id,
    'status', 'retired',
    'versao', v_versao + 1
  );
end;
$$;

create or replace function public.revisar_evidencia_de_sinal(
  p_evidencia_id bigint,
  p_decisao text,
  p_revisada_por text,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_evidencia public.evidencias_de_sinal%rowtype;
begin
  if p_decisao not in ('approved', 'rejected') then
    raise exception 'invalid_evidence_decision';
  end if;
  if p_revisada_por is null
     or length(btrim(p_revisada_por)) not between 1 and 160 then
    raise exception 'evidence_reviewer_required';
  end if;
  if p_decisao = 'rejected'
     and (p_motivo is null or length(btrim(p_motivo)) not between 1 and 1000) then
    raise exception 'evidence_rejection_reason_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select * into v_evidencia
  from public.evidencias_de_sinal
  where id = p_evidencia_id
  for update;
  if not found then raise exception 'evidence_not_found'; end if;
  if v_evidencia.status <> 'draft' then
    raise exception 'evidence_already_reviewed';
  end if;
  if p_decisao = 'approved' and not exists (
    select 1
    from public.evidencias_de_sinal e
    join public.execucoes_de_pesquisa ex on ex.id = e.execucao_id
    join public.itens_de_fonte i on i.id = e.item_id
    join public.execucoes_de_pesquisa ix on ix.id = i.execucao_id
    join public.fontes_de_sinal f on f.id = i.fonte_id
    join public.conceitos_de_moda c on c.id = e.conceito_id
    where e.id = p_evidencia_id
      and e.expira_em > now() and i.expira_em > now()
      and ex.status = 'success' and ix.status = 'success'
      and f.ativa and f.status = 'green'
      and f.autorizacao_expira_em > current_date
      and f.retencao_fatos_dias > 0
      and f.termos_revisados_em > current_date - case
        when f.tier = 'T0' then 365 else 90 end
      and i.termos_versao = f.termos_versao
      and i.fonte_contrato_sha256 = f.contrato_sha256
      and i.autorizacao_sha256 = f.autorizacao_sha256
      and c.status = 'approved' and c.versao = e.conceito_versao
      and (
        ex.executor = 'local_deterministic'
        or (
          ex.executor = 'openai_responses'
          and f.ai_processing in ('facts', 'full_text')
          and f.openai_retention_mode = 'standard_30d'
          and f.retencao_dias >= 30
          and ex.openai_retention_mode = 'standard_30d'
          and ex.service_tier = 'default'
        )
      )
      and (
        (f.url_scope = 'internal' and i.url_canonica is null)
        or public._url_no_escopo_13(
          i.url_canonica, f.base_host, f.url_scope)
      )
  ) then
    raise exception 'evidence_source_rights_not_approved';
  end if;

  update public.evidencias_de_sinal
  set status = p_decisao,
      revisada_em = now(),
      revisada_por = btrim(p_revisada_por),
      motivo_rejeicao = case when p_decisao = 'rejected' then btrim(p_motivo) end
  where id = p_evidencia_id;

  return jsonb_build_object(
    'evidencia_id', p_evidencia_id,
    'status', p_decisao
  );
end;
$$;

create or replace function public.publicar_leitura_de_mercado(
  p_leitura_id bigint,
  p_publicada_por text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_leitura public.leituras_de_mercado%rowtype;
  v_execucao_leitura public.execucoes_de_pesquisa%rowtype;
  v_total integer;
  v_itens integer;
  v_fontes integer;
  v_familias integer;
  v_suportes integer;
  v_fontes_suporte integer;
  v_familias_suporte integer;
  v_invalidas integer;
  v_min_familias integer;
begin
  if p_publicada_por is null
     or length(btrim(p_publicada_por)) not between 1 and 160 then
    raise exception 'reading_publisher_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select * into v_leitura
  from public.leituras_de_mercado
  where id = p_leitura_id
  for update;
  if not found then raise exception 'reading_not_found'; end if;
  if v_leitura.status <> 'draft' then
    raise exception 'reading_is_not_draft';
  end if;
  if v_leitura.cobertura <> '{}'::jsonb then
    raise exception 'reading_coverage_is_system_generated';
  end if;
  select * into v_execucao_leitura
  from public.execucoes_de_pesquisa
  where id = v_leitura.execucao_id
  for key share;
  if not found or v_execucao_leitura.status <> 'success'
     or v_execucao_leitura.tipo <> 'brief_generation'
     or v_execucao_leitura.executor not in (
       'human_review', 'local_deterministic', 'openai_responses') then
    raise exception 'reading_execution_not_successful';
  end if;
  if v_leitura.conceito_id is not null and not exists (
    select 1 from public.conceitos_de_moda c
    where c.id = v_leitura.conceito_id and c.status = 'approved'
  ) then
    raise exception 'reading_concept_not_approved';
  end if;
  if v_leitura.estagio = 'insufficient'
     and cardinality(v_leitura.lacunas) = 0 then
    raise exception 'insufficient_reading_requires_explicit_gap';
  end if;

  -- A constituição proíbe transformar a leitura em previsão de venda/sucesso.
  if lower(v_leitura.titulo || ' ' || v_leitura.resumo || ' '
           || array_to_string(v_leitura.lacunas, ' ')) ~
     '(chance de sucesso|probabilidade de venda|vai vender|vender[aá] bem|recomendamos produzir|deve produzir|sales probability|will sell|recommend(ed)? (production|volume|units))' then
    raise exception 'predictive_language_not_allowed';
  end if;

  -- O trigger de vínculos usa o mesmo lock do pai. Uma alteração concorrente
  -- espera este snapshot e, ao acordar, encontra a leitura publicada.
  perform le.leitura_id
  from public.leitura_evidencias le
  join public.evidencias_de_sinal e on e.id = le.evidencia_id
  join public.itens_de_fonte i on i.id = e.item_id
  join public.fontes_de_sinal f on f.id = i.fonte_id
  join public.conceitos_de_moda c on c.id = e.conceito_id
  join public.execucoes_de_pesquisa ex on ex.id = e.execucao_id
  join public.execucoes_de_pesquisa ix on ix.id = i.execucao_id
  where le.leitura_id = p_leitura_id
  order by f.id, i.id, e.id
  for update of le, e, i, f, c, ex, ix;

  select
    count(*)::integer,
    count(distinct e.item_id)::integer,
    count(distinct f.id)::integer,
    count(distinct i.familia_origem)::integer,
    count(*) filter (where le.papel = 'supports')::integer,
    count(distinct f.id)
      filter (where le.papel = 'supports')::integer,
    count(distinct i.familia_origem)
      filter (where le.papel = 'supports')::integer,
    count(*) filter (where
      e.status <> 'approved'
      or e.expira_em <= now()
      or c.status <> 'approved'
      or c.versao <> e.conceito_versao
      or not f.ativa
      or f.status <> 'green'
      or f.autorizacao_expira_em <= current_date
      or not (
        ex.executor = 'local_deterministic'
        or (
          ex.executor = 'openai_responses'
          and f.ai_processing in ('facts', 'full_text')
          and f.openai_retention_mode = 'standard_30d'
          and f.retencao_dias >= 30
          and ex.openai_retention_mode = 'standard_30d'
          and ex.service_tier = 'default'
        )
      )
      or (
        v_execucao_leitura.executor = 'openai_responses'
        and (
          f.ai_processing not in ('facts', 'full_text')
          or f.openai_retention_mode <> 'standard_30d'
          or f.retencao_dias < 30
        )
      )
      or f.display_rights in ('none', 'link_only')
      or f.retencao_fatos_dias = 0
      or f.termos_revisados_em <= current_date - case
        when f.tier = 'T0' then 365 else 90 end
      or ex.status <> 'success'
      or ex.tipo not in ('extraction', 'research', 'backfill')
      or ex.executor not in ('local_deterministic', 'openai_responses')
      or ix.status <> 'success'
      or ix.tipo not in ('collection', 'backfill')
      or ix.executor not in ('local_deterministic', 'source_api')
      or i.expira_em <= now()
      or i.termos_versao <> f.termos_versao
      or i.fonte_contrato_sha256 <> f.contrato_sha256
      or i.autorizacao_sha256 <> f.autorizacao_sha256
      or not (
        (f.url_scope = 'internal' and i.url_canonica is null)
        or public._url_no_escopo_13(
          i.url_canonica, f.base_host, f.url_scope)
      )
      or (
        le.papel in ('supports', 'contradicts')
        and v_leitura.conceito_id is not null
        and e.conceito_id is distinct from v_leitura.conceito_id
      )
    )::integer
  into v_total, v_itens, v_fontes, v_familias, v_suportes,
       v_fontes_suporte, v_familias_suporte, v_invalidas
  from public.leitura_evidencias le
  join public.evidencias_de_sinal e on e.id = le.evidencia_id
  join public.itens_de_fonte i on i.id = e.item_id
  join public.fontes_de_sinal f on f.id = i.fonte_id
  join public.conceitos_de_moda c on c.id = e.conceito_id
  join public.execucoes_de_pesquisa ex on ex.id = e.execucao_id
  join public.execucoes_de_pesquisa ix on ix.id = i.execucao_id
  where le.leitura_id = p_leitura_id;

  if v_total = 0 then raise exception 'reading_without_evidence'; end if;
  if v_invalidas > 0 then
    raise exception 'reading_has_unapproved_or_expired_evidence';
  end if;

  -- `insufficient` é uma conclusão honesta de cobertura e pode documentar uma
  -- única família; qualquer outro estágio exige confirmação independente.
  v_min_familias := case when v_leitura.estagio = 'insufficient' then 1 else 2 end;
  if v_suportes < v_min_familias
     or v_fontes_suporte < v_min_familias
     or v_familias_suporte < v_min_familias then
    raise exception 'reading_requires_independent_supporting_sources';
  end if;

  update public.leituras_de_mercado
  set status = 'published',
      publicada_em = now(),
      publicada_por = btrim(p_publicada_por),
      cobertura = jsonb_build_object(
        'n_evidencias', v_total,
        'n_itens', v_itens,
        'n_fontes', v_fontes,
        'n_familias_de_origem', v_familias,
        'n_evidencias_de_suporte', v_suportes,
        'n_fontes_de_suporte', v_fontes_suporte,
        'n_familias_de_suporte', v_familias_suporte
      )
  where id = p_leitura_id;

  return jsonb_build_object(
    'leitura_id', p_leitura_id,
    'status', 'published',
    'n_evidencias', v_total,
    'n_fontes', v_fontes
  );
end;
$$;

create or replace function public.retirar_leitura_de_mercado(
  p_leitura_id bigint,
  p_retirada_por text,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if p_retirada_por is null
     or length(btrim(p_retirada_por)) not between 1 and 160
     or p_motivo is null
     or length(btrim(p_motivo)) not between 1 and 1000 then
    raise exception 'reading_withdrawal_fields_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  update public.leituras_de_mercado
  set status = 'withdrawn',
      titulo = 'Leitura retirada',
      resumo = 'Conteúdo removido por expiração, revogação ou correção editorial.',
      lacunas = '{}'::text[],
      cobertura = '{}'::jsonb,
      retirada_em = now(),
      retirada_por = btrim(p_retirada_por),
      motivo_retirada = btrim(p_motivo)
  where id = p_leitura_id and status = 'published';

  if not found then raise exception 'published_reading_not_found'; end if;
  return jsonb_build_object('leitura_id', p_leitura_id, 'status', 'withdrawn');
end;
$$;

create or replace function public._retirar_leituras_de_fonte_revogada_13()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_motivo text;
begin
  if row(new.nome, new.sensor, new.ativa, new.status, new.ai_processing,
         new.openai_retention_mode, new.display_rights,
         new.retencao_dias, new.retencao_fatos_dias,
         new.tier, new.metodo, new.base_url, new.base_host, new.url_scope,
         new.termos_url, new.termos_versao, new.termos_revisados_em,
         new.autorizacao_sha256, new.aprovada_por, new.aprovada_em,
         new.autorizacao_expira_em, new.contrato_sha256, new.observacao)
     is distinct from
     row(old.nome, old.sensor, old.ativa, old.status, old.ai_processing,
         old.openai_retention_mode, old.display_rights,
         old.retencao_dias, old.retencao_fatos_dias,
         old.tier, old.metodo, old.base_url, old.base_host, old.url_scope,
         old.termos_url, old.termos_versao, old.termos_revisados_em,
         old.autorizacao_sha256, old.aprovada_por, old.aprovada_em,
         old.autorizacao_expira_em, old.contrato_sha256, old.observacao) then
    perform pg_advisory_xact_lock(
      hashtextextended('canario:market-intelligence-13', 0));
    v_motivo := 'source_rights_contract_changed:' || new.id;

    -- A leitura pública perde todo o texto editorial antes que a cadeia
    -- privada seja revogada. O tombstone preserva apenas identidade/auditoria.
    update public.leituras_de_mercado l
    set status = 'withdrawn',
        titulo = 'Leitura retirada',
        resumo = 'Conteúdo removido por expiração, revogação ou correção editorial.',
        lacunas = '{}'::text[],
        cobertura = '{}'::jsonb,
        retirada_em = now(),
        retirada_por = 'rights_gate',
        motivo_retirada = v_motivo
    where l.status = 'published'
      and exists (
        select 1
        from public.leitura_evidencias le
        join public.evidencias_de_sinal e on e.id = le.evidencia_id
        join public.itens_de_fonte i on i.id = e.item_id
        where le.leitura_id = l.id and i.fonte_id = new.id
      );

    update public.evidencias_de_sinal e
    set status = 'revoked',
        revogada_em = now(),
        motivo_revogacao = v_motivo
    where e.status <> 'revoked'
      and exists (
        select 1
        from public.itens_de_fonte i
        where i.id = e.item_id and i.fonte_id = new.id
      );

    -- Nunca prolonga retenção. Um segundo depois da observação mantém o CHECK
    -- verdadeiro mesmo numa revogação imediata; `now()` acelera itens antigos.
    update public.itens_de_fonte i
    set expira_em = least(
      i.expira_em,
      greatest(i.observado_em + interval '1 second', clock_timestamp())
    )
    where i.fonte_id = new.id
      and i.expira_em > greatest(
        i.observado_em + interval '1 second', clock_timestamp());
  end if;
  return new;
end;
$$;

create trigger fontes_revogacao_retira_leituras_13
after update of nome, sensor, ativa, status, ai_processing, openai_retention_mode,
                display_rights, retencao_dias, retencao_fatos_dias,
                tier, metodo, base_url, base_host, url_scope,
                termos_url, termos_versao, termos_revisados_em,
                autorizacao_sha256, aprovada_por, aprovada_em,
                autorizacao_expira_em, contrato_sha256, observacao
on public.fontes_de_sinal
for each row execute function public._retirar_leituras_de_fonte_revogada_13();

create or replace function public.podar_itens_de_fonte_13(
  p_limite integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_item_ids bigint[];
  v_removidos integer;
begin
  if p_limite is null or p_limite < 1 or p_limite > 10000 then
    raise exception 'invalid_source_item_prune_limit';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('canario:market-intelligence-13', 0));

  select coalesce(array_agg(c.id order by c.id), '{}'::bigint[])
  into v_item_ids
  from (
    select i.id, i.expira_em
    from public.itens_de_fonte i
    join public.fontes_de_sinal f on f.id = i.fonte_id
    where i.expira_em <= now()
       or not f.ativa
       or f.status <> 'green'
       or f.autorizacao_expira_em <= current_date
       or f.retencao_fatos_dias < 1
       or f.termos_revisados_em <= current_date - case
         when f.tier = 'T0' then 365 else 90 end
       or i.termos_versao <> f.termos_versao
       or i.fonte_contrato_sha256 <> f.contrato_sha256
       or i.autorizacao_sha256 <> f.autorizacao_sha256
       or not (
         (f.url_scope = 'internal'
          and i.url_canonica is null and i.id_externo is not null)
         or public._url_no_escopo_13(
           i.url_canonica, f.base_host, f.url_scope)
      )
    order by i.expira_em, i.id
    limit p_limite
    for update of i skip locked
  ) c;

  if cardinality(v_item_ids) = 0 then return 0; end if;

  update public.leituras_de_mercado l
  set status = 'withdrawn',
      titulo = 'Leitura retirada',
      resumo = 'Conteúdo removido por expiração, revogação ou correção editorial.',
      lacunas = '{}'::text[],
      cobertura = '{}'::jsonb,
      retirada_em = now(),
      retirada_por = 'retention_gate',
      motivo_retirada = 'source_item_expired_or_rights_revoked'
  where l.status = 'published'
    and exists (
      select 1
      from public.leitura_evidencias le
      join public.evidencias_de_sinal e on e.id = le.evidencia_id
      where le.leitura_id = l.id and e.item_id = any(v_item_ids)
    );

  update public.evidencias_de_sinal e
  set status = 'revoked',
      revogada_em = now(),
      motivo_revogacao = 'source_item_expired_or_rights_revoked'
  where e.item_id = any(v_item_ids) and e.status <> 'revoked';

  -- ON DELETE CASCADE remove os vínculos somente após o tombstone/revogação;
  -- os triggers continuam bloqueando a mesma operação em leitura publicada.
  delete from public.evidencias_de_sinal e
  where e.item_id = any(v_item_ids);

  delete from public.itens_de_fonte i
  where i.id = any(v_item_ids);
  get diagnostics v_removidos = row_count;

  return v_removidos;
end;
$$;

-- Predicados SECURITY DEFINER estreitos permitem que as policies consultem
-- tabelas internas sem conceder suas colunas. Ambos só respondem sobre linhas
-- que continuam publicáveis; ids privados e drafts devolvem apenas `false`.
create or replace function public._leitura_publicavel_13(
  p_leitura_id bigint
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.leituras_de_mercado l
    join public.execucoes_de_pesquisa lx on lx.id = l.execucao_id
    where l.id = p_leitura_id
      and l.status = 'published'
      and lx.status = 'success'
      and lx.tipo = 'brief_generation'
      and lx.executor in (
        'human_review', 'local_deterministic', 'openai_responses')
      and (
        l.conceito_id is null
        or exists (
          select 1 from public.conceitos_de_moda lc
          where lc.id = l.conceito_id and lc.status = 'approved'
        )
      )
      and not exists (
        select 1
        from public.leitura_evidencias le
        join public.evidencias_de_sinal e on e.id = le.evidencia_id
        join public.execucoes_de_pesquisa ex on ex.id = e.execucao_id
        join public.conceitos_de_moda c on c.id = e.conceito_id
        join public.itens_de_fonte i on i.id = e.item_id
        join public.execucoes_de_pesquisa ix on ix.id = i.execucao_id
        join public.fontes_de_sinal f on f.id = i.fonte_id
        where le.leitura_id = l.id
          and (
            e.status <> 'approved'
            or e.expira_em <= now()
            or ex.status <> 'success'
            or ex.tipo not in ('extraction', 'research', 'backfill')
            or ex.executor not in ('local_deterministic', 'openai_responses')
            or ix.status <> 'success'
            or ix.tipo not in ('collection', 'backfill')
            or ix.executor not in ('local_deterministic', 'source_api')
            or c.status <> 'approved'
            or c.versao <> e.conceito_versao
            or i.expira_em <= now()
            or i.termos_versao <> f.termos_versao
            or i.fonte_contrato_sha256 <> f.contrato_sha256
            or i.autorizacao_sha256 <> f.autorizacao_sha256
            or not f.ativa
            or f.status <> 'green'
            or f.autorizacao_expira_em <= current_date
            or f.display_rights in ('none', 'link_only')
            or f.retencao_fatos_dias < 1
            or f.termos_revisados_em <= current_date - case
              when f.tier = 'T0' then 365 else 90 end
            or not (
              (f.url_scope = 'internal'
               and i.url_canonica is null and i.id_externo is not null)
              or public._url_no_escopo_13(
                i.url_canonica, f.base_host, f.url_scope)
            )
            or (
              ex.executor = 'openai_responses'
              and not (
                f.ai_processing in ('facts', 'full_text')
                and f.openai_retention_mode = 'standard_30d'
                and f.retencao_dias >= 30
                and ex.openai_retention_mode = 'standard_30d'
                and ex.service_tier = 'default'
              )
            )
            or (
              lx.executor = 'openai_responses'
              and not (
                f.ai_processing in ('facts', 'full_text')
                and f.openai_retention_mode = 'standard_30d'
                and f.retencao_dias >= 30
                and lx.openai_retention_mode = 'standard_30d'
                and lx.service_tier = 'default'
              )
            )
            or (
              le.papel in ('supports', 'contradicts')
              and l.conceito_id is not null
              and e.conceito_id is distinct from l.conceito_id
            )
          )
      )
      and (
        select count(*)
        from public.leitura_evidencias le
        where le.leitura_id = l.id and le.papel = 'supports'
      ) >= case when l.estagio = 'insufficient' then 1 else 2 end
      and (
        select count(distinct i.fonte_id)
        from public.leitura_evidencias le
        join public.evidencias_de_sinal e on e.id = le.evidencia_id
        join public.itens_de_fonte i on i.id = e.item_id
        where le.leitura_id = l.id and le.papel = 'supports'
      ) >= case when l.estagio = 'insufficient' then 1 else 2 end
      and (
        select count(distinct i.familia_origem)
        from public.leitura_evidencias le
        join public.evidencias_de_sinal e on e.id = le.evidencia_id
        join public.itens_de_fonte i on i.id = e.item_id
        where le.leitura_id = l.id and le.papel = 'supports'
      ) >= case when l.estagio = 'insufficient' then 1 else 2 end
  );
$$;

create or replace function public._conceito_publicavel_13(
  p_conceito_id text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with recursive arvore(id, parent_id) as (
    select distinct c.id, c.parent_id
    from public.conceitos_de_moda c
    join public.evidencias_de_sinal e on e.conceito_id = c.id
    join public.leitura_evidencias le on le.evidencia_id = e.id
    where c.status = 'approved'
      and e.status = 'approved'
      and public._leitura_publicavel_13(le.leitura_id)
    union
    select pai.id, pai.parent_id
    from public.conceitos_de_moda pai
    join arvore filho on filho.parent_id = pai.id
    where pai.status = 'approved'
  )
  select exists (select 1 from arvore where id = p_conceito_id);
$$;

-- -------------------------------------------------------------------------
-- 10. RLS: objetos internos privados; público só enxerga a árvore publicada
-- -------------------------------------------------------------------------

alter table public.conceitos_de_moda enable row level security;
alter table public.conceitos_de_moda force row level security;
alter table public.mapeamentos_de_conceito_legado enable row level security;
alter table public.mapeamentos_de_conceito_legado force row level security;
alter table public.fontes_de_sinal enable row level security;
alter table public.fontes_de_sinal force row level security;
alter table public.execucoes_de_pesquisa enable row level security;
alter table public.execucoes_de_pesquisa force row level security;
alter table public.itens_de_fonte enable row level security;
alter table public.itens_de_fonte force row level security;
alter table public.evidencias_de_sinal enable row level security;
alter table public.evidencias_de_sinal force row level security;
alter table public.leituras_de_mercado enable row level security;
alter table public.leituras_de_mercado force row level security;
alter table public.leitura_evidencias enable row level security;
alter table public.leitura_evidencias force row level security;

revoke all on table public.conceitos_de_moda
  from public, anon, authenticated, service_role;
revoke all on table public.mapeamentos_de_conceito_legado
  from public, anon, authenticated, service_role;
revoke all on table public.fontes_de_sinal
  from public, anon, authenticated, service_role;
revoke all on table public.execucoes_de_pesquisa
  from public, anon, authenticated, service_role;
revoke all on table public.itens_de_fonte
  from public, anon, authenticated, service_role;
revoke all on table public.evidencias_de_sinal
  from public, anon, authenticated, service_role;
revoke all on table public.leituras_de_mercado
  from public, anon, authenticated, service_role;
revoke all on table public.leitura_evidencias
  from public, anon, authenticated, service_role;

grant select, delete on table public.conceitos_de_moda to service_role;
grant insert (
  id, familia, parent_id, rotulo_pt, rotulo_en, definicao,
  aliases_pt, aliases_en, exemplos_positivos, exemplos_negativos,
  protocolo_promocao_versao, volume_observado, volume_minimo_exigido
) on table public.conceitos_de_moda to service_role;
grant update (
  familia, parent_id, rotulo_pt, rotulo_en, definicao,
  aliases_pt, aliases_en, exemplos_positivos, exemplos_negativos,
  protocolo_promocao_versao, volume_observado, volume_minimo_exigido
) on table public.conceitos_de_moda to service_role;
grant select, insert, update, delete on table public.mapeamentos_de_conceito_legado
  to service_role;
-- O CSV versionado é a única rota de alteração de fontes; novas versões
-- chegam por migração revisada, nunca por DML operacional do service_role.
grant select on table public.fontes_de_sinal to service_role;
grant select, insert, update on table public.execucoes_de_pesquisa
  to service_role;
grant select on table public.itens_de_fonte to service_role;
grant insert (
  fonte_id, execucao_id, id_externo, url_canonica, titulo, publicado_em,
  observado_em, tipo_conteudo, familia_origem, tipo_origem, geo, idioma,
  periodo_inicio, periodo_fim, unidade_original, transformacao_versao,
  conteudo_sha256, metadados
) on table public.itens_de_fonte to service_role;

grant select on table public.evidencias_de_sinal to service_role;
grant insert (
  item_id, execucao_id, conceito_id, tipo, direcao, valor, resumo,
  territorio, periodo_inicio, periodo_fim, unidade, transformacao_versao,
  confianca_extracao, metodologia_versao
) on table public.evidencias_de_sinal to service_role;

grant select, delete on table public.leituras_de_mercado to service_role;
grant insert (
  chave, execucao_id, conceito_id, semana, locale, territorio,
  titulo, resumo, estagio, metodologia_versao, lacunas
) on table public.leituras_de_mercado to service_role;
grant update (
  chave, execucao_id, conceito_id, semana, locale, territorio,
  titulo, resumo, estagio, metodologia_versao, lacunas
) on table public.leituras_de_mercado to service_role;
grant select, insert, delete on table public.leitura_evidencias to service_role;

grant usage, select on sequence public.execucoes_de_pesquisa_id_seq to service_role;
grant usage, select on sequence public.itens_de_fonte_id_seq to service_role;
grant usage, select on sequence public.evidencias_de_sinal_id_seq to service_role;
grant usage, select on sequence public.leituras_de_mercado_id_seq to service_role;

create policy conceitos_so_quando_publicados_13
on public.conceitos_de_moda for select to anon, authenticated
using (
  status = 'approved'
  and public._conceito_publicavel_13(conceitos_de_moda.id)
);

create policy mapeamentos_so_quando_publicados_13
on public.mapeamentos_de_conceito_legado for select to anon, authenticated
using (
  public._conceito_publicavel_13(
    mapeamentos_de_conceito_legado.conceito_id
  )
  and exists (
    select 1 from public.termos t
    where t.id = mapeamentos_de_conceito_legado.termo_id
      and t.status = 'aprovado'
  )
);

create policy fontes_so_quando_publicadas_13
on public.fontes_de_sinal for select to anon, authenticated
using (
  ativa and status = 'green' and exists (
    select 1
    from public.itens_de_fonte i
    join public.evidencias_de_sinal e on e.item_id = i.id
    join public.leitura_evidencias le on le.evidencia_id = e.id
    where i.fonte_id = fontes_de_sinal.id
      and e.status = 'approved'
      and public._leitura_publicavel_13(le.leitura_id)
  )
);

create policy itens_so_quando_publicados_13
on public.itens_de_fonte for select to anon, authenticated
using (
  exists (
    select 1
    from public.evidencias_de_sinal e
    join public.leitura_evidencias le on le.evidencia_id = e.id
    where e.item_id = itens_de_fonte.id
      and e.status = 'approved'
      and public._leitura_publicavel_13(le.leitura_id)
  )
);

create policy evidencias_so_quando_publicadas_13
on public.evidencias_de_sinal for select to anon, authenticated
using (
  status = 'approved' and exists (
    select 1
    from public.leitura_evidencias le
    where le.evidencia_id = evidencias_de_sinal.id
      and public._leitura_publicavel_13(le.leitura_id)
  )
);

create policy leituras_publicadas_13
on public.leituras_de_mercado for select to anon, authenticated
using (public._leitura_publicavel_13(leituras_de_mercado.id));

create policy vinculos_de_leituras_publicadas_13
on public.leitura_evidencias for select to anon, authenticated
using (
  public._leitura_publicavel_13(leitura_evidencias.leitura_id)
);

-- As tabelas internas não recebem nem mesmo SELECT por coluna para clientes.
-- Isso é necessário porque uma concessão direta permitiria contornar o
-- mascaramento `link_only` da view. A API pública atravessa somente as duas RPCs
-- SECURITY DEFINER estreitas declaradas abaixo; RLS permanece como defesa em
-- profundidade caso uma concessão futura seja adicionada por engano.

-- Views enxutas para o futuro cliente; `security_invoker` mantém as policies
-- acima como a fronteira real, em vez de usar os direitos do dono da view.
create view public.conceitos_de_moda_publicados
with (security_invoker = true) as
select id, familia, parent_id, rotulo_pt, rotulo_en, definicao, versao
from public.conceitos_de_moda c
where public._conceito_publicavel_13(c.id);

create view public.mapeamentos_de_conceito_publicados
with (security_invoker = true) as
select conceito_id, termo_id, relacao, nota
from public.mapeamentos_de_conceito_legado m
where public._conceito_publicavel_13(m.conceito_id);

create view public.leituras_de_mercado_publicadas
with (security_invoker = true) as
select id, chave, conceito_id, semana, locale, titulo, resumo, estagio,
       territorio, metodologia_versao, lacunas, cobertura, publicada_em
from public.leituras_de_mercado l
where public._leitura_publicavel_13(l.id);

create view public.evidencias_de_mercado_publicadas
with (security_invoker = true) as
select
  le.leitura_id,
  le.papel,
  le.ordem,
  case when f.display_rights = 'link_only' then null else le.nota end as nota,
  e.id as evidencia_id,
  case when f.display_rights = 'link_only' then null else e.conceito_id end
    as conceito_id,
  case when f.display_rights = 'link_only' then null else c.familia end
    as familia,
  case when f.display_rights = 'link_only' then null else c.rotulo_pt end
    as rotulo_pt,
  case when f.display_rights = 'link_only' then null else c.rotulo_en end
    as rotulo_en,
  case when f.display_rights = 'link_only' then null else e.tipo end as tipo,
  case when f.display_rights = 'link_only' then null else e.direcao end as direcao,
  case when f.display_rights = 'link_only' then null else e.valor end as valor,
  case when f.display_rights = 'link_only' then null else e.resumo end as resumo,
  case when f.display_rights = 'link_only' then null else e.territorio end
    as territorio,
  case when f.display_rights = 'link_only' then null else e.periodo_inicio end
    as periodo_inicio,
  case when f.display_rights = 'link_only' then null else e.periodo_fim end
    as periodo_fim,
  case when f.display_rights = 'link_only' then null else e.unidade end
    as unidade,
  case when f.display_rights = 'link_only' then null
       else e.transformacao_versao end as transformacao_versao,
  case when f.display_rights = 'link_only' then null
       else e.conceito_versao end as conceito_versao,
  case when f.display_rights = 'link_only' then null
       else e.confianca_extracao end as confianca_extracao,
  case when f.display_rights = 'link_only' then null
       else e.metodologia_versao end as metodologia_versao,
  i.url_canonica,
  case when f.display_rights = 'link_only' then null else i.titulo end
    as titulo_da_fonte,
  case when f.display_rights = 'link_only' then null else i.publicado_em end
    as publicado_em,
  case when f.display_rights = 'link_only' then null else i.observado_em end
    as observado_em,
  case when f.display_rights = 'link_only' then null else i.geo end as geo,
  case when f.display_rights = 'link_only' then null else i.idioma end as idioma,
  case when f.display_rights = 'link_only' then null
       else i.familia_origem end as familia_origem,
  case when f.display_rights = 'link_only' then null
       else i.tipo_origem end as tipo_origem,
  case when f.display_rights = 'link_only' then null
       else i.unidade_original end as unidade_original,
  case when f.display_rights = 'link_only' then null
       else i.transformacao_versao end as transformacao_da_fonte_versao,
  case when f.display_rights = 'link_only' then null
       else i.conteudo_sha256 end as conteudo_sha256,
  i.fonte_contrato_sha256,
  f.id as fonte_id,
  f.nome as fonte,
  case when f.display_rights = 'link_only' then null else f.sensor end as sensor,
  f.termos_url,
  f.termos_versao
from public.leitura_evidencias le
join public.leituras_de_mercado l on l.id = le.leitura_id
join public.evidencias_de_sinal e on e.id = le.evidencia_id
join public.conceitos_de_moda c on c.id = e.conceito_id
join public.itens_de_fonte i on i.id = e.item_id
join public.fontes_de_sinal f on f.id = i.fonte_id
where public._leitura_publicavel_13(l.id);

grant select on public.conceitos_de_moda_publicados,
                public.mapeamentos_de_conceito_publicados,
                public.leituras_de_mercado_publicadas,
                public.evidencias_de_mercado_publicadas
  to service_role;

create or replace function public.listar_leituras_de_mercado_publicadas(
  p_limite integer default 50
)
returns setof public.leituras_de_mercado_publicadas
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select *
  from public.leituras_de_mercado_publicadas
  order by semana desc, id desc
  limit least(greatest(coalesce(p_limite, 50), 1), 100);
$$;

create or replace function public.evidencias_da_leitura_publicada(
  p_leitura_id bigint
)
returns setof public.evidencias_de_mercado_publicadas
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select *
  from public.evidencias_de_mercado_publicadas
  where leitura_id = p_leitura_id
  order by papel, ordem, evidencia_id;
$$;

-- Funções internas de trigger não são endpoints.
revoke all on function public._url_https_segura_13(text)
  from public, anon, authenticated, service_role;
revoke all on function public._host_da_url_13(text)
  from public, anon, authenticated, service_role;
revoke all on function public._url_no_escopo_13(text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public._jsonb_sem_dados_brutos_13(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public._textos_revisaveis_13(text[], integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public._url_https_segura_13(text),
                          public._host_da_url_13(text),
                          public._url_no_escopo_13(text, text, text),
                          public._jsonb_sem_dados_brutos_13(jsonb),
                          public._textos_revisaveis_13(text[], integer, integer)
  to service_role;

revoke all on function public._marcar_atualizado_em_13()
  from public, anon, authenticated, service_role;
revoke all on function public._serializar_escritas_criticas_13()
  from public, anon, authenticated, service_role;
revoke all on function public._validar_hierarquia_conceito_13()
  from public, anon, authenticated, service_role;
revoke all on function public._validar_versao_conceito_13()
  from public, anon, authenticated, service_role;
revoke all on function public._retirar_leituras_de_conceito_alterado_13()
  from public, anon, authenticated, service_role;
revoke all on function public._validar_mapeamento_legado_13()
  from public, anon, authenticated, service_role;
revoke all on function public._validar_fonte_do_item_13()
  from public, anon, authenticated, service_role;
revoke all on function public._proteger_execucao_13()
  from public, anon, authenticated, service_role;
revoke all on function public._proteger_item_publicado_13()
  from public, anon, authenticated, service_role;
revoke all on function public._proteger_evidencia_13()
  from public, anon, authenticated, service_role;
revoke all on function public._proteger_leitura_13()
  from public, anon, authenticated, service_role;
revoke all on function public._proteger_vinculo_de_leitura_13()
  from public, anon, authenticated, service_role;
revoke all on function public._retirar_leituras_de_fonte_revogada_13()
  from public, anon, authenticated, service_role;

revoke all on function public._leitura_publicavel_13(bigint)
  from public, anon, authenticated, service_role;
revoke all on function public._conceito_publicavel_13(text)
  from public, anon, authenticated, service_role;
grant execute on function public._leitura_publicavel_13(bigint)
  to service_role;
grant execute on function public._conceito_publicavel_13(text)
  to service_role;

revoke all on function public.revisar_conceito_de_moda(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.retirar_conceito_de_moda(text, text, text)
  from public, anon, authenticated;
revoke all on function public.revisar_evidencia_de_sinal(bigint, text, text, text)
  from public, anon, authenticated;
revoke all on function public.publicar_leitura_de_mercado(bigint, text)
  from public, anon, authenticated;
revoke all on function public.retirar_leitura_de_mercado(bigint, text, text)
  from public, anon, authenticated;
revoke all on function public.podar_itens_de_fonte_13(integer)
  from public, anon, authenticated;
revoke all on function public.listar_leituras_de_mercado_publicadas(integer)
  from public, anon, authenticated;
revoke all on function public.evidencias_da_leitura_publicada(bigint)
  from public, anon, authenticated;

grant execute on function public.revisar_conceito_de_moda(text, text, text, text)
  to service_role;
grant execute on function public.retirar_conceito_de_moda(text, text, text)
  to service_role;
grant execute on function public.revisar_evidencia_de_sinal(bigint, text, text, text)
  to service_role;
grant execute on function public.publicar_leitura_de_mercado(bigint, text)
  to service_role;
grant execute on function public.retirar_leitura_de_mercado(bigint, text, text)
  to service_role;
grant execute on function public.podar_itens_de_fonte_13(integer)
  to service_role;
grant execute on function public.listar_leituras_de_mercado_publicadas(integer)
  to anon, authenticated, service_role;
grant execute on function public.evidencias_da_leitura_publicada(bigint)
  to anon, authenticated, service_role;

comment on view public.conceitos_de_moda_publicados is
  'A51: conceitos aprovados usados por leitura ainda publicável, incluindo ancestrais necessários para reconstruir a hierarquia.';
comment on view public.mapeamentos_de_conceito_publicados is
  'A51: ponte ao termo legado somente para conceitos e termos que atravessaram os respectivos portões de publicação.';
comment on view public.leituras_de_mercado_publicadas is
  'A51: leituras publicadas e enxutas; drafts, withdrawn e execução não atravessam a API.';
comment on view public.evidencias_de_mercado_publicadas is
  'A51: trilha pública de cada leitura até conceito, item e fonte autorizada; publicação rejeita `link_only` e a máscara permanece como defesa em profundidade.';
