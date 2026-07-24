-- Canário — F1, Passo 2: schema (Anexo D) + RLS na mesma migração.
--
-- Modelo de acesso (RESPOSTAS_AUDITORIA, seção 5): a chave publishable é
-- pública por design e vai embutida no binário do app. A segurança do banco
-- depende INTEIRAMENTE das políticas RLS, nunca do sigilo da chave. Por isso
-- as políticas entram ANTES de qualquer tabela receber uma linha.
--
-- Regra de ouro desta migração:
--   * o coletor escreve com a chave secreta (role `service_role`), que tem
--     BYPASSRLS: enxerga e escreve tudo.
--   * o app lê com a chave publishable (role `anon`): só enxerga a saída
--     computada (series_semanais e, no futuro, as views do motor). Nunca
--     escreve. Nunca vê tabela crua de snapshot.
--
-- Servidor calcula, app consulta, câmera fica local (§33).

-- ---------------------------------------------------------------------------
-- 1. TABELAS (Anexo D, com as correções das respostas)
-- ---------------------------------------------------------------------------

-- Painel de marcas. B4: `segmento` aqui é só o PADRÃO da marca; o segmento
-- que vale é o de `produtos`, derivado do mapa de categorias.
create table marcas (
  id            bigint generated always as identity primary key,
  nome          text not null unique,
  dominio       text,
  plataforma    text check (plataforma in ('vtex','shopify')),
  segmento      text,
  papel         text not null check (papel in
                  ('nucleo','adjacente','ancora','multimarca','grupo','direcao')),
  justificativa text,
  status_teste  text not null default 'pendente' check (status_teste in
                  ('pendente','vtex','shopify','falhou','nao_se_aplica')),
  data_teste    date,
  detalhe_teste text,
  congelada_em  date,     -- regra 5 e K11: data do congelamento da coorte
  ativa         boolean not null default true
);
comment on column marcas.segmento is
  'B4: padrão de fallback. O segmento que vale é produtos.segmento.';
comment on column marcas.congelada_em is
  'Congelamento da coorte por temporada (regra 5). Marca nova só na virada.';

-- Catálogo. flag_tipo ganha os valores presumidos da A1 (bootstrap do
-- classificador continuativo enquanto não há 26 semanas de história).
create table produtos (
  id                   bigint generated always as identity primary key,
  marca_id             bigint not null references marcas(id),
  id_externo           text not null,
  url                  text,
  titulo               text,
  descricao            text,
  categoria_site       text,
  imagem_url           text,      -- v1 guarda só a URL (§17), nunca o binário
  segmento             text,      -- B4: derivado por produto do mapa de categorias
  primeiro_avistamento date,
  flag_tipo            text not null default 'indefinido' check (flag_tipo in
                         ('continuativo','colecao','indefinido',
                          'continuativo_presumido','colecao_presumida')),
  unique (marca_id, id_externo)
);
comment on column produtos.segmento is
  'B4: segmento autoritativo, derivado do mapa de categorias. NULL até o mapa ser aprovado.';
comment on column produtos.flag_tipo is
  'A1: *_presumido é classificação provisória por regra, substituída pela medida quando K2/K3 tiverem dados.';

-- Snapshots. B3: GRAVAÇÃO POR DELTA. O coletor visita todo produto todo dia,
-- mas só grava linha quando algo mudou (preço, disponibilidade, grade), mais
-- um batimento semanal por produto. A série diária é reconstruída por
-- carry-forward na leitura: cada linha é um ponto de mudança.
create table snapshots (
  id                bigint generated always as identity primary key,
  produto_id        bigint not null references produtos(id),
  data              date not null,          -- data lógica do snapshot
  preco_original    numeric(10,2),
  preco_atual       numeric(10,2),
  composicao        text,                   -- capturar desde o 1o respiro (§17)
  grade_por_tamanho jsonb,                  -- {"P": true, "M": false, ...} disponível/indisponível
  capturado_em      timestamptz not null default now(),
  unique (produto_id, data)
);
comment on table snapshots is
  'B3: gravação por delta. Linha = ponto de mudança. Dia sem linha herda o anterior (carry-forward na leitura).';

-- Eventos derivados, computados pelo motor (não pelo coletor).
create table eventos (
  id         bigint generated always as identity primary key,
  produto_id bigint not null references produtos(id),
  tipo       text not null check (tipo in ('reposicao','remarcacao','saida_de_linha')),
  data       date not null,
  detalhe    jsonb
);

