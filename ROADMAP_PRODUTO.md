# DataDrobe — roteiro de produto pós-Challenge

**Data do inventário: 16/09/2026.** Fila executável da evolução após o Challenge 3.
Baseline inspecionada da 1.3: `d85fbaa`; trabalho novo na branch
`codex/produto-pos-challenge`. O usuário informou que a entrega do Challenge terminou.

Este documento registra **o que construir e como aceitar cada entrega**, não o
estado atual dos serviços. Estado operacional, incidentes e medições atuais ficam
em [`ESTADO.md`](ESTADO.md). Resultados de um teste devem carregar commit, comando,
data e alcance da prova; uma intenção neste roteiro não comprova implementação.

## 1. Objetivo e limites

Transformar o app em um produto útil e em um case de portfólio demonstrável:
observar o mercado de moda feminina, investigar sinais com evidências e aplicar
essa leitura à própria peça ou coleção. Luna organiza e explica; números,
direitos, fontes, cobertura e limites continuam verificáveis.

O pedido de 16/09 reabre a construção planejada além do anti-escopo acadêmico:
design, Android, oferta comercial, capacidades de plataforma e ampliação do
radar podem entrar na fila. Isso **não** autoriza por si só contratar serviços,
fazer inferências pagas, publicar uma versão, realizar uma migração de produção,
apagar história, contornar restrições de fontes ou retirar colaboradores.

- Mudanças locais e testes isolados avançam sem transformar cada passo em pedido
  de autorização. Custos, publicação e alterações destrutivas têm decisão própria.
- O código da versão publicada e suas séries não são laboratório. Operação pode
  ser reparada no escopo pedido, preservando dados e compatibilidade.
- Não se promete venda, adoção, disponibilidade de API, precisão ou escala sem
  prova. Indisponibilidade de produto não é venda; ausência de coleta não é queda
  de interesse; uma fonte encontrada não é uma fonte autorizada.
- Não haverá outra reescrita integral de blueprint a cada sessão. Ajustes entram
  nos IDs abaixo; decisões estruturais mudam por evidência ou novo objetivo.

## 2. Legenda e forma de trabalhar

**Dificuldade relativa, não estimativa de calendário:**

| Grau | Interpretação |
|---|---|
| XS | Correção localizada, baixo acoplamento e prova direta |
| S | Mudança pequena com testes ou revisão de conteúdo |
| M | Vários componentes ou comportamento de integração |
| L | Mudança de domínio, migração, avaliação ou experiência completa |
| XL | Frente de produto/plataforma com várias entregas e decisões próprias |

**Urgência:** `U0` restaura operação ou protege dados; `U1` fecha base e defeitos
atuais; `U2` constrói o produto seguinte; `U3` amplia após dependências verificadas.
Esses códigos não são os pacotes `P1–P7` da blueprint.

**Estados usados:** `aberto` = precisa ser feito ou verificado;
`condicionado` = depende de decisão, material, direito ou capacidade externa;
`implementado local` = código encontrado, sem presumir deploy ou aceite completo.
Ao fechar um item, acrescentar a evidência de aceite; não trocar o estado para
concluído com base apenas em compilação, relato antigo ou quantidade de testes.

IDs são estáveis e não serão renumerados. Cada execução escolhe uma fatia que
termina com código/documento, teste, limitação e próximo passo. Dificuldade não
é prioridade: um incidente difícil não espera todas as tarefas fáceis.

## 3. Base já existente — aproveitar, não reconstruir

O inventário encontrou estas implementações. Elas não anulam as lacunas da fila:

| Base | Estado | Limite da evidência |
|---|---|---|
| Conta opcional Apple/Google/e-mail, Closet local e sincronização | implementado local | Revalidar serviços e fluxos quando a evolução tocar autenticação/dados |
| Revogação Apple em `excluir-conta` e armazenamento do refresh token | implementado local | Código não comprova secrets, deploy ou revogação real no ambiente atual |
| Compartilhamento, links universais, card social e CSV | implementado local | Evoluções precisam preservar conteúdo, privacidade e desempenho |
| Retenção de snapshots, estado estreito e atualização diferencial do motor | implementado local | Medições de agosto não descrevem a capacidade de setembro |
| Catálogo candidato separado do painel medido | implementado local | Promovê-lo muda método e não é expansão transparente |
| Studio/Estúdio, substrato neutro e estrutura PT/EN | implementado local | Ainda há traduções e formatações que passam pelos portões sem funcionar |
| Cor constante e par de imagens ambiental/medição | implementado local | Integração remota, ordem de callbacks e calibração ainda abertas |
| A51/A52, governança, Scout, parser/materializador e revisão cega | implementado local | Não significam fonte externa admitida nem edição publicável |
| Laboratório PostgreSQL e testes transacionais | implementado local | P1 parcial: fixture não atravessa o parser e o consolidador reais |

