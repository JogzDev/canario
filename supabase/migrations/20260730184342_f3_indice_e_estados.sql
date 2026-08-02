-- Motor, passo 3: z-score, indice do atributo e estado semanal (§21, §22).

create table indices_semanais (
  id            bigint generated always as identity primary key,
  termo_id      text not null references termos(id),
  segmento      text not null,
  semana        date not null,
  indice        numeric,        -- media dos z das pernas ativas (§22)
  estado        text check (estado in ('em alta','em queda','pico','estavel')),
  pernas_ativas text[],         -- §8: a tela declara quais sustentam o numero
  n_pernas      integer,
  meta          jsonb,
  computado_em  timestamptz not null default now(),
  unique (termo_id, segmento, semana)
);

comment on table indices_semanais is
  'Saida do motor: indice e estado por termo/semana. O app so le daqui (§33).';
comment on column indices_semanais.pernas_ativas is
  '§8: "a interface declara quais pernas sustentam cada numero". Sem isto o app nao tem como ser honesto sobre a base.';

alter table indices_semanais enable row level security;
grant select on indices_semanais to anon, authenticated;
create policy "leitura publica dos indices computados"
  on indices_semanais for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- z-score contra a propria historia, janela movel de 12 semanas (§21)
-- ---------------------------------------------------------------------------
create or replace function computar_z()
returns integer
language plpgsql
security invoker
as $$
declare
  atualizadas integer;
begin
  with janela as (
    select
      s.id,
      s.fonte,
      s.valor_bruto,
      -- Janela movel de 12 semanas, SEM a semana corrente: comparar o valor
      -- com uma media que ja o contem amortece justamente o desvio que se quer
      -- medir.
      avg(s.valor_bruto) over w    as media,
      stddev_samp(s.valor_bruto) over w as desvio,
      count(*) over w              as n_semanas
    from series_semanais s
    window w as (
      partition by s.termo_id, s.segmento, s.fonte
      order by s.semana
      rows between 12 preceding and 1 preceding
    )
  )
  update series_semanais s
  set z = case
            -- B1: varejo nunca recebe z dentro da v1.
            when j.fonte = 'varejo' then null
            -- §8: minimo de historia. Editorial com 6 por EXCECAO PONTUAL do
            -- JP em 30/07, com escopo e prazo declarados no changelog; as
            -- demais pernas seguem exigindo 8.
            when j.n_semanas < (case when j.fonte like 'editorial%' then 6 else 8 end)
              then null
            -- Serie chapada: desvio zero nao produz z, produz divisao por zero.
            -- Nulo declarado, nunca valor plausivel (regra 2).
            when j.desvio is null or j.desvio = 0 then null
            else round((j.valor_bruto - j.media) / j.desvio, 4)
          end
  from janela j
  where j.id = s.id;

  get diagnostics atualizadas = row_count;
  return atualizadas;
end;
$$;

comment on function computar_z is
  'z contra a propria historia em janela de 12 semanas (§21). Varejo fica nulo (B1); editorial usa minimo 6 pela excecao de 30/07.';;
