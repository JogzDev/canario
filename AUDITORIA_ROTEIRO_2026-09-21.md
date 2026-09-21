# Auditoria do roteiro — 21/09/2026

Esta reconciliação compara:

- `PLANO_FECHADO_2026-09-17.md`;
- o inventário pós-Challenge de 70 itens em `ROADMAP_PRODUTO.md`, preservado na
  branch `codex/produto-pos-challenge`;
- `PENDENCIAS.md`, `ESTADO.md` e `AUDITORIA_SEGURANCA_2026-09-21.md` da `main`;
- o código e o histórico Git disponíveis em 21/09;
- o estado remoto do GitHub Actions e das pull requests.

Ela não chama uma intenção de entrega e não usa documento antigo como prova de
produção. Onde a aceitação depende de observação, aparelho, licença, pessoa ou
publicação, o item continua aberto.

## Correção estrutural encontrada

O trabalho estava dividido em duas linhas que nunca haviam sido reunidas:

- a `main` continha recuperação do banco, A57/A58, operação gerenciada e
  endurecimento de segurança;
- `codex/produto-pos-challenge` continha A53–A56, português/inglês, cor
  constante, correções de interface, fundação privada do radar e o roteiro de
  70 itens.

Logo, nenhuma das duas isoladamente representava “tudo novo”. A branch local
`codex/integracao-app-2` foi criada a partir da `main` e recebeu o pacote do app
A53–A56, as correções posteriores do Xcode 27 e as correções de localização,
preservando A57/A58. Ela é o primeiro candidato correto para teste visual; não
foi enviada nem mesclada.

## Plano fechado de 17/09

| Etapa | Estado em 21/09 | O que ainda falta |
|---|---|---|
| 0. Preservar e isolar | concluída | Manter artefatos e branches até a integração final |
| 1. Recuperar capacidade | recuperação concluída; estabilidade em observação | Completar sete ciclos válidos; hoje são 2/7 |
| 2. Continuidade da `main` | executores gerenciados e Xcode Cloud entregues | Alerta verdadeiramente independente para execução agendada ausente; fechar atualizações de dependência com CI |
| 3. Significado e busca específica | backend e consumidor implementados | Regressão integrada no aparelho; síntese específica controlada continua na etapa 6 |
| 4. Restaurar coleta com medição | retomada e capacidade final automatizadas | Cinco ciclos válidos; o evento de 21/09 não existiu e não conta |
| 5. v4/2.0 por percurso | núcleo funcional existe; integração local criada | Design final, logo/nome, regressão visual e de acessibilidade no aparelho, capturas e TestFlight |
| 6. Interpretação controlada | não concluída | Corpus permitido, afirmações verificadas, verificador, abstensão, avaliação cega e teto de custo |
| 7. Foto específica | parcialmente implementada | Benchmark novo de 30–50 fotos, comparação local/Luna/manual, holdout independente e decisão de produto |
| 8. Beta, transferência e portfólio | parcial | Beta da 2.0, teste distribuído, documentação/case final e publicação decidida |

## O que está comprovadamente entregue

- Backup e restauração isolada; recuperação de capacidade; retenção e escritas
  diferenciais; banco medido em 73,5% após o ciclo de 20/09.
- A57/A58 publicadas com RPCs versionadas, frescor declarado, agregação correta
  de eventos e busca editorial específica.
- Coleta, saúde, motor, catálogo candidato, capacidade e CI sem depender do Mac
  pessoal; o supervisor e o runner residenciais foram removidos.
- Login opcional, RLS, Closet offline-first, miniaturas privadas, exclusão de
  conta, HTTPS no cliente, rate limit e inventário de concessões públicas.
- A48/A49 e Luna v11; cor com prioridade no Closet.
- Na integração local: A53–A56, interface em português/inglês, substrato neutro,
  Estúdio, captura de cor constante, correções do Xcode 27 e A57/A58 juntas.
- A integração local compila para simulador, tem 338 testes Swift verdes e
  catálogo com 554 chaves, zero ausente e zero sem português.

## O que não foi feito — e não pode desaparecer da fila

### Operação e segurança

- A janela está em 2/7. A ausência de run em 21/09 não é um marco verde.
- Falta um alerta de “o agendamento nem nasceu” que seja independente da mesma
  agenda que pode falhar.