[`EXECUCAO_1_3.md`](EXECUCAO_1_3.md) reconhece o P1 parcial. Os rótulos de
“fechado” em `FILA_DO_DEPOIS.md` e `ORDEM_PROPOSTA_1_3.md` não prevalecem sobre
essa lacuna. `ESTADO.md`, fichas de release e relatórios antigos contêm fotografias
datadas: não reabrir como pendência atual um certificado ou envio já resolvido.

## 4. Inventário executável — 62 itens

### 4.1 Operação, capacidade e continuidade

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| OP-01 | Diagnosticar e recuperar pipelines diários | M / U0 | aberto | Acesso de leitura ao Actions e runners | Causa atual registrada; execução completa real observada; próxima execução agendada confirmada ou limitação explícita; CI verde não substitui coleta |
| OP-02 | Alerta independente de “job não começou” | M / U0 | aberto | OP-01; executor/observador separado | Simular runner indisponível e job ausente; alerta acionável sem depender da máquina caída; incidente deduplicado e recuperação comunicada |
| OP-03 | Saúde de fonte, cobertura e idade do corpus | M / U0 | aberto | OP-01 | Distinguir falha, atraso, cadência, zero verdadeiro, fonte bloqueada e cobertura insuficiente; regra de publicação testada por cenário |
| OP-04 | Medir capacidade real: banco, índices, inchaço, Storage e tráfego | S / U0 | aberto | Consultas somente leitura no ambiente certo | Relatório datado em bytes, crescimento e consultas lentas; identificar qual quota/recurso limita; não usar 81,5% de agosto como medição atual |
| OP-05 | Ajustar retenção e escrita pela causa medida | M / U0 | condicionado | OP-04; plano de retenção e alvos | Dry-run e impacto metodológico; não podar séries; demonstrar crescimento controlado sem reescrita inútil; remoção material só com decisão própria |
| OP-06 | Backup e restauração ensaiados | L / U1 | aberto | Inventário de banco, objetos e configuração | Restaurar em destino isolado; verificar schema, contagens, amostra, permissões e vínculos de miniaturas; registrar RPO/RTO medidos e segredos fora do artefato |
| OP-07 | Decidir permanência ou migração do Supabase | L / U1 | condicionado | OP-04, OP-06 | Comparar opções pelo gargalo e custo total; incluir Auth, RLS, RPC, Storage e funções; decisão escrita com critérios de saída, não só preço de PostgreSQL |
| OP-08 | Executar eventual migração com compatibilidade | XL / U3 | condicionado | OP-07; destino e custo aprovados | Ensaio, paridade, identidade de usuários, dados/objetos, cutover e rollback testados; app publicado continua suportado; nenhuma troca cega de URL |
| OP-09 | Tornar CI e execução reproduzíveis e isolados | M / U1 | aberto | Inventário de workflows/runners | Dependências fixadas, cache, permissões mínimas, secrets só no ambiente correto, jobs sem dependência acidental da sessão pessoal; fila e cancelamentos testados |

Origem: `PENDENCIAS.md` operacional; `ESTADO.md` banco/pipeline; `FILA_DO_DEPOIS.md`
§2.5; `RUNNER.md`; blueprint §16; incidente relatado pelo JP em 16/09.

### 4.2 Defeitos e qualidade do app atual

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| APP-01 | Parser de preço correto em PT/EN | S / U1 | aberto | Convenção de entrada explícita | Testar `79,90`, `79.90`, milhares, vazio e ambiguidade; valor entendido conferível; mudar idioma não muda moeda nem multiplica preço |
| APP-02 | Tradução e formatação integral | S / U1 | aberto | Catálogo existente | Remarcações, busca sem cobertura, privacidade, datas e atributos respeitam idioma do app; testar app PT/sistema EN e inverso |
| APP-03 | Portões de tradução sem falsos negativos conhecidos | S / U1 | aberto | APP-02 | Casos reais inseridos como testes negativos; exceções limitadas ao parâmetro/contexto correto; tradução existente mas não usada também detectada por teste |
| APP-04 | Cor corrigida chegar à sugestão final da Luna | M / U1 | aberto | Contrato entre foto exibida, alvo e imagem analisada | Duas imagens deliberadamente diferentes provam qual sustenta a cor final; natural continua exibição; não reduzir estampas a uma mediana sem avaliação |
| APP-05 | Captura robusta à ordem dos callbacks | M / U1 | aberto | Par de captura existente | Ambas as ordens de chegada, imagem ausente, erro, cancelamento e callback tardio; finalizar uma única vez ao término da captura correta |
| APP-06 | Preservar avisos e explicar perda da medição | XS / U1 | aberto | Estado de captura/recorte | Aviso de baixa confiança não é sobrescrito; recorte manual e isolamento explicam fallback; voltar/cancelar não reaproveita medição antiga |
| APP-07 | Controlar resolução e memória da normalização | S / U1 | aberto | Captura e renderização | Escala explícita, limite de pixels e teste em imagens grandes; perfil de memória sem expansão acidental @3x; não alegar crash não observado |
| APP-08 | Calibrar confiança por região e iluminação | L / U2 | condicionado | Peças/referências físicas novas; APP-04/05 | Protocolo congelado, regiões da peça, materiais e luzes variados; reportar erros/abstenções; um acerto físico não valida o limiar 0,5 |
| APP-09 | Medição compatível com recorte e segmentação | L / U3 | condicionado | APP-08; prova de correspondência geométrica | Demonstrar alinhamento entre as imagens e máscara/alvo; caso incompatível se abstém; não aplicar máscara de uma imagem à outra por suposição |

