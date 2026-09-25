-- Fixture da A68: a curva mede a janela que observou.
--
-- Roda depois da A62 e da A64, na mesma sessão: usa o relógio `relogio_a62`
-- (H) e as leituras `pg_temp.semana_a62` e `pg_temp.faixas_a62`.
--
-- A A68 lê em `saude` os dias de coleta SAUDÁVEL de cada marca. A fixture da
-- A62 não tinha nenhum; aqui as marcas dela ganham os dias que tornam as
-- contas da A62 (19 em risco, 6 quebras) verdadeiras também pela regra nova,
-- e `assercoes_a62.sql` roda de novo depois da A68, inteira.
--
-- AS FOTOS SEGUEM O COLETOR
-- =========================
--
-- O coletor grava foto quando algo muda na peça, ou no batimento de sete
-- dias. Então peça sem foto num dia está como na última foto antes dele.
--
-- `lab_janela` (marca 91, coletada em H-5, H-2 e H; janela H-5..H):
--   9101 foto em H-8, todos à venda; em H-2 o G esgota    -> 5 em risco, 1 quebra
--        (a regra antiga só via a quebra quando H-8 caía dentro da janela
--        nominal, o que depende do dia da semana; quando caía fora, a
--        primeira foto de dentro já era a do G esgotado)
--   9102 última foto em H-12, sete dias antes do início   -> fora (a peça não
--        foi vista no início)
--   9103 nova, primeira foto em H-3                       -> fora (não existia
--        no início)
--   9104 vista pela última vez em H-6, antes do início    -> fora
--   9107 foto em H-8, e em H-5 o M esgota no próprio dia do início
--        -> 4 em risco (o M já começou esgotado), 0 quebras
--   total: 9 em risco, 1 quebra; janela declarada H-5..H, 5 dias, 1 marca
--
-- `lab_janela_um_dia` (marca 92, uma coleta só, em H-1 -- o caso do catálogo
-- candidato em 21/09):
--   9201 foto em H-8 inteira, em H-1 o P esgotado         -> nada em risco
--   sem janela declarada
--
-- `lab_janela_parcial` (marca 93): saudável em H-5 e H-3. Depois disso,
-- H-2 adiado (zero), H-1 truncado, H parcial (10 contra média 100).
--   9301 foto em H-8 inteira; em H-2 o PP esgota          -> 5 em risco, 0 quebras
--        (a janela termina em H-3: qualquer dia não saudável que contasse
--        levaria o fim para depois da troca e criaria a quebra)
--   janela declarada H-5..H-3, 2 dias

insert into public.marcas
  (id, nome, papel, segmento, status_teste, plataforma, ativa) values
  (91, 'Lab janela diaria', 'nucleo', 'lab_janela', 'vtex', 'vtex', true),
  (92, 'Lab janela um dia', 'nucleo', 'lab_janela_um_dia', 'vtex', 'vtex', true),
  (93, 'Lab janela parcial', 'nucleo', 'lab_janela_parcial', 'vtex', 'vtex', true);

-- Dias de coleta. As marcas da fixture da A62 ganham o que as contas dela
-- pedem: a 81 nos dois dias em que tem foto (H-7 e H), a 82 do catálogo novo
-- em H-1 e H.
insert into public.saude (data, fonte, marca_id, visitados, alertas)
select v.data, 'varejo', v.marca, v.visitados, v.alertas::jsonb
from relogio_a62 r
cross join lateral (values
  (r.h - 7, 81, 100, '{}'), (r.h, 81, 100, '{}'),
  (r.h - 1, 82, 100, '{}'), (r.h, 82, 100, '{}'),
  (r.h - 5, 91, 100, '{}'), (r.h - 2, 91, 100, '{}'), (r.h, 91, 100, '{}'),
  (r.h - 1, 92, 100, '{}'),
  (r.h - 5, 93, 100, '{}'), (r.h - 3, 93, 100, '{}'),
  (r.h - 2, 93, 0, '{"adiado_por_cadencia": true}'),
  (r.h - 1, 93, 100, '{"truncou": true}'),
  (r.h, 93, 10, '{}')
) v(data, marca, visitados, alertas);

insert into public.produtos (id, marca_id, segmento, titulo, url, ultima_grade)
select v.id, v.marca, v.segmento, v.titulo, 'https://lab.example/' || v.id, v.grade::jsonb
from (values
  (9101, 91, 'lab_janela', 'Esgotou o G no meio da janela',
   '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (9102, 91, 'lab_janela', 'Sem foto no inicio',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9103, 91, 'lab_janela', 'Nova na janela',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9104, 91, 'lab_janela', 'Vista antes do inicio',
   '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9107, 91, 'lab_janela', 'Esgotou o M no dia do inicio',
   '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  (9201, 92, 'lab_janela_um_dia', 'Marca com uma coleta so',
   '{"PP": true, "P": false, "M": true, "G": true, "GG": true}'),
  (9301, 93, 'lab_janela_parcial', 'Esgotou depois da ultima coleta saudavel',
   '{"PP": false, "P": true, "M": true, "G": true, "GG": true}')
) v(id, marca, segmento, titulo, grade);

insert into public.estado_dos_produtos
  (produto_id, ultimo_avistamento_em, ofertavel, ultimo_snapshot_em)
select v.id, v.visto, true, v.foto
from relogio_a62 r
cross join lateral (values
  (9101, r.h, r.h - 2),
  (9102, r.h, r.h - 12),
  (9103, r.h, r.h - 3),
  (9104, r.h - 6, r.h - 8),
  (9107, r.h, r.h - 5),
  (9201, r.h - 1, r.h - 1),
  (9301, r.h, r.h - 2)
) v(id, visto, foto);

insert into public.snapshots (produto_id, data, ofertavel, grade_por_tamanho)
select v.id, v.data, true, v.grade::jsonb
from relogio_a62 r
cross join lateral (values
  (9101, r.h - 8, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9101, r.h - 2, '{"PP": true, "P": true, "M": true, "G": false, "GG": true}'),
  (9102, r.h - 12, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9103, r.h - 3, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9104, r.h - 8, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9107, r.h - 8, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9107, r.h - 5, '{"PP": true, "P": true, "M": false, "G": true, "GG": true}'),
  (9201, r.h - 8, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9201, r.h - 1, '{"PP": true, "P": false, "M": true, "G": true, "GG": true}'),
  (9301, r.h - 8, '{"PP": true, "P": true, "M": true, "G": true, "GG": true}'),
  (9301, r.h - 2, '{"PP": false, "P": true, "M": true, "G": true, "GG": true}')
) v(id, data, grade);

-- A janela declarada de um segmento na semana alvo. Todas as linhas do
-- segmento carregam a mesma.
create function pg_temp.janela_a68(p_segmento text) returns jsonb
language sql stable as $$
  select (array_agg(distinct meta->'janela_observada'))[1]
  from public.curva_tamanhos
  where segmento = p_segmento and semana = pg_temp.semana_a62();
$$;
