-- 0012 -- Cobertura da perna de busca, para a fila por defasagem.
--
-- O coletor precisava saber ha quanto tempo a serie de cada termo nao anda, e
-- resolvia no cliente puxando `series_semanais` inteira. Nao funciona: o
-- PostgREST corta em 1000 linhas por resposta e `selecionar()` nao pagina,
-- entao o coletor concluiu "36 termos sem serie nenhuma" quando o numero real
-- era QUATRO -- e a fila saiu ordenada errada na primeira execucao.
--
-- §33: quem sabe responder isso em uma linha e o banco.
create or replace view public.cobertura_da_busca as
select t.id as termo_id,
       max(s.semana) as ultima_semana,
       count(s.*)::integer as pontos,
       (current_date - max(s.semana)) as dias_de_atraso
from public.termos t
left join public.series_semanais s
  on s.termo_id = t.id and s.fonte = 'busca'
group by t.id;

comment on view public.cobertura_da_busca is
  'Ultima semana e volume da perna de busca por termo. O coletor ordena a '
  'fila por esta defasagem: sem serie na frente, mais atrasado depois.';

revoke all on public.cobertura_da_busca from anon, authenticated;
grant select on public.cobertura_da_busca to service_role;
