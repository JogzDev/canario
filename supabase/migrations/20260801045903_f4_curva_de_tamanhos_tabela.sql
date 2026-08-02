create table if not exists public.curva_tamanhos (
  id              bigserial primary key,
  termo_id        text references public.termos(id) on delete cascade,
  segmento        text not null,
  semana          date not null,
  sistema         text not null,
  faixa           text not null,
  rotulo          text,
  n_grades        integer not null,
  n_pares         integer not null,
  n_indisponivel  integer not null,
  n_quebrou       integer not null default 0,
  share_indisponivel numeric,
  meta            jsonb,
  computado_em    timestamptz not null default now()
);

create unique index if not exists curva_tamanhos_chave
  on public.curva_tamanhos (termo_id, segmento, semana, sistema, faixa, rotulo)
  nulls not distinct;

create index if not exists curva_tamanhos_busca
  on public.curva_tamanhos (segmento, semana desc, termo_id);

alter table public.curva_tamanhos enable row level security;

drop policy if exists curva_tamanhos_leitura on public.curva_tamanhos;
create policy curva_tamanhos_leitura on public.curva_tamanhos
  for select to anon, authenticated using (true);;