Origem: revisão de `d85fbaa`; `ImportarPeca.swift`, `CapturaDeCorConstante.swift`,
`Modelos.swift`, `Formato.swift`; A53–A56; fila §§2.1/2.6. A avaliação anterior
não deve ser usada para reabrir problemas já corrigidos de fila principal e
limpeza ao cancelar.

### 4.3 Mercado, taxonomia, similares e virada de temporada

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| DAT-01 | Separar autobenchmark do mercado externo | M / U1 | aberto | Versão nova de método e ambiente isolado | `papel=grupo` não entra em numerador/denominador externos; teste sintético e comparação com baseline; impacto histórico declarado |
| DAT-02 | Tornar categoria exclusiva com precedência verificável | L / U1 | aberto | Rubrica e conjunto de avaliação | Cada produto elegível recebe no máximo uma categoria principal; casos ambíguos explícitos; precedência não inventada para apagar divergências |
| DAT-03 | Corrigir vocabulário de malharia e auditar blusa/top/camiseta | M / U1 | aberto | DAT-02; taxonomia revisada | Suéter/pullover/blusão e fronteiras visuais avaliados; definição exclusiva, exemplos, volume e concordância; não criar categoria por dois exemplos |
| DAT-04 | Avaliar viés de tamanho de marca no painel | L / U1 | aberto | População atual medida | Comparar SKU versus pesos por marca/papel, sensibilidade e cobertura; metodologia escolhida e versionada antes de substituir shares |
| DAT-05 | Executar virada versionada e avaliar candidatas | L / U1 | condicionado | DAT-01/02/03/04/07/10/11, OP-04/06 | Coorte, taxonomia e método explícitos; replay/comparação e rollback; clientes antigos isolados; retirar exceções do Demo Day com teste; série nova só entra com história comparável e cobertura suficiente |
| DAT-06 | Calibrar similares por dimensão, cor principal e relaxamento | L / U2 | aberto | Dataset de avaliação e versão de RPC | OR entre alternativas da mesma dimensão, AND entre dimensões quando cabível; categoria preservada, relaxamento explicado, relevância medida sem regressão publicada |
| DAT-07 | Melhorar cobertura semântica de estampa, cintura e tecido | M / U1 | aberto | Taxonomia aprovada e amostra atual | Precisão/recall e observabilidade por dimensão; não trocar ausência por “liso”; ganho de cobertura sem inflar fatos falsos |
| DAT-08 | Curadoria visual e diversidade dos similares | M / U2 | aberto | DAT-06; UX-01 | Critérios de imagem/relevância/diversidade e rejeição explícita; amostra visual não se passa por população; consulta cabe no orçamento medido |
| DAT-09 | Reavaliar a entrada por URL | M / U3 | condicionado | Decisão de UX; backend existente | Reconstruir entrada apenas se escolhida; validar URL exata, limites, erro e privacidade; registrar que a porta foi retirada a pedido do JP, não esquecida |
| DAT-10 | Revisar corpus e método do editorial existente | L / U1 | aberto | Inventário datado, direitos, rubrica e baseline isolada | Fontes BR/internacionais separadas, contagem independente, denominadores e cobertura comparáveis; teste de entrada/saída de veículo sem falso pico; avaliação de contagem esparsa/rajadas e mínimo temporal pós-Demo Day; nenhuma fórmula escolhida só por deixar a tela mais cheia |
| DAT-11 | Compatibilizar taxonomia e séries de busca | M / U1 | aberto | DAT-02/03/07; consultas e metadados existentes | Mapa de termo→query exata, geo, janela, escala e âncora; query nova não herda série incompatível; nenhum degrau metodológico vira tendência; histórico/coleta só quando tecnicamente disponível e permitido |

Origem: `PENDENCIAS.md` §§fila/virada; `FILA_DO_DEPOIS.md` §§2.2–2.4;
`CANARIO.md` §§8/11/13/A20/A49. Percentuais e contagens de agosto são evidência
histórica para investigar, não medição do painel de setembro. DAT-01 a DAT-05
compõem uma virada coordenada: adicionar vocabulário sozinho pode aumentar
marcações duplicadas e distorcer a série.

#### Pacote prioritário: virada metodológica pós-Challenge

**Confirmação e ajuste de 16/09, solicitado pelo JP.** A virada já existia na
regra 5 e no §13 do `CANARIO.md`, em `PENDENCIAS.md` §“Para a virada de
temporada” e em `FILA_DO_DEPOIS.md` §2.2. O roteiro inicial incluía marcas e
taxonomia em DAT-01–05, mas não explicitava a revisão coordenada do editorial
legado e do Trends; DAT-10/11 fecham essa lacuna. Não confundir RAD-07, direitos
de fontes externas do novo radar, com o corpus editorial que já alimenta índices.

