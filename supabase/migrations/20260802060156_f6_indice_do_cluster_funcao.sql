create or replace function public.indice_do_cluster(termos text[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  categoria_da_peca text;
  n_categorias      integer;
  resultado         jsonb;
begin
  if termos is null or array_length(termos, 1) is null then
    return jsonb_build_object('erro', 'nenhum atributo informado');
  end if;

  select count(*), min(t.id) into n_categorias, categoria_da_peca
  from termos t
  where t.id = any(indice_do_cluster.termos) and t.dimensao = 'categoria';

  if coalesce(n_categorias, 0) <> 1 then
    categoria_da_peca := '(todas)';
  end if;

  return (
  with
  ultimo as (
    select distinct on (i.termo_id)
           i.termo_id, i.indice, i.estado, i.semana, i.pernas_ativas, i.n_pernas
    from indices_semanais i
    where i.termo_id = any(indice_do_cluster.termos)
    order by i.termo_id, i.semana desc
  ),
  com_cobertura as (
    select u.*, coalesce(c.suficiente, true) as cobertura_ok
    from ultimo u
    left join cobertura_por_celula c
      on c.termo_id = u.termo_id and c.semana = u.semana
  ),
  pedido as (
    select t.id as termo_id, t.rotulo, t.dimensao, t.papel,
           r.peso, r.pecas, r.p_observado,
           cc.indice, cc.estado, cc.semana, cc.pernas_ativas, cc.n_pernas,
           case
             when cc.indice is null   then 'sem leitura neste recorte'
             when not coalesce(cc.cobertura_ok, false)
                                      then 'cobertura insuficiente (§8)'
             when r.peso is null      then 'sem raridade computada'
             else null
           end as fora_por
    from termos t
    left join raridade_do_atributo r
      on r.termo_id = t.id and r.categoria = categoria_da_peca
    left join com_cobertura cc on cc.termo_id = t.id
    where t.id = any(indice_do_cluster.termos)
  ),
  somas as (
    select coalesce(sum(peso), 0)          as soma_w,
           coalesce(sum(peso * peso), 0)   as soma_w2,
           coalesce(sum(peso * indice), 0) as soma_wz,
           count(*)::integer               as n_atributos
    from pedido where fora_por is null
  ),
  media as (
    select s.*, case when s.soma_w > 0 then s.soma_wz / s.soma_w end as indice
    from somas s
  ),
  espalhamento as (
    select m.*,
      (select case when m.soma_w > 0 and m.n_atributos > 1
                then sqrt(sum(p.peso * (p.indice - m.indice) ^ 2) / m.soma_w)
              end
         from pedido p where p.fora_por is null) as desvio
    from media m
  )
  select jsonb_build_object(
    'categoria_usada', categoria_da_peca,
    'indice',      round(e.indice, 4),
    'dispersao',   round(e.desvio, 4),
    'atributos_efetivos',
        round((e.soma_w ^ 2) / nullif(e.soma_w2, 0), 2),
    'n_atributos', e.n_atributos,
    'ha_direcao',  case when e.n_atributos = 0 then false
                        when e.n_atributos = 1 then true
                        else abs(e.indice) >= coalesce(e.desvio, 0) end,
    'unidade', 'desvios-padrao da propria historia de cada atributo (§21)',
    'metodo',  'media dos indices ponderada por raridade dentro da dimensao e '
               || 'da categoria, com encolhimento para o prior em contagem '
               || 'baixa (§22, K5)',
    'atributos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'termo_id', p.termo_id,
        'rotulo',   p.rotulo,
        'dimensao', p.dimensao,
        'papel',    p.papel,
        'indice',   p.indice,
        'estado',   p.estado,
        'semana',   p.semana,
        'pernas',   p.pernas_ativas,
        'peso',     round(p.peso, 4),
        'peso_relativo', case when e.soma_w > 0 and p.fora_por is null
                              then round(p.peso / e.soma_w, 4) end,
        'pecas_no_painel', p.pecas,
        'pct_na_dimensao', round(100 * p.p_observado, 1),
        'fora_por', p.fora_por
      ) order by (p.fora_por is not null), p.peso desc nulls last), '[]'::jsonb)
      from pedido p
    )
  )
  from espalhamento e);
end;
$function$;

revoke all on function public.indice_do_cluster(text[]) from public;
grant execute on function public.indice_do_cluster(text[]) to anon, authenticated;;
