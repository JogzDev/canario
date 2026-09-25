# Regras de trabalho do Canário / Seam

- Responda ao JP sempre em português do Brasil, inclusive progresso, PRs e relatórios.
- Leia `CANARIO.md`, `PENDENCIAS.md` e, se estiver presente na raiz, o arquivo local `HANDOFF_CODEX_SEAM_2_0_2026-09-24.md` antes de continuar a 2.0. O handoff é datado: confira o estado atual.
- Trabalhe em segundo plano por shell, worktrees e `simctl`. Não abra aplicativos ou janelas do JP sem pedido dele.
- Não peça, mostre, copie para chat nem crie senhas, tokens ou chaves. O JP os coloca diretamente no cofre apropriado.
- Não acrescente custo: nenhum plano ou serviço pago e nenhuma rotina no Mac pessoal. O banco gratuito precisa ficar em até 85% de 500 MB para o dia ser verde.
- Não corte o escopo da 2.0 em silêncio. O envio depende de tudo testado no iPhone, com aceite do JP.
- No app, use **Leitura**; nomes de modelos, “Luna”, “Sheary”, GPT e OpenAI são internos.
- Siga o sistema v4 em `app/Canario/Design/Edicao.swift`: bordô nas ações, azul nos dados, uma marcação por tela, foto sobre `#CBCBCB`, Folha com costura e atributos sempre tocáveis.
- Use componentes nativos, Dynamic Type, VoiceOver, cores semânticas e alvos de toque de 44 pt. Mostre capturas reais em pt-BR, claro e escuro; build e teste não comprovam design.
- Antes de mudar regra mensurável, leia o código e meça. Explique ao JP o efeito para quem usa o app. Não misture os segmentos do painel, catálogo candidato e direção internacional.
- Migração de banco exige número livre, laboratório SQL, teste de mutação, contrato Python e conferência byte a byte da versão aplicada. Nunca escreva dado de produção sem teste.
- Mudança de Edge Function exige testes Deno, checagem de tipos e sonda real com uso parcimonioso da cota.
- Em Swift, toda nova frase visível precisa de chave em inglês e tradução pt-BR no `Localizable.xcstrings`. Gere o projeto após criar ou remover arquivo Swift.
- Preserve arquivos não rastreados do JP. Não use `git clean` nem `git stash -u` na raiz.
- Use PRs pequenas e temáticas, CI verde e branch atualizada. Com escopo acordado, o merge está autorizado; nunca use `--admin` para contornar proteção. A PR do app 2.0 só mescla após teste e aceite no iPhone.
- Quando o JP pedir relatório, confira repositório, coletores, frescor do servidor, executores e app, com horário de Brasília; separe falhas do que está de pé.
