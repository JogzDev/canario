# Passagem de bastão — 14/08/2026

> **Correção de 18/08/2026 — leia antes de seguir este guia.**
> O bundle que está em revisão na App Store é **`br.com.canario.ch3.app`**, não
> `com.canario.app`. Existem dois registros na App Store Connect; o `ch3` é o que
> tem perfil de distribuição emitido e o que recebeu o envio. Menções a
> `com.canario.app` abaixo são históricas — **não "corrija" o projeto para elas**,
> ou o upload vai para o app errado.

Este documento registra o estado do Canário/DataDrobe ao fim da sessão de 14/08.
Leia também `CANARIO.md` e `PENDENCIAS.md`: este arquivo não os substitui.

## Situação honesta agora

O app **não está pronto para envio à App Store** e o analisador visual ainda não
está aprovado. Há bastante trabalho integrado e testado no repositório, mas dois
resultados de hoje precisam de correção antes de qualquer conclusão otimista:

1. O benchmark de 300 imagens da Luna terminou tecnicamente verde, porém sua
   métrica é inválida: o recorte de fundo compatível com o Mac i7 produziu quase
   sempre imagens pretas ou somente uma parte do rosto. A Luna devolveu
   `not_visible` de forma coerente. Os **1,3%** de concordância não medem a
   qualidade do modelo; não usar esse número para decidir nada.
2. O pipeline diário teve VTEX e Shopify verdes, mas os jobs editorial, saúde e
   recuperação falharam antes de criar steps. Isso indica um problema de
   orquestração/configuração do workflow, ainda sem causa provada; não culpar os
   dados nem enfraquecer o portão de saúde sem diagnóstico.

## Commits e árvore de trabalho

- Repositório: `JogzDev/canario`, branch `main`.
- Último commit do trabalho: `d2926a4 Prepara revisao cega do holdout de 300`.
- Há uma alteração **do usuário** não commitada em
  `app/Canario.xcodeproj/project.pbxproj`. Preserve-a: não usar `reset`,
  `checkout` ou `stash` nela e não a colocar em commits deste pacote.
- CI conhecida verde em `d2926a4`: testes Swift/Python.

## O que foi implementado hoje

### Analisador visual e privacidade

- Fotos importadas passam por escolha de alvo, recorte/zoom e dica textual do
  usuário antes da análise.
- No iPhone, a peça selecionada é isolada com Vision; o original é preservado
  como opção segura quando o recorte não for confiável.
- A cor ignora pixels transparentes; antes transparência podia virar preto.
- O app não contém chave OpenAI. A chamada de Luna foi estruturada numa Supabase
  Edge Function (`supabase/functions/analisar-peca/index.ts`) com saída
  tipada/restrita à taxonomia, `store=false` e limites de custo.
- `REMOTE_ANALYSIS_ENABLED=NO` é o padrão proposital. Não ativar até validar a
  Edge Function com os secrets de produção e num iPhone.
- `PrivacyInfo.xcprivacy` foi atualizado para o fluxo de fotos/análise.

### Benchmark Luna

- Script: `ferramentas/avaliar_luna.py`.
- Prompt atual: `alvo-estrutura-v5` (alvo -> estrutura -> categoria), não pede
  para inventar uma categoria fora da taxonomia.
- Calibração humana de 24 imagens anterior: categoria 20/24 (83,3%), cor 22/24
  (91,7%). Isso foi antes do defeito do recorte do i7.
- Workflow 300: run `31838225739`, verde, custo US$ 0,136137, 1141 s.
- Artefato privado: `luna-respostas-300-run-31838225739`, retenção de 3 dias.
  Contém JSONL com resposta, uso, latência e `response_id`, sem chave.
- A revisão humana cega já está preparada no workflow
  `OpenAI — preparar revisao cega do Luna` (id `331594251`), mas **não disparar**
  para esse resultado inválido. Só usar após refazer uma amostra válida.

### Inglês/DataDrobe e App Store