“Temporada” aqui é uma **nova versão declarada da medição**, com data de corte e
universo definido. Não é obrigação de esperar a primavera/verão ou apagar a
temporada anterior. Datas de coleção exibidas no app continuam distintas da
versão de painel/método. A preparação começa nesta fase, em paralelo à recuperação
operacional; publicação da nova medição depende dos aceites abaixo.

**Escopo coordenado:**

- **Marcas:** revisar representação, papéis e disponibilidade; separar grupo de
  mercado externo; avaliar as 13 candidatas historicamente listadas, sem promoção
  automática. Comparar pesos por SKU/marca/papel com critério anterior ao resultado.
- **Taxonomia:** categorias exclusivas, malharia, blusa/top/camiseta, vocabulário
  de estampa/cintura/tecido e distinção entre ausência e desconhecido. IDs estáveis;
  significado novo exige revisão/mapeamento, não reaproveitamento silencioso de ID.
  Formulário, Luna, matcher, similares, editorial e Trends precisam do mesmo contrato.
- **Editorial:** revisar relevância em moda feminina, veículos ativos, cobertura,
  origem/republicação, BR versus internacional e denominador da janela. O histórico
  de 02/08 registra quatro picos que eram a entrada de três revistas, não movimento
  das fontes comparáveis. Avaliar também contagem esparsa e rajadas: binomial
  negativa aparece como hipótese histórica, não como escolha validada neste pacote.
- **Busca:** revalidar o significado das queries e sua escala. Já houve costura
  incompatível de janelas de Trends (migration `20260805180000`); uma taxonomia nova
  não pode repetir o defeito. Corrigir consulta sem versão seria mudar a régua no
  meio da comparação.
- **Índices e estados:** recomputar cobertura, raridade, z-scores e elegibilidade
  somente no destino da nova versão. O radar e a Luna recebem a versão e os limites,
  não misturam conceitos amplos do radar com termos aprovados do motor antigo.

A recomposição feminina A41 e os pares compactos A43 já foram implementados;
as fontes femininas acrescentadas em agosto já constam no anexo. Esta entrega
revisa método e qualidade a partir dessa base, não apresenta o trabalho herdado
como uma nova implementação.

**Duas pendências pós-Demo Day encontradas no código versionado:**

1. A exceção editorial de seis semanas expirava em 24/08 (`CANARIO.md`, registro
   de 30/07), mas a última definição de `computar_z()` ainda usa seis, sem data de
   expiração. Preparar retorno ao contrato normal de oito semanas, com teste do
   impacto e sem usar semanas de falha como observações válidas.
2. A mesma definição força `z = NULL` para varejo, apesar de A9 prever ativação
   ao acumular história suficiente. Remover a restrição não é ligar o varejo por
   calendário: exigir oito semanas comparáveis, cobertura e compatibilidade da
   coorte/taxonomia, considerando a lacuna de setembro.

Referência: `supabase/migrations/20260802070027_f7_portao_de_cobertura_da_perna_editorial.sql`.
São constatações do repositório; a função vigente no servidor precisa ser
conferida antes da migration. Nenhuma alteração no motor foi executada nesta revisão.

**Execução e portas de saída:**

1. **Congelar a referência:** identificar composição, taxonomia, queries, métodos,
   data de corte dos dados e contagens atuais; preservar artefatos e commit. Não usar
   contagens de agosto como se fossem medidas novas.
2. **Especificar a versão nova:** inventário de alterações e motivos, mapa de
   compatibilidade, critérios de admissão e decisão sobre comparações possíveis.
   Termos/fontes propostos não passam a aprovados por estarem no roteiro.
3. **Preparar armazenamento e contratos versionados:** provar que escrever a versão
   nova não substitui a velha. As séries legadas são únicas por termo/segmento/
   fonte/semana e a RPC editorial pode substituir uma perna inteira; Git branch
   isolada não isola essas escritas. Usar destino de laboratório e contrato novo.
4. **Reclassificar/recalcular em paralelo:** aplicar ambos os métodos ao mesmo
   conjunto permitido; medir mudanças por marca, categoria, fonte e semana.
   Reprocessamento só onde a evidência conservada permitir. Um artigo sem conteúdo
   suficiente ou uma marca sem snapshots antigos não ganha passado inventado.
5. **Aceite metodológico e de produto:** amostra revisada, exemplos adversos,
   fronteiras/denominadores consistentes, explicação das divergências, performance
   e tamanho do banco. Interrupção/retry/rollback testados sem contaminar o legado.
6. **Transição explícita:** preservar API/dados lidos pelo app entregue, expor nova
   versão ao cliente compatível e anunciar corte/comparabilidade. Se faltar história
   comparável, mostrar nova série sem z/estado em vez de emendar artificialmente.
7. **Acompanhar:** observar ciclos completos, qualidade e crescimento; ligar novas
   pernas somente quando os requisitos forem atingidos, não por uma data prometida.

