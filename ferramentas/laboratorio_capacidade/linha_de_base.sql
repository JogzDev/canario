-- Linha de base: o defeito, medido com as funções que estão em produção.
--
-- Se estas asserções deixarem de passar, é o teste da P22 que perdeu o poder
-- de distinguir o antes do depois -- e aí o verde de `assercoes.sql` não
-- prova mais nada. Cada bloco é uma transação: o motor chama cada função uma
-- vez por publicação.

do $$
begin
  perform public.computar_serie_varejo();
end $$;

do $$
declare u bigint; begin
  perform lab.fotografar();
  u := lab.updates();
  perform public.computar_serie_varejo();
  assert lab.updates() - u = 9 and lab.movidas_sem_mudar() = 9,
    'o varejo antigo deveria reescrever as 9 linhas sem mudar nada; reescreveu '
      || (lab.updates() - u);
  raise notice 'base 1  varejo antigo: 9 de 9 linhas reescritas sem mudanca';
end $$;

do $$
begin
  perform lab.semear_editorial();
  perform public.computar_serie_editorial();
end $$;

do $$
declare u bigint; begin
  perform lab.fotografar();
  u := lab.updates();
  perform public.computar_serie_editorial();
  assert lab.updates() - u = 10 and lab.movidas_sem_mudar() = 10,
    'o editorial antigo deveria reescrever as 10 linhas normalizaveis; reescreveu '
      || (lab.updates() - u);
  raise notice 'base 2  editorial antigo: 10 de 10 linhas reescritas sem mudanca';
end $$;

do $$
begin
  perform lab.semear_busca();
  perform public.computar_z();
end $$;

do $$
declare u bigint; total int; begin
  select count(*) into total from public.series_semanais;
  perform lab.fotografar();
  u := lab.updates();
  perform public.computar_z();
  assert lab.updates() - u = total and lab.movidas_sem_mudar() = total,
    'computar_z antigo deveria reescrever as ' || total || ' linhas; reescreveu '
      || (lab.updates() - u);
  raise notice 'base 3  computar_z antigo: % de % linhas reescritas sem mudanca',
    total, total;
end $$;

do $$
begin
  perform public.computar_indice();
end $$;

do $$
declare u bigint; total int; begin
  select count(*) into total from public.indices_semanais;
  assert total > 0, 'a base precisa produzir indices para o teste da P25';
  perform lab.fotografar_indices();
  u := lab.updates_indices();
  perform public.computar_indice();
  assert lab.updates_indices() - u = total
     and lab.indices_movidos_sem_mudar() = total,
    'computar_indice antigo deveria reescrever os ' || total
      || ' indices sem mudar nada; reescreveu ' || (lab.updates_indices() - u);
  raise notice 'base 4  computar_indice antigo: % de % linhas reescritas sem mudanca',
    total, total;
end $$;
