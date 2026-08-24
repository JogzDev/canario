-- A34: couro entra como tecido aprovado, com a mesma rastreabilidade dos
-- demais termos. O histórico não é inventado: varejo nasce desta data e o
-- portão de suficiência continua impedindo leitura estatística prematura.

insert into public.termos
  (id, rotulo, dimensao, exclusiva, sinonimos, termo_busca, palavras_pt,
   palavras_en, exemplo, status, sem_perna_busca, motivo, papel)
values
  ('couro', 'Couro', 'tecido', false,
   'leather|courino|couro sintetico|couro ecologico', 'vestido de couro',
   'couro|courino|pelica|couro sintetico|couro ecologico',
   'leather|faux leather|vegan leather',
   'Couro natural ou superficie declarada como couro sintetico',
   'aprovado', 'pendente',
   'A34: nasce sem z ate cumprir a janela minima', 'atributo')
on conflict (id) do update set
  rotulo = excluded.rotulo,
  dimensao = excluded.dimensao,
  exclusiva = excluded.exclusiva,
  sinonimos = excluded.sinonimos,
  termo_busca = excluded.termo_busca,
  palavras_pt = excluded.palavras_pt,
  palavras_en = excluded.palavras_en,
  exemplo = excluded.exemplo,
  status = excluded.status,
  sem_perna_busca = excluded.sem_perna_busca,
  motivo = excluded.motivo,
  papel = excluded.papel;

insert into public.produto_termos(produto_id, termo_id, origem)
select p.id, 'couro', 'titulo'
from public.produtos p
where lower(coalesce(p.titulo, '')) ~
  '\m(couro|courino|pelica|leather|faux leather|vegan leather)\M'
on conflict do nothing;
