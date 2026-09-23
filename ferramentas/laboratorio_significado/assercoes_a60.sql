-- Asserções da A60: uma regra só de cobertura para publicar o painel.
--
-- Roda depois de `assercoes.sql` (1-24, contra a A58) e da própria A60. Cada
-- caso monta o dia numa subtransação e a desfaz ao final com o erro de
-- controle LAB01; uma asserção que falha levanta outro código e derruba o
-- laboratório. O estado de partida é o que `assercoes.sql` deixa: painel
-- publicado em D-15, marcas 1 (Grande) e 2 (Pequena) com 100 visitados de
-- D-8 a D-2 e uma queda crítica da Pequena em D-1.

-- Prepara "hoje": a Grande coletou inteira; a Pequena depende do caso.
create or replace function pg_temp.hoje_da_grande() returns void
language sql as $$
  update public.estado_dos_produtos
     set ultimo_avistamento_em = current_date
   where produto_id between 1 and 500;
  insert into public.saude (data, fonte, marca_id, visitados, alertas)
  values (current_date, 'varejo', 1, 503, null);
$$;

create or replace function pg_temp.motor() returns jsonb
language plpgsql as $$
declare r jsonb; begin
  execute 'set local role service_role';
  r := public.computar_motor();
  execute 'reset role';
  return r;
end $$;

create or replace function pg_temp.motivo(p_marca bigint) returns text
language sql as $$
  select motivo from public.cobertura_de_publicacao('feminino_casual_br', current_date)
  where marca_id = p_marca;
$$;

-- 26. O caso de 22/09: marca adiada por cadência, com base saudável, não trava.
do $$
declare r jsonb; marcador date; begin
  begin
    perform pg_temp.hoje_da_grande();
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0,
       '{"adiado_por_cadencia": true, "cadencia": "semanal"}'::jsonb);
    assert pg_temp.motivo(2) = 'adiada_com_base',
      'Pequena adiada deveria estar coberta e veio ' || pg_temp.motivo(2);
    r := pg_temp.motor();
    select observado_em into marcador from public.observacoes_publicadas_do_painel
     where segmento = 'feminino_casual_br';
    assert (r->>'observacoes_publicadas')::int = 1 and marcador = current_date,
      'adiamento declarado travou o painel: ' || coalesce(r->>'observacoes_publicadas', 'nulo');
    -- Nada e inventado para a marca pulada: as pecas dela seguem na data antiga.
    assert (select max(ultimo_avistamento_em) from public.estado_dos_produtos
             where produto_id between 1001 and 1010) = current_date - 15,
      'o motor nao pode carimbar como vista hoje a marca que nao foi coletada';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 26 adiamento com base publica; a marca pulada guarda a propria data';
end $$;

-- 27. O outro caso de 22/09: recusa externa conhecida (http 429) por um dia.
do $$
declare r jsonb; c record; begin
  begin
    perform pg_temp.hoje_da_grande();
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0,
       '{"erro": "http 429 (persistiu apos backoff longo)"}'::jsonb);
    select * into c from public.cobertura_de_publicacao('feminino_casual_br', current_date)
     where marca_id = 2;
    -- D-1 foi queda critica (10 contra 100): conta como falha, o 429 de hoje
    -- e a segunda. Abaixo das 3 do coletor.
    assert c.coberta and c.motivo = 'recusa_externa_tolerada'
       and c.falhas_seguidas = 2 and c.ultima_saudavel = current_date - 2,
      'recusa de um dia deveria ser tolerada: ' || row_to_json(c)::text;
    r := pg_temp.motor();
    assert (r->>'observacoes_publicadas')::int = 1,
      'recusa tolerada pelo coletor travou o motor';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 27 recusa externa (429) tolerada como no coletor';
end $$;

-- 28. Recusa na terceira coleta seguida deixa de ser ruído e trava.
do $$
declare r jsonb; c record; begin
  begin
    perform pg_temp.hoje_da_grande();
    update public.saude set visitados = 0,
           alertas = '{"erro": "http 503"}'::jsonb
     where fonte = 'varejo' and marca_id = 2
       and data in (current_date - 2, current_date - 1);
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0, '{"erro": "http 429"}'::jsonb);
    select * into c from public.cobertura_de_publicacao('feminino_casual_br', current_date)
     where marca_id = 2;
    assert not c.coberta and c.motivo = 'recusa_persistente' and c.falhas_seguidas = 3,
      'terceira recusa seguida deveria travar: ' || row_to_json(c)::text;
    r := pg_temp.motor();
    assert (r->>'observacoes_publicadas')::int = 0,
      'recusa persistente publicou o painel';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 28 terceira recusa seguida trava, como DIAS_DE_ZERO_PARA_BLOQUEAR';
