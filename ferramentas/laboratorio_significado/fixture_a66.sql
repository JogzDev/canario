-- Fixture da A66: um atributo da taxonomia no laboratório. 7302 e 7304 são
-- "midi" pelo motor; 7301 não tem comprimento ligado.
insert into public.termos (id, rotulo, dimensao, status, papel)
values ('lab_midi', 'Midi (lab)', 'comprimento', 'aprovado', 'atributo');
insert into public.produto_termos (produto_id, termo_id) values (7302, 'lab_midi'), (7304, 'lab_midi');