-- Taxonomia: espelho do CSV aprovado. id textual e estável (§11, nunca muda).
-- C2: coluna `exclusiva` por dimensão. C3: coluna `sem_perna_busca`.
create table termos (
  id              text primary key,
  rotulo          text not null,
  dimensao        text not null,
  exclusiva       boolean not null,
  sinonimos       text,
  termo_busca     text,
  palavras_pt     text,
  palavras_en     text,
  exemplo         text,
  status          text not null default 'proposto' check (status in
                    ('proposto','aprovado','reprovado')),
  sem_perna_busca text not null default 'pendente' check (sem_perna_busca in
                    ('pendente','sim','nao')),
  motivo          text
);
comment on table termos is
  'Espelho do CSV aprovado. O motor só usa linhas status=aprovado (regra 4).';

-- Casamento produto → termo. origem distingue de onde veio a etiqueta.
create table produto_termos (
  produto_id bigint not null references produtos(id),
  termo_id   text not null references termos(id),
  origem     text not null check (origem in ('titulo','visao','manual')),
  primary key (produto_id, termo_id, origem)
);

-- Editorial. Nunca guardar o texto integral (§18): só metadados e contagem.
create table artigos (
  id       bigint generated always as identity primary key,
  veiculo  text not null,
  url      text not null unique,
  titulo   text,
  data_pub date
);

-- Contagem única por (artigo, termo): um artigo conta no máximo 1x por termo.
create table artigo_termos (
  artigo_id bigint not null references artigos(id),
  termo_id  text not null references termos(id),
  primary key (artigo_id, termo_id)
);

-- Saída computada pelo motor. É o que o app lê. `fonte` distingue as pernas;
-- C5 dá ao Lyst fonte própria; a ambiguidade 2 separa editorial_br de intl.
create table series_semanais (
  id          bigint generated always as identity primary key,
  termo_id    text not null references termos(id),
  segmento    text not null,
  fonte       text not null check (fonte in
                ('varejo','busca','editorial_br','editorial_intl','lyst')),
  semana      date not null,           -- segunda-feira da semana ISO
  valor_bruto numeric,
  z           numeric,                 -- nulo até 8 semanas de história (§21)
  n_amostra   integer,
  unique (termo_id, segmento, fonte, semana)
);
comment on column series_semanais.z is
  'NULL até a série ter 8 semanas (§8/§21). Varejo nunca terá z na v1 (B1).';

-- Relatório de saúde diário (§20 + K9). Uma linha por (data, fonte) e, quando
-- marca_id não é nulo, o detalhe por marca. B3: visitados vs gravados.
-- Condição 2.3: total_declarado vem do header `resources` da VTEX (0-49/13436)
-- para denunciar truncamento por construção.
create table saude (
  id              bigint generated always as identity primary key,
  data            date not null,
  fonte           text not null,
  marca_id        bigint references marcas(id),
  visitados       integer,      -- produtos tocados (B3)
  gravados        integer,      -- linhas de snapshot escritas (B3)
  itens           integer,      -- itens coletados na fonte
  total_declarado integer,      -- total que a fonte diz existir (header resources)
  pct_campos_ok   numeric,
  alertas         jsonb,
  criado_em       timestamptz not null default now(),
  unique (data, fonte, marca_id)
);
comment on column saude.total_declarado is
  'Condição 2.3: total declarado pela fonte (header resources da VTEX). Divergência >2% vs itens vira alerta.';

-- ---------------------------------------------------------------------------
-- 2. RLS: negar por padrão, ANTES de qualquer dado
-- ---------------------------------------------------------------------------

alter table marcas          enable row level security;
alter table produtos        enable row level security;
alter table snapshots       enable row level security;
alter table eventos         enable row level security;
alter table termos          enable row level security;
alter table produto_termos  enable row level security;
alter table artigos         enable row level security;
alter table artigo_termos   enable row level security;
alter table series_semanais enable row level security;
alter table saude           enable row level security;

-- Defesa em profundidade: o Supabase concede privilégios a anon/authenticated
-- por padrão em tabelas novas do schema public. Revogamos tudo. O que o app
-- pode ler é reconcedido explicitamente, item por item, abaixo. O coletor usa
-- service_role, que ignora RLS e não depende destes grants.
revoke all on all tables in schema public from anon, authenticated;

-- Única superfície pública da v1: a série computada que o app consome.
-- Escrita continua negada (não existe policy de INSERT/UPDATE/DELETE para anon).
-- As demais views computadas do motor (camada descritiva de varejo, B1.3)
-- ganham policy de leitura própria quando forem criadas na F3.
grant select on series_semanais to anon, authenticated;
create policy "leitura publica das series computadas"
  on series_semanais for select
  to anon, authenticated
  using (true);