end $$;

-- 29. Zero sem recusa conhecida continua travando na hora (403 nao e ritmo).
do $$
declare r jsonb; begin
  begin
    perform pg_temp.hoje_da_grande();
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0,
       '{"erro": "http 403 ao contar categoria VTEX 134"}'::jsonb);
    assert pg_temp.motivo(2) = 'zero_sem_recusa_conhecida',
      '403 virou tolerancia: ' || pg_temp.motivo(2);
    r := pg_temp.motor();
    assert (r->>'observacoes_publicadas')::int = 0, 'zero com 403 publicou o painel';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 29 zero sem recusa conhecida trava no primeiro dia';
end $$;

-- 30. Adiamento sem observacao saudavel nos sete dias nao cobre ninguem.
do $$
declare r jsonb; begin
  begin
    perform pg_temp.hoje_da_grande();
    delete from public.saude
     where fonte = 'varejo' and marca_id = 2
       and data between current_date - 7 and current_date - 1;
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0, '{"adiado_por_cadencia": true}'::jsonb);
    assert pg_temp.motivo(2) = 'adiada_sem_observacao_em_7_dias',
      'adiamento sem base deveria travar: ' || pg_temp.motivo(2);
    r := pg_temp.motor();
    assert (r->>'observacoes_publicadas')::int = 0,
      'adiamento eterno publicou o painel';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 30 adiamento sem base nos 7 dias trava';
end $$;

-- 31. Dia de cadencia nao e falha: seis adiamentos + uma recusa = 1 falha.
do $$
declare c record; begin
  begin
    perform pg_temp.hoje_da_grande();
    update public.saude set visitados = 0,
           alertas = '{"adiado_por_cadencia": true, "cadencia": "semanal"}'::jsonb
     where fonte = 'varejo' and marca_id = 2
       and data between current_date - 6 and current_date - 1;
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 0, '{"erro": "http 429"}'::jsonb);
    select * into c from public.cobertura_de_publicacao('feminino_casual_br', current_date)
     where marca_id = 2;
    assert c.coberta and c.falhas_seguidas = 1 and c.ultima_saudavel = current_date - 7,
      'dias de cadencia foram contados como falha: ' || row_to_json(c)::text;
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 31 cadencia nao soma falhas; recusa na volta e a primeira';
end $$;

-- 32. O que a A58 ja reprovava continua reprovado: sem linha, truncado, queda.
do $$
begin
  begin
    perform pg_temp.hoje_da_grande();
    assert pg_temp.motivo(2) = 'sem_observacao_no_dia',
      'marca sem linha no dia: ' || pg_temp.motivo(2);
    insert into public.saude (data, fonte, marca_id, visitados, alertas) values
      (current_date, 'varejo', 2, 100, '{"faixas_truncadas": [1]}'::jsonb);
    assert pg_temp.motivo(2) = 'catalogo_truncado',
      'catalogo truncado: ' || pg_temp.motivo(2);
    update public.saude set visitados = 10, alertas = null
     where fonte = 'varejo' and marca_id = 2 and data = current_date;
    assert pg_temp.motivo(2) = 'queda_critica',
      'queda critica: ' || pg_temp.motivo(2);
    assert (pg_temp.motor()->>'observacoes_publicadas')::int = 0,
      'queda critica publicou o painel com a A60';
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 32 sem linha, truncado e queda critica seguem travando';
end $$;

-- 33. A regra e interna: anon nao le cobertura de marca por marca.
do $$
begin
  begin
    execute 'set local role anon';
    perform public.cobertura_de_publicacao('feminino_casual_br', current_date);
    execute 'reset role';
    raise exception 'anon executou cobertura_de_publicacao';
  exception when insufficient_privilege then
    execute 'reset role';
  end;
  raise notice 'ok 33 anon recebe 42501 na cobertura';
end $$;
