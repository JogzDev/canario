-- Os dois alertas CRITICOS do advisor do Supabase apontam para
-- `cobertura_por_celula` e `eventos_da_semana`: views com semantica de
-- SECURITY DEFINER, que rodam com a permissao de quem as criou e por isso
-- ignoram a RLS de quem consulta.
--
-- O `security_invoker = false` NAO foi descuido. A migracao
-- 20260730235132_f4_eventos_da_semana_para_o_app.sql documenta a intencao com
-- todas as letras: "o app... NAO pode ler `produtos`, `marcas` nem
-- `snapshots` -- sao tabelas cruas e ficam fora do alcance da chave
-- publishable". A view era a janela estreita; o definer era o que mantinha a
-- janela funcionando com as tabelas fechadas atras dela.
--
-- POR QUE OS DOIS CONSERTOS OBVIOS ESTAO ERRADOS
-- ==============================================
--
-- (a) Ligar o invoker e nada mais. As tabelas `eventos`, `produtos` e
--     `marcas` tem RLS ligada e ZERO policies -- estado que nega tudo. O
--     efeito seria:
--       - `eventos_da_semana` devolve 0 linhas  -> a aba Explorar esvazia;
--       - `cobertura_por_celula` conta 0 marcas -> `suficiente` vira false em
--         toda celula, e o portao da §8 trava em "ainda nao vi pecas
--         suficientes" PARA SEMPRE.
--     Nenhum dos dois levanta erro. O app so fica mudo, que e exatamente o
--     defeito que estamos tentando matar.
--
-- (b) Ligar o invoker e abrir as tabelas com policy `using (true)` e grant de
--     tabela inteira. Resolve o alerta rasgando a promessa acima: exporia
--     `marcas.justificativa`, `marcas.detalhe_teste`, `produtos.descricao`,
--     `produtos.flag_tipo`, `produtos.ultima_grade` -- nada disso aparece em
--     tela, nada disso e da conta de quem consulta.
--
-- O CAMINHO DAQUI
-- ===============
--
-- Invoker ligado, e a leitura liberada COLUNA A COLUNA: exatamente as colunas
-- que as duas views ja projetam, nem uma a mais. A RLS passa a ser de
-- verdade, e nao contornada; e a lista de colunas abaixo vira o contrato --
-- coluna nova nas tabelas cruas nasce fechada, sem ninguem precisar lembrar.
--
-- O que isso concede de fato: quem tem a chave publishable passa a conseguir
-- ler as MESMAS colunas direto da tabela, e nao so pela view. Para `produtos`
-- isso significa o catalogo inteiro, e nao apenas as pecas que tiveram
-- evento. E dado de vitrine publica, e a regra 3 manda a peca carregar o
-- caminho ate a origem de qualquer jeito -- mas e um alargamento real, e fica
-- registrado aqui como escolha, nao como efeito colateral.

-- 1. Leitura por coluna -----------------------------------------------------

-- `eventos` e derivada e nao tem coluna reservada; ainda assim vai listada,
-- para que uma coluna futura nasca fechada.
grant select (id, produto_id, tipo, data, detalhe)
  on public.eventos to anon, authenticated;

-- De 17 colunas, 6. Ficam fora: id_externo, descricao, categoria_site,
-- imagem_url, primeiro_avistamento, flag_tipo, ultimo_preco_original,
-- ultima_grade, ultimo_snapshot_em.
grant select (id, marca_id, titulo, url, segmento, ultimo_preco_atual)
  on public.produtos to anon, authenticated;

-- De 12 colunas, 5. Ficam fora as notas internas do painel congelado:
-- dominio, plataforma, segmento, justificativa, data_teste, detalhe_teste,
-- congelada_em.
grant select (id, nome, papel, status_teste, ativa)
  on public.marcas to anon, authenticated;

-- 2. Policies de linha ------------------------------------------------------

-- `using (true)`, e nao um recorte: as duas views ja filtram o que mostram
-- (`p.segmento is not null` numa, `ativa`/`papel`/`status_teste` na outra), e
-- um recorte aqui mudaria a CONTA de `marcas_externas`, que alimenta o portao
-- da §8. O estreitamento fica todo na lista de colunas acima, onde nao
-- altera numero nenhum.
create policy "app le eventos ja projetados pela view"
  on public.eventos for select to anon, authenticated using (true);

create policy "app le as colunas de vitrine da peca"
  on public.produtos for select to anon, authenticated using (true);

create policy "app le a identificacao da marca"
  on public.marcas for select to anon, authenticated using (true);

-- 3. As views passam a respeitar a RLS -------------------------------------

alter view public.eventos_da_semana    set (security_invoker = true);
alter view public.cobertura_por_celula set (security_invoker = true);

comment on view public.eventos_da_semana is
  '§27: reposicoes e remarcacoes da semana para a aba Explorar. Respeita RLS (security_invoker); as tabelas cruas atras dela so liberam as colunas que esta view projeta.';

comment on view public.cobertura_por_celula is
  '§8: portao de cobertura por celula. Respeita RLS (security_invoker). `marcas_externas` conta marcas ativas com produto coletado -- se esse numero cair sozinho, o portao fecha e a causa esta em permissao, nao em cobertura.';
