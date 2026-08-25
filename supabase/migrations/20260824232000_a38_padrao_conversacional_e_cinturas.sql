-- A38: completa Waist e impede que o detalhe técnico `motivo_estampa`
-- apareça como uma taxonomia paralela na interface. O termo conversacional é
-- o guarda-chuva observável; tomate/cereja/etc. permanecem detalhe de similares.

insert into public.termos
  (id, rotulo, dimensao, exclusiva, sinonimos, termo_busca, palavras_pt,
   palavras_en, exemplo, status, sem_perna_busca, motivo, papel)
values
  ('conversacional', 'Estampa conversacional', 'estampa', true,
   'figurativa|novelty print|estampa de objetos', null,
   'figurativa|conversacional|estampa de objetos|estampa de frutas|estampa de legumes|coracao|estrela|borboleta',
   'conversational print|novelty print|object print|fruit print|food print|heart print|star print|butterfly print',
   'Estampa de objetos, alimentos, plantas ou símbolos reconhecíveis',
   'aprovado', 'sim', 'A38: guarda-chuva visual; não cria série de busca', 'atributo'),
  ('cintura_media', 'Cintura média', 'cintura', true,
   'cos medio|mid rise', 'calca cintura media', 'cintura media|cos medio',
   'mid waist|mid-waisted|mid rise', 'Cós na linha natural',
   'aprovado', 'pendente', 'A38: completa a dimensão cintura', 'atributo'),
  ('cintura_baixa', 'Cintura baixa', 'cintura', true,
   'cos baixo|low rise', 'calca cintura baixa', 'cintura baixa|cos baixo',
   'low waist|low-waisted|low rise', 'Cós abaixo da linha natural',
   'aprovado', 'pendente', 'A38: completa a dimensão cintura', 'atributo')
on conflict (id) do update set
  rotulo = excluded.rotulo, dimensao = excluded.dimensao,
  exclusiva = excluded.exclusiva, sinonimos = excluded.sinonimos,
  termo_busca = excluded.termo_busca, palavras_pt = excluded.palavras_pt,
  palavras_en = excluded.palavras_en, exemplo = excluded.exemplo,
  status = excluded.status, sem_perna_busca = excluded.sem_perna_busca,
  motivo = excluded.motivo, papel = excluded.papel;

with regras(termo_id, padrao) as (
  values
    ('conversacional', '\m(conversacional|figurativ[ao]|novelty print|object print|fruit print|food print|estampa de (frutas|legumes|objetos)|coracoes?|hearts?|estrelas?|stars?|borboletas?|butterfl(y|ies)|tomates?|cherr(y|ies)|cerejas?|morangos?|strawberr(y|ies)|bananas?|abacaxis?|pineapples?|melancias?|watermelons?)\M'),
    ('cintura_media', '\m(cintura media|cos medio|mid[ -](waist|waisted|rise))\M'),
    ('cintura_baixa', '\m(cintura baixa|cos baixo|low[ -](waist|waisted|rise))\M')
)
insert into public.produto_termos(produto_id, termo_id, origem)
select p.id, r.termo_id, 'titulo'
from public.produtos p
cross join regras r
where lower(coalesce(p.titulo, '')) ~ r.padrao
on conflict do nothing;
