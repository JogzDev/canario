O Codex revisou os commits até f2f8e7e: laboratório SQL 18/18 e 45 testes selecionados do app passaram. As correções anteriores do denominador, materialização, janela e exemplos estão aceitas. Pode seguir com a integração de resumo_de_eventos em Explorar, eliminando a contagem baseada nos 120 exemplos. Trate denominador e taxa de cada marca como opcionais.

Feche também estes pontos na mesma etapa, sem reabrir planejamento/design:

1. Compatibilidade de versões: a orientação anterior de publicar A57 junto com o app era insuficiente, porque usuários continuam com versões antigas instaladas. A57 substitui similares_da_peca e afeta o wrapper já usado por elas. Crie similares_da_peca_v2 e similares_da_peca_amplo_v2, com o comportamento novo e datas, preservando o contrato/comportamento das RPCs antigas. Teste clientes novos e antigos. O rollout será backend v2 primeiro e app consumidor depois, quando o portão de produção for liberado.

2. Frescor: uma observação de ontem não pode esconder outras de quinze dias na mesma resposta. Declare o intervalo das observações, use a mais antiga para evitar chamar o conjunto de atual e mantenha preço/grade contextualizados na mesma data. No resultado vazio, devolva a âncora do painel consultado independentemente dos matches: zero resultados também precisa de período. Sem data conhecida, use texto neutro.

3. Busca editorial: consultas canceladas/antigas não podem limpar nem sobrescrever uma resposta nova. Verifique cancelamento e identidade da consulta antes de alterar estado; cancelamento não deve entrar em retry no cliente Supabase. Cubra com uma consulta A lenta e uma B rápida. Restrinja o silêncio de 404 ao erro específico de função ausente, não a qualquer 404.

4. Cubra o bloco editorial com respostas injetadas/fixtures offline; depender da RPC real não impede teste de interface. Exercite sucesso, vazio, erro e troca rápida de expressão. Inclua fixtures para coortes com idades mistas, zero resultados com painel antigo e compatibilidade v1/v2.

Localizable.xcstrings: preserve mudanças anteriores; inclua apenas os ajustes comprovadamente relacionados ao pacote, sem arrastar o arquivo inteiro por conveniência. pg_trgm continua condicionado à medição e à folga de espaço.

O backup permanece com o Codex, em worktree separada. A tentativa mais recente autenticou e iniciou o dump, mas a conexão foi encerrada durante a exportação de artigos. Isso foi confirmado no Pooler Logs às 22:49:30 de 17/09; a causa original ainda está sendo investigada. O arquivo é parcial, não restaurável, e não há backup de produção validado. Migrations, manutenção e retomada da coleta em produção continuam aguardando essa prova e a revisão do pacote final. Isso não impede a implementação e os testes locais descritos acima.

Siga implementando localmente e volte com commits, testes e pendências concretas. Não precisamos de outra rodada de debate sobre o plano.