A preparação não espera o Radar pronto. A recomputação real exige OP-04/05/06
(capacidade, retenção e restauração); a promoção pública continua separada da
autorização de construir. Fontes históricas não são apagadas; retirada da coorte
ativa e exceções às regras editoriais anteriores exigem decisão explícita no
manifesto da virada e changelog. Não há contratação ou corte de produção aqui.

### 4.4 Radar, fontes, Luna e validação

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| RAD-01 | Completar P1 pelo caminho real de extração e revisão | M / U1 | aberto | Laboratório já implementado | Fixture passa por materializador/parser/consolidador reais; cadeia reaberta e comparada; uma evidência e uma leitura privadas, atômicas e idempotentes |
| RAD-02 | Laboratório completo como teste padrão e no CI | M / U1 | aberto | RAD-01, OP-09 | `npm test` executa a suíte completa; smoke separado; expiração por data, concorrência, interrupção, privilégio e ausência de escrita parcial falham corretamente |
| RAD-03 | P2: entidade, observação e identidade lógica duráveis | L / U2 | aberto | RAD-01 | Reobservação preserva história; retry não duplica; mudar conteúdo sob mesma identidade gera conflito; migração aditiva ensaiada sem legado remoto |
| RAD-04 | Conceitos semânticos versionados e eixos separados | L / U2 | aberto | RAD-03 | Aprovação factual, conceitual e editorial distintas; contador operacional não revoga conceito; suficiência, território e dinâmica não se confundem |
| RAD-05 | Retenção, retirada e auditoria mínima do radar | L / U2 | aberto | RAD-03; contratos de fontes | Expiração retira dados de edição, conversa e cache; tombstone só com metadados permitidos; teste de deleção, dependência e reexecução |
| RAD-06 | Revisão real com identidade e carga humana viável | M / U2 | aberto | Ferramentas cegas existentes; revisores reais | R1/R2 independentes, adjudicação e decisão autenticada; simulação não vira revisão humana; preservar cegamento; shards só quando carga real exigir |
| RAD-07 | F1: fonte externa utilizável e corpus autorizado | M / U1 | condicionado | Termos atuais, método e eventual licença/acesso | Matriz IA/exibição/retenção/custo; ao menos um sensor admitido ou bloqueio específico e alternativa; ausência numa shortlist não prova inexistência global |
| RAD-08 | Painel curado de creators e contextos de moda | M / U2 | condicionado | RAD-07; consentimento/método permitido | Seleção por análise técnica, território, originalidade e viés; canais pequenos incluídos; publicidade e republicação identificadas; sem scraping social proibido |
| RAD-09 | P3: afirmações, edição determinística e histórico | L / U2 | aberto | RAD-03/04/05; RAD-07 para alegação externa | Toda frase liga evidência vigente e origem; números/recortes reprodutíveis; contradições visíveis; edição/correção versionadas, não sobrescritas silenciosamente |
| RAD-10 | P4: Luna avaliada, custo limitado e verificador | L / U2 | condicionado | RAD-09; teto financeiro antes de inferência | Baseline e Luna no mesmo corpus, avaliação cega, schema e sustentação verificados; reserva atômica, recibo, timeout e fallback sem loop pago |
| RAD-11 | Conversa contextual e recuperação de evidências | L / U2 | aberto | RAD-09/10, SEC-02/03 | Resposta herda filtros visíveis; cita apenas corpus permitido e vigente; casos sem base/ambíguos/adversos se abstêm; sem recuperar drafts ou dados de outro usuário |
| RAD-12 | Piloto de utilidade e holdouts independentes | L / U2 | condicionado | Corpus autorizado, revisores/participantes e orçamento quando necessário | Teste de tarefa e retorno em outra ocasião; erros, cobertura, custo e minutos humanos registrados; 12 edições revisadas junto do piloto; holdout visual com imagens novas |

Origem: `BLUEPRINT_DATADROBE_1_3.md` §§3–18;
`MARKET_INTELLIGENCE_1_3.md`; governança de fontes; revisão humana; `EXECUCAO_1_3`;
avaliação da ordem alternativa. O piloto pode começar com uma edição manual
revisada, sem esperar todas as 12. Uma edição de composição não valida sozinha
o radar de cores, cortes, caimento, styling e contexto internacional. Falta de
clique em três pessoas não demonstra inviabilidade de todo o produto.