- Permanecem seis controles parciais: secret scanning da plataforma, proteção
  adicional do refresh token Apple, política de revisão/admin, App Attest ou
  DeviceCheck, auditoria de headers na 2.0 publicada e scan automatizado
  equivalente para Swift/Deno.
- PRs Dependabot #37 e #38 estão abertas e ainda precisam de compatibilidade e
  CI antes de qualquer merge.

### Mercado, taxonomia e virada

- A virada metodológica/temporada **não aconteceu**.
- `papel=grupo` ainda precisa ser retirado do mercado externo por método
  versionado.
- Categoria exclusiva, malharia/suéter, `blusa_top`/camiseta, estampa, cintura
  e tecido precisam de rubrica, amostra, precedência e comparação.
- O viés por tamanho de marca ainda precisa de decisão anterior ao resultado.
- As 13 candidatas não foram promovidas ao painel medido.
- Loja 3, Mondepars e as demais novas marcas foram sondadas, não adicionadas ao
  painel. Malwee já existe no catálogo candidato, não na coorte medida.
- O motor de similares ainda precisa da calibração por dimensão, OR dentro da
  dimensão, cor principal, relaxamento e avaliação visual.
- A recomposição editorial feminina de agosto existe, mas a revisão nova de
  fontes, direitos, denominadores e rajadas não foi concluída.
- A taxonomia recebeu A48/A49; isso não equivale à virada coordenada.

### Radar, Luna e validação

- A51/A52 e as ferramentas do radar existem apenas na linha de produto e não
  equivalem a um radar publicável.
- O P1 provou a parte transacional; falta atravessar materializador, parser e
  consolidador reais.
- F1 continua sendo o bloqueio: nenhuma fonte externa nova foi admitida com
  direitos de IA, exibição e retenção comprovados.
- P2–P7 do radar não estão concluídos: dados duráveis, conceitos versionados,
  retirada, revisão humana real, afirmações, Luna avaliada, conversa,
  experiência privada, piloto e liberação.
- A busca encontra a matéria específica; a síntese específica da peça e a
  leitura específica da foto, sustentadas apenas por evidência, não estão
  fechadas.
- O holdout novo da Luna e o benchmark de foto/cor ainda dependem de imagens
  novas e protocolo congelado.

### Produto e lançamento

- O visual herdado é base, não o design final da 2.0.
- Nome, logo e identidade final continuam deliberadamente abertos.
- Falta regressão visual no iPhone da integração atual, além de Dynamic Type,
  VoiceOver, mínimo suportado, rede lenta/offline, memória e performance onde
  o código mudou.
- Capturas, Archive, TestFlight e submissão pertencem ao final; o Archive 1.2
  antigo não é candidato à 2.0.
- Android, billing, organizações, painel administrativo, notificações e offline
  completo continuam condicionados à utilidade e não devem furar a ordem.

## Ordem executável a partir de agora

1. **Fechar a integração do app.** Teste visual e funcional da branch
   `codex/integracao-app-2` no simulador e no iPhone; corrigir regressões; rodar
   a suíte combinada completa. Só depois propor PR para a `main`.
2. **Manter a observação em paralelo.** Os sete dias bloqueiam publicação e
   mudanças de produção, não bloqueiam código local, design, testes ou método
   em laboratório.
3. **Fechar dívidas determinísticas do app.** Parser de preço, callbacks da
   captura, limites de imagem/memória, tradução e estados de erro podem avançar
   sem tocar produção.
4. **Preparar a virada em laboratório.** Congelar baseline, escrever contrato
   versionado, rubrica de categoria e comparações de peso/coorte. Nenhuma
   recomputação pública antes do aceite e da janela verde.
5. **Resolver F1 e completar o P1 real.** Primeiro direitos e método das fontes;
   em seguida a fixture atravessa os componentes reais. Não construir P2–P7
   para um corpus cuja utilização ainda não foi autorizada.
6. **Calibrar similares e foto com datasets congelados.** Depois da taxonomia e
   do método, para não avaliar um alvo que muda no meio do teste.
7. **Fechar design/nome/logo e lançar a 2.0.** Regressão física, capturas,
   TestFlight, política/headers e publicação explícita por último.

## Próximo portão

O próximo resultado verificável é a branch integrada rodando no simulador e no
iPhone sem regressão crítica. A observação diária continua separada. Nenhuma
marca, taxonomia, série histórica ou migration de produção será alterada para
obter esse resultado.
