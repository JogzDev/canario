-- Canário — F1, Passo 2: schema (Anexo D) + RLS na mesma migração.
-- Coletor escreve com service_role (BYPASSRLS). App lê com anon: só series_semanais.

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
  congelada_em  date,
  ativa         boolean not null default true
);
comment on column marcas.segmento is
  'B4: padrão de fallback. O segmento que vale é produtos.segmento.';
comment on column marcas.congelada_em is
  'Congelamento da coorte por temporada (regra 5). Marca nova só na virada.';

create table produtos (
  id                   bigint generated always as identity primary key,
  marca_id             bigint not null references marcas(id),
  id_externo           text not null,
  url                  text,
  titulo               text,
  descricao            text,
  categoria_site       text,
  imagem_url           text,
  segmento             text,
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

create table snapshots (
  id                bigint generated always as identity primary key,
  produto_id        bigint not null references produtos(id),
  data              date not null,
  preco_original    numeric(10,2),
  preco_atual       numeric(10,2),
  composicao        text,
  grade_por_tamanho jsonb,
  capturado_em      timestamptz not null default now(),
  unique (produto_id, data)
);
comment on table snapshots is
  'B3: gravação por delta. Linha = ponto de mudança. Dia sem linha herda o anterior (carry-forward na leitura).';

create table eventos (
  id         bigint generated always as identity primary key,
  produto_id bigint not null references produtos(id),
  tipo       text not null check (tipo in ('reposicao','remarcacao','saida_de_linha')),
  data       date not null,
  detalhe    jsonb
);

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

create table produto_termos (
  produto_id bigint not null references produtos(id),
  termo_id   text not null references termos(id),
  origem     text not null check (origem in ('titulo','visao','manual')),
  primary key (produto_id, termo_id, origem)
);

create table artigos (
  id       bigint generated always as identity primary key,
  veiculo  text not null,
  url      text not null unique,
  titulo   text,
  data_pub date
);

create table artigo_termos (
  artigo_id bigint not null references artigos(id),
  termo_id  text not null references termos(id),
  primary key (artigo_id, termo_id)
);

create table series_semanais (
  id          bigint generated always as identity primary key,
  termo_id    text not null references termos(id),
  segmento    text not null,
  fonte       text not null check (fonte in
                ('varejo','busca','editorial_br','editorial_intl','lyst')),
  semana      date not null,
  valor_bruto numeric,
  z           numeric,
  n_amostra   integer,
  unique (termo_id, segmento, fonte, semana)
);
comment on column series_semanais.z is
  'NULL até a série ter 8 semanas (§8/§21). Varejo nunca terá z na v1 (B1).';

create table saude (
  id              bigint generated always as identity primary key,
  data            date not null,
  fonte           text not null,
  marca_id        bigint references marcas(id),
  visitados       integer,
  gravados        integer,
  itens           integer,
  total_declarado integer,
  pct_campos_ok   numeric,
  alertas         jsonb,
  criado_em       timestamptz not null default now(),
  unique (data, fonte, marca_id)
);
comment on column saude.total_declarado is
  'Condição 2.3: total declarado pela fonte (header resources da VTEX). Divergência >2% vs itens vira alerta.';

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

revoke all on all tables in schema public from anon, authenticated;

grant select on series_semanais to anon, authenticated;
create policy "leitura publica das series computadas"
  on series_semanais for select
  to anon, authenticated
  using (true);;