- Nome de exibição: `DataDrobe`; iPhone-only; versão 1.0 build 1.
- Strings visíveis principais foram convertidas para inglês; IDs internos seguem
  em português onde apropriado.
- Testes locais concluídos: 143 Swift verdes; build de simulador verde; testes
  Python verdes antes do último workflow.
- Existe archive em `/tmp/DataDrobe.xcarchive`, mas ele está assinado para
  Development, não para App Store. A conta atual da Apple não possui autorização
  para criar provisioning profile de distribuição para `com.canario.app`.
  Account Holder/Admin deve conceder acesso a Certificates, Identifiers & Profiles
  ou criar o profile.
- Guias: `RELEASE_DATADROBE.md` e `APP_STORE_READINESS_14-08-2026.md`.

### Similar Pieces, imagens e links

- Auditoria criada com 262 URLs: `ferramentas/auditar_links_app.py`,
  `AUDITORIA_LINKS_APP.md`, `anexos/auditoria_links_app.json`.
- Achados: links históricos mortos e URLs Maria Filó apontando para VTEX admin.
- Coletor foi ajustado para URL pública Maria Filó; há migração pendente para
  corrigir históricos e ocultar similares esgotados/mortos.

### Banco e pipeline

- Limpeza segura anterior liberou aproximadamente 16,8 MB. Banco ficou em
  467.963.027 bytes (~446,3 MiB), 93,6% do plano de 0,5 GB; o portão de 96%
  continua ativo.
- O coletor VTEX agora diferencia HTTP, ausência de `Resources` e zero explícito,
  para não produzir falso “zero sem explicação”.
- Pipeline problemático: run `31837815669`.
  - `varejo-vtex / coletar`: sucesso.
  - `varejo-shopify / coletar`: sucesso.
  - `editorial / coletar`, `saude-inicial`, `recuperar-busca`, `saude`: falharam
    sem steps/logs, em segundos.
  - `busca`, `recuperar-shopify`, `motor`: skipped por dependência.

## Próxima ordem de trabalho (não pular)

### P0 — corrigir antes de gastar outro crédito Luna

1. Reproduzir localmente o problema de `ferramentas/segmentar_fundo.swift` com
   imagens do cache de treino e salvar PNG de entrada/saída para inspeção visual.
2. Corrigir a máscara de saliência do macOS i7. O provável defeito é a conversão
   / orientação / interpretação do pixel buffer, não o modelo Luna. O fallback
   não pode ser “mandar a imagem crua” silenciosamente: deve falhar fechado ou
   mostrar que houve fallback e exigir aprovação.
3. Criar teste de regressão visual/métrico: saída precisa ter alfa, uma área de
   peça razoável e não pode ser quase preta/transparente. Testar pelo menos 24
   imagens distribuídas pelas categorias.
4. Rodar novamente as mesmas 24 com o prompt v5. Somente se categoria **e** cor
   chegarem a 80% ou mais, repetir 300. Não reutilizar o 1,3%.
5. Após 300 válido, disparar a revisão cega humana (`331594251`) e chamar o
   resultado de “concordância com rótulo fraco do catálogo” até três pessoas
   revisarem as imagens.

### P0 — colocar Luna em funcionamento no app

1. No dashboard Supabase, inserir secrets da Edge Function:
   - `OPENAI_API_KEY`: a chave do projeto OpenAI (não colocar no Git/Swift/chat).
   - `AI_RATE_LIMIT_SALT`: valor aleatório com >=24 caracteres.
2. Testar a função sem inferência e depois com uma imagem de roupa.
3. Só então definir `REMOTE_ANALYSIS_ENABLED=YES` no `Config.xcconfig` local,
   compilar e validar no iPhone (foto, fototeca e câmera).
4. Confirmar que o texto do app diz “analysing your garment”, não promete medidas
   físicas ou Clothing DNA se não estiver medindo.

### P0 — pipeline diário

1. Examinar `.github/workflows/pipeline-diario.yml` e os workflows reutilizáveis
   chamados depois de Shopify; comparar a condição/necessidade dos jobs que
   falharam sem steps.