### 4.5 Design, plataforma e identidade

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| UX-01 | Arquitetura de informação coerente com o produto | M / U1 | aberto | Inventário de tarefas e teste exploratório | Protótipo distingue observar mercado, investigar evidência e trabalhar com peça/coleção; usuário encontra tarefa/fonte; não trocar home por preferência estética apenas |
| UX-02 | Sistema visual e componentes consistentes | L / U2 | aberto | UX-01; auditoria visual | Tokens, tipografia, densidade, estados, movimento e componentes documentados; substrato de avaliação neutro; azul não substitui hierarquia; telas pequenas e transições verificadas |
| UX-03 | P5: Radar, dossiê, histórico e fluxo semanal | L / U2 | aberto | UX-01/02, RAD-09 | Navegação frase→evidência→origem; Trends/Search coerentes; loading, sem edição, cache datado, erro, correção e retirada são estados distintos |
| UX-04 | Acessibilidade e robustez de ponta a ponta | M / U1 | aberto | Cada fatia de interface | Dynamic Type, VoiceOver, contraste, Reduce Motion, navegação e alvos de toque; rede lenta/offline, token vencido e interrupção; aceite físico novo no que mudou |
| UX-05 | Investigar e incorporar oportunidades de iOS 27 | M / U2 | condicionado | Verificação oficial e SDK/dispositivos reais | Lista de APIs disponíveis e benefício concreto, fallback, privacidade e teste; nenhuma API hipotética tratada como entregue; decisão de deployment target separada |
| UX-06 | Preservar compatibilidade e medir performance | M / U1 | aberto | OP-09; matriz de dispositivos/OS | Testes no mínimo suportado e sistema atual; cold launch, scroll, imagem, térmica e memória; card social só sai da main thread com ganho medido e execução segura |
| UX-07 | Decidir nome e linguagem de marca | S / U3 | condicionado | Posicionamento UX-01; verificação de disponibilidade | Shortlist, teste de pronúncia/entendimento, busca de conflito e decisão; mudança preserva identidade técnica, links e autoria; não renomear bundle por estética |

Origem: pedido de 16/09; A21/A23/A53–A56; blueprint §§3/13/14;
`FILA_DO_DEPOIS.md` §§2.1/2.4. O inventário local **não encontrou promessas de
recurso aguardando iOS 27**: Liquid Glass/TabView do iOS 26 já têm código, e cor
constante é do iOS 18. A pesquisa atual de plataforma deve complementar UX-05,
sem reclassificar esses recursos como novidade ainda não implementada.

#### UX-05 — pesquisa oficial inicial em 16/09

O iOS 27 foi lançado em 14/09. Algumas capacidades de Siri AI começam em beta
em inglês, com português anunciado para outubro; disponibilidade de OS não
significa disponibilidade de todo recurso em todo idioma/aparelho.
[Anúncio da Apple](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/).
O ambiente local ainda tem Xcode 26.2 (17C52): nenhuma compatibilidade com o
SDK 27 foi demonstrada nesta rodada.

Ordem proposta de experimentos, não recursos prometidos:

1. **Imagens e desempenho:** comparar o cache atual com o suporte HTTP de
   `AsyncImage`, inclusive `URLRequest`/`URLSession` personalizados; medir rede,
   memória e scroll. Rever inicializações de estado com as mudanças de SwiftUI.
   Aceite: ganho medido sem mostrar miniatura de outro usuário ou reter conteúdo
   retirado. Não remover cache existente só porque surgiu API nova.
   [SwiftUI na WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/).
2. **Ações do produto no sistema:** prototipar App Intents para abrir uma peça,
   um dossiê e uma edição, com entidades e deep links autorizados. Requer regra
   explícita sobre o que pode entrar em busca/indexação; Closet privado não é
   conteúdo público. Aceite: logout, troca de conta e retirada invalidam acesso.
3. **Assistência local avaliada:** experimentar Foundation Models em tarefas
   estreitas, como organizar a intenção de busca ou resumir material permitido.
   A documentação agora inclui prompts multimodais e avaliações; nossa hipótese
   de utilidade precisa de comparação com baseline e com Luna, não de troca
   automática do motor. Indisponibilidade tem fallback explícito.
4. **Descoberta visual:** investigar integração com Visual Intelligence para
   abrir conteúdo correspondente. Não prometer identificação exata de produto
   ou transformar semelhança visual em evidência de adoção.

