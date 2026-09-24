-- A67: o mesmo pedido, a mesma leitura.
--
-- Em 24/09/2026, "saia midi plissada" leu 11 saias numa rodada e 4 na
-- seguinte: a Luna escolheu sinais diferentes ("pregas" entrou numa e não na
-- outra). O dado muda de um dia para o outro; o significado do pedido não.
-- A interpretação (categoria, atributos, sinais, vetos) passa a ser guardada
-- por pedido e reaproveitada por sete dias. Candidatas e fatos continuam
-- calculados na hora, sobre o painel publicado.
--
-- A chave é um hash do pedido normalizado (texto, refinamento e a análise da
-- foto): nenhum texto de quem usa o app fica guardado aqui.

create table if not exists public.interpretacoes_da_leitura (
  chave text primary key check (chave ~ '^[0-9a-f]{64}$'),
  interpretacao jsonb not null,
  versao text not null,
  criado_em timestamptz not null default now()
);

alter table public.interpretacoes_da_leitura enable row level security;
alter table public.interpretacoes_da_leitura force row level security;
revoke all on public.interpretacoes_da_leitura from public, anon, authenticated;
grant select, insert, update, delete on public.interpretacoes_da_leitura to service_role;

comment on table public.interpretacoes_da_leitura is
  'A67: interpretacao da leitura especifica por hash do pedido, valida por sete dias; a Edge Function ler-peca le e grava.';

select cron.schedule('canario-interpretacoes-da-leitura', '47 4 * * *',
  $cron$delete from public.interpretacoes_da_leitura where criado_em < now() - interval '7 days';$cron$);