2. Verificar nas mensagens do GitHub UI do job `editorial / coletar` se há erro de
   referência a workflow, permissão, concorrência ou runner. `gh run --log` não
   terá conteúdo porque nenhum step iniciou.
3. Corrigir a causa, cobrir com teste de workflow se possível, push e rodar um
   único `workflow_dispatch`. Não mascarar com `continue-on-error`.

### P1 — migrações pendentes no Supabase (requerem decisão explícita do JP)

- **P6**: limpa contadores de rate-limit com mais de sete dias (dados efêmeros)
  e cria a proteção de uso da Edge Function.
- **P7**: corrige URLs históricas de Maria Filó, anula URLs mortas de eventos e
  filtra Similar Pieces esgotadas/sem URL válida.
- Ambas já existem no repositório, mas não foram aplicadas ao projeto de produção
  porque alteram dados. Antes de aplicar, pedir confirmação explícita: “pode
  aplicar P6 e P7 no Supabase”.

### P1 — publicação

1. Conseguir a permissão/perfil Apple de distribuição.
2. Com Xcode em `Any iOS Device (arm64)`: Product > Archive > Distribute App >
   App Store Connect > Upload.
3. Preencher com Davi/JP: URLs de Privacy e Support, logo final, descrição,
   screenshots, App Privacy, age rating e review notes.
4. Usar primeiro TestFlight interno para validar o mesmo build que seguirá para
   revisão. Não há necessidade de “subir direto sem TestFlight”; o upload é o
   mesmo, e TestFlight reduz risco.

### P2 — UX/produto que segue pendente

- Terminar telas Add/Form/resultado/Closet/Analytics/Search e instruções;
  consolidar inglês e SF Pro.
- Trocar menu lateral por padrão iOS acordado (provável sheet) e corrigir áreas
  de toque/safe area/tab bar.
- Refinar taxonomia `blusa_top`, possivelmente dividir camiseta/blusa/top com
  definições e nova calibração humana; não mudar rótulos antes de documentar
  impacto em todos os termos/séries.
- Ajustar Similar Pieces para relevância real, não apenas interseção crua de
  atributos; continuar auditoria de destino/estoque.
- Corrigir stale data/editorial, explicações de tendência, gráficos com séries
  assimétricas, zoom/filtro de período e texto “desvios” user-friendly.
- Melhorar extração/preview editorial e filtro semântico para excluir matéria sem
  relação com moda (ex.: “camisa 7” do Vini Jr.).
- Melhorar liquid glass usando materiais SwiftUI nativos e reduzir textos de
  placeholder; não sacrificar conteúdo para “parecer mais simples”.

## Invariantes importantes

- Nenhuma imagem do usuário deve ir para análise/cor sem primeiro tentar
  isolar/confirmar a peça principal; o usuário precisa poder corrigir alvo,
  recortar/zoom ou informar o alvo.
- Chave OpenAI nunca no binário, Git, logs ou chat.
- Câmera, fototeca e arquivo convergem no mesmo leitor, em memória; não criar
  cópia de disco casualmente.
- Hotlink não é cópia: manter imagem na origem e fallback visual.
- Regra de coleta: 1 req/s por domínio, User-Agent identificável, robots, backoff
  verdadeiro em 429; sem proxy/rotação.
- PostgREST pagina em 1000 linhas sem avisar; sempre paginar.
- Preservar recorte `(categoria, termo_id)` em joins de raridade.

## Arquivos de referência

- `CANARIO.md`, `PENDENCIAS.md`
- `DEPLOY_ANALISE_VISUAL.md`
- `RELEASE_DATADROBE.md`
- `APP_STORE_READINESS_14-08-2026.md`
- `AUDITORIA_LINKS_APP.md`
- `ferramentas/avaliar_luna.py`
- `ferramentas/segmentar_fundo.swift`
- `supabase/functions/analisar-peca/index.ts`
- `.github/workflows/avaliar-luna.yml`
- `.github/workflows/preparar-revisao-luna.yml`
- `.github/workflows/pipeline-diario.yml`
