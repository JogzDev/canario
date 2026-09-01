-- A52: janela mínima e somente-leitura para o primeiro pacote factual da 1.3.
--
-- A composição continua no snapshot cru e obedece à poda de 21 dias. Esta RPC
-- deixa o service_role ler apenas produtos do segmento principal que estão
-- ofertáveis e foram avistados nos últimos sete dias. O materializador local
-- transforma a etiqueta antes da poda; nenhuma descrição de marketing volta.

create or replace function public.exportar_linhas_etiqueta_13(
  p_data_corte date,
  p_after_id bigint default 0,
  p_limit integer default 1000
)
returns table (
  data_corte              date,
  produto_id              bigint,
  marca_id                bigint,
  segmento                text,
  ofertavel               boolean,
  ultimo_avistamento_em   date,
  snapshot_data           date,
  composicao              text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_data_corte is null
     or p_data_corte not between v_hoje - 1 and v_hoje then
    raise exception 'label_export_cutoff_outside_operational_window';
  end if;
  if p_after_id is null or p_after_id < 0 then
    raise exception 'label_export_cursor_invalid';
  end if;
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'label_export_page_size_invalid';
  end if;

  return query
  select
    p_data_corte,
    p.id,
    p.marca_id,
    p.segmento,
    ep.ofertavel,
    ep.ultimo_avistamento_em,
    etiqueta.data,
    etiqueta.composicao
  from public.produtos p
  join public.estado_dos_produtos ep
    on ep.produto_id = p.id
   and ep.ofertavel is true
   and ep.ultimo_avistamento_em between p_data_corte - 7 and p_data_corte
  left join lateral (
    select s.data, s.composicao
    from public.snapshots s
    where s.produto_id = p.id
      and s.data between p_data_corte - 21 and p_data_corte
      and s.composicao is not null
      and length(btrim(s.composicao)) > 0
      and length(s.composicao) <= 100000
    order by s.data desc, s.id desc
    limit 1
  ) etiqueta on true
  where p.id > p_after_id
    and p.segmento = 'feminino_casual_br'
  order by p.id
  limit p_limit;
end;
$$;

comment on function public.exportar_linhas_etiqueta_13(date, bigint, integer) is
  'A52: exportação privada, atual, paginada e minimizada para o parser local da Etiqueta. A RPC não escreve, não publica e não expõe o catálogo a anon/authenticated.';

revoke all on function public.exportar_linhas_etiqueta_13(date, bigint, integer)
  from public, anon, authenticated;
grant execute on function public.exportar_linhas_etiqueta_13(date, bigint, integer)
  to service_role;
