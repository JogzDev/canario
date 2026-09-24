-- Asserções da A64: a marca da Nuvemshop é cobrada pelo portão de publicação.
--
-- O `rodar.mjs` roda este arquivo duas vezes: antes da A64, numa transação
-- desfeita, e exige que ele REPROVE (a A60 deixa a Amaro fora da coorte);
-- depois da A64, e exige que passe. A Amaro da fixture da A61 (marca 7)
-- entra como está em produção desde 23/09: `nuvemshop`.

-- 60. Amaro sem coleta no dia trava a publicação; com coleta, está coberta.
do $$
declare c record; begin
  begin
    update public.marcas set plataforma = 'nuvemshop', status_teste = 'nuvemshop'
     where id = 7;
    delete from public.saude
     where fonte = 'varejo' and marca_id = 7 and data = current_date;
    select * into c from public.cobertura_de_publicacao('feminino_casual_br', current_date)
     where marca_id = 7;
    assert c.marca_id is not null,
      'a Amaro na Nuvemshop ficou fora da cobertura: publicaria sem ela';
    assert not c.coberta and c.motivo = 'sem_observacao_no_dia',
      'Amaro sem coleta no dia deveria travar: ' || row_to_json(c)::text;
    insert into public.saude (data, fonte, marca_id, visitados, alertas)
    values (current_date, 'varejo', 7, 360, null);
    select * into c from public.cobertura_de_publicacao('feminino_casual_br', current_date)
     where marca_id = 7;
    assert c.coberta and c.motivo = 'observada',
      'Amaro coletada inteira deveria estar coberta: ' || row_to_json(c)::text;
    raise exception using errcode = 'LAB01';
  exception when sqlstate 'LAB01' then null;
  end;
  raise notice 'ok 60 a Amaro na Nuvemshop entra na coorte: sem coleta trava, com coleta publica';
end $$;
