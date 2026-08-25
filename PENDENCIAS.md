# Pendências do DataDrobe 1.2

**Atualizado em 24/08/2026 às 21:51 BRT.** Esta lista substitui a triagem de
20/08, que ainda chamava de pendente telas e funções já entregues.

## Bloqueio externo — depende do Figma

1. **Pacote visual do Figma.** Aplicar as novas telas e os assets finais. A
   hierarquia do Market panel e a redução de texto em “Which item” ficam nesta
   etapa para não desenhar duas vezes a mesma interface.

## Fechamento de release — depois do Figma

- Repetir o login Google no iPhone com o novo SDK nativo. O cliente OAuth iOS,
  os IDs aceitos no Supabase, o callback e o build já estão verdes; esta prova
  confirma que o usuário vê Google/DataDrobe sem o domínio interno da Supabase.
- Rodar a regressão visual no iPhone e a suíte completa.
- Gerar Archive Release 1.2, validar assinatura/entitlements, enviar ao
  TestFlight e repetir os fluxos críticos no binário distribuído.
- Atualizar capturas e metadata da App Store com as telas finais; só então
  submeter a 1.2 para revisão.

## Validações posteriores, não bloqueadoras da implementação

- **Calibração Luna somente com amostra nova.** A taxonomia expandida da 1.2
  deu 57/72 em categoria e cor (79,2%) nas mesmas 24 imagens. O conjunto não
  será repetido nem usado para perseguir décimos: cinco casos difíceis ficam
  registrados como erro conhecido. Um futuro holdout usa imagens novas e
  orçamento explícito. Isso não bloqueia o Figma nem os fluxos manuais.
- **Cold launch e artefato rosa no iOS 18.7.** Exigem o iPhone 15 no qual foram
  relatados. Build, simulador iOS 26.2 e os fluxos automatizados estão verdes.
- **Novos veículos editoriais.** ELLE US, Harper's Bazaar US, Marie Claire US e
  Glamour US tiveram feeds femininos públicos confirmados em 24/08. Não entram
  ainda porque oferecem só a cauda recente: adicioná-los sem backfill criaria
  outro degrau falso no denominador histórico. A entrada exige estratégia de
  arquivo uniforme e recomputo, não apenas uma linha no CSV.
- **Marcas brasileiras Tier A.** Permanecem candidatas para a próxima virada de
  temporada. A regra 5 não foi quebrada; cinco marcas internacionais já entraram
  em painel separado de direção.

## Entregue na 1.2 antes do Figma

- Apple, Google e e-mail/senha validados fisicamente no iPhone pelo JP em 24/08.
  O fluxo Google hospedado foi depois substituído pelo SDK oficial nativo para
  não expor o domínio interno da Supabase; integração e build estão verdes.
- E-mail transacional gratuito validado de ponta a ponta em 24/08: Supabase →
  Brevo → Gmail, com envio, entrega e primeira abertura registrados. O chamado
  **#5525910** recebeu a confirmação e foi respondido como resolvido; usuários
  técnicos de teste foram apagados.
- Login opcional com Apple, Google e e-mail/senha; recuperação, logout, exclusão,
  Keychain, RLS e sincronização offline-first do Closet.
- Banco estabilizado no plano gratuito: estado volátil em tabela estreita,
  retenção segura de snapshots e recuperação do inchaço sem apagar séries.
- Um botão de compartilhar com bottom sheet, links autocontidos, Universal Link,
  fallback da App Store, card social e CSV de uma peça, seleção ou Closet inteiro,
  com opção de incluir leitura de mercado e sua data.
- Nome visível/editável, busca e filtro local do Closet por favorito e atributos.
- Depois de Fill the Info, Clothing Details abre em tela cheia; Add to Closet
  fica no canto superior esquerdo com instrução explícita. A busca do Closet é
  o drawer recolhível nativo, o canto esquerdo virou menu de três pontos e o
  Compare passou para Weekly Trends.
- Similares com foto no alto do relatório, polo como camisa, relaxamento declarado
  por cobertura e fallback sem abandonar categoria nem motivo de estampa.
- Importação por URL de produto; Farm/tomate funciona sem visão quando o produto
  já está no painel. Motivos visuais de frutas e couro foram adicionados.
- Editorial refiltrado para feminino sem apagar o arquivo, fontes clicáveis,
  contagens cruas e zero honesto no lugar do “−100%” enganoso.
- Editorial dos atributos acessível a partir da peça salva.
- Painel `direcao_intl` isolado com Doen, Rouje, Staud, Faithfull the Brand e
  With Jean: 4.956 itens visitados, 3.768 produtos elegíveis e zero produto das
  cinco marcas fora do segmento, comprovados pelo portão de produção.
- 239 testes Swift, portões Python e sete fluxos de UI (incluindo o filtro do
  Closet) verdes no ambiente local.