Os itens 2–4 são aplicações propostas a partir das capacidades oficiais de
[Apple Intelligence](https://developer.apple.com/apple-intelligence/), não APIs
já integradas no DataDrobe. Um novo SDK não exige elevar de imediato o mínimo
suportado. Imagem generativa pode servir à comunicação identificada, nunca à
foto de evidência, medição de cor ou prova de uma tendência.

### 4.6 Privacidade, autenticação e liberação

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| SEC-01 | Revalidar autenticação e exclusão completa | M / U1 | aberto | Ambiente identificado e contas de teste | Apple/Google/e-mail, relogin, revogação e exclusão de miniaturas/dados; falha parcial explícita; código de revogação existente não confundido com prova runtime |
| SEC-02 | Ensaiar isolamento de usuário, laboratório e produção | M / U1 | aberto | OP-09; banco de teste | Dois usuários não cruzam dados/objetos; anon não vê drafts; rotinas não ganham poder de aprovação; workflows de laboratório não usam destino genérico de produção |
| SEC-03 | Privacidade acompanhar novos dados e uso de IA | M / U1 | aberto | Mapa de dados/fontes e RAD-07/10 | Consentimento, retenção, política, manifesto e ficha concordam; minimização, logs sem conteúdo/segredos; não prometer retenção zero com `store=false` |
| SEC-04 | Revisão de acesso e release reversível | M / U2 | condicionado | Aceites da fatia, OP-06, decisão de release | Inventário de acessos sem revogar pessoas por inferência; secrets server-side; testes físicos/TestFlight, rollback e metadados; publicação só após decisão explícita |

Origem: A15/A26/A44/A50, implementação de `excluir-conta`, blueprint §§16/18.
Não presumir que pendências de assinatura de agosto ainda existam, nem executar
ações sobre certificados de terceiros como efeito colateral deste roteiro.

### 4.7 Expansão, negócio e portfólio

| ID | Entrega | Grau / urgência | Estado | Dependência | Critério de feito |
|---|---|---|---|---|---|
| EXP-01 | Referências internas por cliente | L / U3 | condicionado | Dados reais autorizados e necessidade observada | Template, importação, validação, escopo local/remoto e exclusão; análogos não viram previsão; sem construir para corpus inexistente |
| EXP-02 | Termômetro retroativo sem vazamento temporal | L / U3 | condicionado | EXP-01; coleção antiga/desfecho e data de decisão | Congelar dados disponíveis naquela data; avaliar ordenamento, erro e viés; limites claros; retrospectiva não promete desempenho futuro |
| EXP-03 | Cliente Android | XL / U3 | condicionado | Contratos estáveis e fatia útil validada | Escolha nativo/multiplataforma justificada; mesmo contrato/segurança, UX e acessibilidade próprias; sem prometer port automático de SwiftUI |
| EXP-04 | Organizações e equipes | XL / U3 | condicionado | Uso colaborativo observado; SEC-02 | Modelo de tenant/papéis/convite, ownership e exclusão; testes cruzados e trilha de revisão; nenhuma conta pessoal vira equipe por improviso |
| EXP-05 | Oferta comercial, preço e billing | XL / U3 | condicionado | RAD-12; economia e disposição de pagar | Custos por cliente/edição, proposta de valor, limites, ciclo de cobrança/cancelamento e regras de loja; não contratar gateway nem cobrar antes da decisão |
| EXP-06 | Exportações profissionais, personalização e novos idiomas | L / U3 | condicionado | Tarefa real, direitos de exibição e APP-02 | Artefato útil com fonte/data/limite, acessível e correto; branding e localização sem alterar IDs/metodologia; não exportar conteúdo sem licença |
| EXP-07 | Case de portfólio demonstrável | M / U1 | aberto | Evidências das entregas e dados publicáveis | README atual, arquitetura, decisões/tradeoffs, vídeo, acessibilidade, testes e resultados medidos; autoria clara; segredos e dados pessoais fora; abrir repo é decisão separada |
| EXP-08 | Offline completo além do cache/Closet local | L / U3 | condicionado | Tarefas offline observadas e política de retirada | Definir o que pode persistir, sincronização e conflitos; conteúdo expirado/retirado não continua válido por estar offline; distinguir recurso atual e novo |
| EXP-09 | Notificações úteis ao usuário | M / U3 | condicionado | Evento útil validado e consentimento | Opt-in, preferências, deduplicação, frequência e deep link; sem transformar indisponibilidade em demanda; alertas operacionais OP-02 são outra função |
| EXP-10 | Painel administrativo/editorial de produto | XL / U3 | condicionado | RAD-06/09; carga operacional real | Permissões por função, revisões/retiradas auditadas e UX de trabalho; não substituir revisão independente por dois aliases do mesmo operador |

Origem: CANARIO §§30/31/34/36; blueprint §§4/15; pedido pós-Challenge. Android,
billing, administração, push e offline completo deixam de ser ideias apagadas,
mas não entram todos na primeira entrega.

## 5. Ordem de execução e portas de saída

### Índice por dificuldade, da menor para a maior

Esta é a ordenação de esforço pedida pelo JP; a execução começa pelos incidentes
U0, mesmo que sejam mais difíceis. Detalhes e dependências estão nas linhas de
cada ID acima.

| Grau | IDs (62 itens, sem duplicação) |
|---|---|
| XS — 1 | APP-06 |
| S — 6 | OP-04; APP-01/02/03/07; UX-07 |
| M — 28 | OP-01/02/03/05/09; APP-04/05; DAT-01/03/07/08/09/11; RAD-01/02/06/07/08; UX-01/04/05/06; SEC-01/02/03/04; EXP-07/09 |
| L — 22 | OP-06/07; APP-08/09; DAT-02/04/05/06/10; RAD-03/04/05/09/10/11/12; UX-02/03; EXP-01/02/06/08 |
| XL — 5 | OP-08; EXP-03/04/05/10 |

### Sequência de implementação por risco e dependência

| Etapa | IDs principais | Porta de saída |
|---|---|---|
| 1 — operação visível | OP-01 a OP-04 | Saber por que parou, recuperar dentro do escopo e detectar a próxima ausência; métricas atuais de capacidade |
| 2 — integridade e continuidade | APP-01 a APP-07, OP-06/09, SEC-01/02/03 | Resultados de preço/cor corretos, fallback explicado, sem regressão de conta/dados e prova de restore isolado |
| 2B — virada metodológica prioritária | DAT-01 a DAT-05, DAT-07/10/11 | Preparação começa junto da operação; método/taxonomia/painéis versionados e comparação isolada após OP-04/05/06; promoção não altera o app entregue silenciosamente |
| 3 — base contínua da 1.3 | RAD-01/02, EXP-07 | Caminho inteiro local e CI reproduzíveis, documentação condizente com a prova |
| Paralela — aprender desde cedo | RAD-07, UX-01, piloto inicial de RAD-12 | Fonte autorizada ou restrição específica; teste de tarefa; design guiado pelo trabalho do usuário |
| 4 — produto rastreável | RAD-03 a RAD-11, UX-02/03/04 | Edição e conversa privadas, verificáveis e capazes de se abster |
| 5 — refinamento sobre a nova medição | DAT-06/08, APP-08 | Similares e cor calibrados com avaliação independente, depois da fundação metodológica da etapa 2B |
| 6 — escala justificada | OP-07/08, EXP-01 a EXP-10, SEC-04 | Acesso, economia, demanda, privacidade e rollback demonstrados para cada expansão |

Não esperar o fim da etapa 4 para ouvir alguém. Também não usar um piloto de
três pessoas ou um pipeline verde como prova de mercado. A migração de backend
pode subir de prioridade se a medição mostrar risco imediato; o destino continua
precisando de custo aprovado e restauração ensaiada.

## 6. Ideias preservadas, sem implementação automática

- **Create ML/visão local:** spec antiga pode alimentar um novo experimento
  comparativo; não é dívida a pagar só porque foi substituída pela Luna.
- **Novas marcas/multimarcas/Amaro:** revalidar acesso e papel metodológico;
  disponibilidade histórica não é a disponibilidade atual.
- **Busca vetorial, embeddings, microserviços, Kafka e agentes no runtime:**
  acrescentar somente se avaliação ou carga revelar limitação concreta.
- **Retenção especial de IA (MAM/ZDR):** exige necessidade contratual e controle
  habilitado verificável; o registro de fonte não pode autoconcedê-la.
- **Passarelas, vitrines, Pinterest, Instagram, TikTok e YouTube:** investigar
  caminhos permitidos e adequação do sensor; não prometer licença/API por
  existência de página pública. Criatividade não depende de contornar direitos.
- **Coleções/sazonalidade e histórico interno:** precisam de material autorizado
  do cliente, não de respostas inventadas pelo pipeline.

### Nomes para explorar, ainda sem validação de marca ou disponibilidade

**Vestígio** (vestir + evidência), **Entrelinha** (moda + leitura), **Tramora**
(trama + agora), **Trama** (tecido + relações) e **Orla** (observação e fronteira).
São hipóteses criativas para UX-07, não recomendação jurídica nem nomes livres.
DataDrobe explica dados + armário; a escolha futura deve representar também o
radar e a investigação, sem obrigar uma troca precipitada.

## 7. Registro de entrega por ID

Ao implementar uma fatia, registrar junto dela:

1. Commit e arquivos, sem atribuir trabalho herdado como novidade.
2. Comandos/testes executados e resultado, distinguindo lógica, integração, UI,
   aparelho físico e serviço remoto.
3. Evidência do critério de feito; teste verde fora do caminho real não basta.
4. Limitações, dados fictícios identificados e direitos/custos não habilitados.
5. Se houve deploy, ambiente e verificação posterior; se não houve, dizer isso.
6. Próximo ID executável, sem recomeçar o inventário inteiro na sessão seguinte.

Este roteiro não substitui a blueprint técnica nem apaga decisões históricas.
Consolida a fila para execução pós-Challenge; o estado operacional verificável
permanece em `ESTADO.md`.

### Primeira fatia local — 16/09/2026

| ID | Progresso e limite |
|---|---|
| OP-01 | Causa do incidente medida; diagnóstico JSON e elegibilidade de recuperação corrigidos/testados localmente. Incidente continua aberto: nenhum deploy nem ciclo real recuperado. |
| OP-04 | Banco, relações, cron, Storage e watermarks medidos por leitura. Faltam confirmação de billing, espaço físico e projeção de crescimento após recuperação; não há número provado de bloat recuperável. |
| RAD-02 | `npm test` passou a executar admissão e concorrência; smoke separado. Testes aprovados em PostgreSQL 17.10 isolado. CI, novos casos e caminho real P1 continuam pendentes. |
| UX-05 | Pesquisa oficial inicial acima; Xcode/runtime 27 e testes ainda pendentes. |
| EXP-07 | README corrigido quanto a imagens, RLS, coleta e links; roteiro e runbook criados. Case público, vídeo e demonstração não foram produzidos. |

Comandos e resultados da fatia estão no topo de `ESTADO.md`; arquivos compõem
o commit local desta entrega na branch `codex/produto-pos-challenge`. Nenhum
desses avanços declara completo um critério que ainda dependa de produção.
