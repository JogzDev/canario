# Fila do depois — inventário completo

**05/09/2026.** Tudo que este projeto decidiu adiar, num lugar só, com a origem
de cada decisão. Até hoje a lista estava espalhada por quatro documentos
(`PENDENCIAS.md`, `ESTADO.md`, o changelog do `CANARIO.md` e a blueprint da
1.3), e "o que ficou para depois" só existia na cabeça de quem tinha lido os
quatro. Um item que ninguém consegue enumerar não está adiado: está esquecido.

**Coluna que mais importa:** *toca o app publicado?* O 1.1 está na App Store e
lê séries já computadas do mesmo Supabase. Qualquer linha marcada com **SIM**
muda o que as pessoas veem hoje, no celular delas, sem build novo.

---

## 1. Fechado em 05/09 — saiu da fila

| Item | Origem | O que era |
|---|---|---|
| **Multi-idioma** | anti-escopo §34 | "sem multi-idioma" era Won't Have permanente da v1. Revogado pela A53; pt-BR e inglês, 517 chaves, com portão de CI |
| **Strings fora do String Catalog** | `PENDENCIAS.md`, acabamento adiado | O Xcode podava chaves em silêncio a cada redesenho. Agora `ferramentas/extrair_frases.py --conferir` falha o push |
| **Fundo azul atrás da peça** | revisão com a diretoria | A54: substrato neutro fixo `#CBCBCB` |
| **Verbo na barra de navegação** | revisão com a diretoria | A55: `Add` → `Studio` / `Estúdio` |
| **Cor dependente da luz do ambiente** | revisão com a diretoria | A56: cor constante do iOS 18, opt-in, com portão de confiança |
| **P1 do radar 1.3 nunca executado** | blueprint 1.3 | Laboratório rodado em PostgreSQL real; ver `EXECUCAO_1_3.md` |

---

## 2. Continua adiado — e eu recomendo que continue

### 2.1 Adiado por análise de custo, não por falta de tempo

| Item | Origem | Por que eu deixaria parado | Toca o app publicado? |
|---|---|---|---|
| **Card social fora da main thread** | `PENDENCIAS.md` | `CartaoCompartilhavel.imagem` é `@MainActor` e renderiza 1080×1350. O ganho são 1–3 quadros numa ação que já mostra "Preparing export…"; o custo é mover desenho de texto para fora da main thread, com risco real de crash. É o único item da lista que eu deixaria parado mesmo com tempo sobrando | não |
| **Cor medida na "peça isolada"** | criado hoje, emenda da A56 | A foto inteira mantém a cor medida; isolar a peça a perde. O Vision devolve uma **máscara**, não um retângulo, e ela nasceu da foto natural — aplicá-la aos pixels da foto de cor constante exigiria que o Vision achasse as mesmas instâncias, na mesma ordem, nas duas versões da cena, o que nada garante. Medir num recorte que talvez não seja o escolhido é pior que não medir. Destravar exige medir primeiro se as instâncias batem | não |
| **Fechar o P1: fixture pelo parser real** | revisão externa de 05/09 | A fixture atual monta o manifesto direto. Os itens 5–7 do checklist da blueprint pedem que a etiqueta sintética passe pelo `materializar_etiqueta_radar.py` e pelo `consolidar_revisao_etiqueta_radar.py` antes de virar manifesto. Sem isso, a ligação extração revisada → admissão continua sem demonstração | não |
| **Confiança por região, e não só a média ao centro** | revisão externa de 05/09 | `constantColorCenterWeightedMeanConfidenceLevel` pondera o CENTRO do quadro. Uma peça fora do centro é descrita por um número que fala principalmente do fundo. A Apple entrega também `constantColorConfidenceMap`, com valor por região — usá-lo exige saber onde a peça está, e a segmentação só acontece depois da captura | não |
| **Laboratório do P1 no CI** | decisão de 05/09 | Precisa de `npm ci` baixando ~134 MB de binários PostgreSQL a cada execução limpa, no Mac do JP. Ficou como prova de *checkpoint*, não contínua — com a consequência honesta de que quem mexer na A51 sem rodá-lo não será avisado | não |

### 2.2 Virada de temporada — mexem no share histórico em produção

Estes cinco são um passe só, e é por isso que nenhum deles anda sozinho:
corrigir vocabulário sem regra de precedência aumentaria a marcação dupla em
vez de reduzi-la. **Todos exigem recomputação e todos chegam ao 1.1 publicado
sem build novo.**

| Item | Origem | O que foi medido | Toca o app publicado? |
|---|---|---|---|
| **`papel = grupo` conta como mercado externo** | `PENDENCIAS.md` 26/08 | A `CANARIO.md` linha 145 diz que Farm, Animale, Maria Filó e NV são autobenchmark e "nunca contam como mercado externo". Mas `computar_serie_varejo` monta a população só com `where p.segmento is not null` — sem join com `marcas`. As quatro entram no denominador de todo share de `feminino_casual_br` | **SIM** |
| **Suéter/quarter-zip em duas categorias** | `PENDENCIAS.md` 26/08 | 1.281 títulos dizem suéter/pullover: **819 em `casaco_jaqueta` e 361 em `blusa_top`**. A causa é vocabulário — `casaco_jaqueta` casa `cardigan` mas não `suéter`, `pullover` nem `blusão`. Move ~500 produtos | **SIM** |
| **Categoria não é exclusiva, e o §11 diz que deveria** | `PENDENCIAS.md` 26/08 | **7,85% do painel (5.884 produtos) carrega duas ou três categorias** ao mesmo tempo, e cada um conta nos dois shares | **SIM** |
| **Viés de composição do painel** | `PENDENCIAS.md` | C&A é ~53% do painel e o share é por SKU, então a maior marca domina por volume. Média entre marcas com peso por papel resolve melhor que adicionar marcas | **SIM** |
| **Promover as 13 candidatas ao painel medido** | `PENDENCIAS.md` | Elas já entregam o benefício visível (similares com foto, preço, marca) de dentro de `catalogo_candidato_br`. Promover exige virada explícita, recomputação e folga de banco, nesta ordem | **SIM** |

### 2.3 Motor de similares — alto valor, mexe em RPC de produção

Pedido do JP em 27/08. **Não é dívida técnica: é calibração com medição pronta
esperando decisão.** O que já está medido:

- **A cobertura por dimensão é o gargalo, não a regra.** Categoria 97,4%, cor
  38,5%, tecido 33,6%, estampa 5,4%, cintura 4,6%. Exigir 70% dos atributos com
  duas dimensões quase vazias é zero garantido.
- **A escada de relaxamento vale mais que qualquer ajuste de peso.** Na medição
  da polo: 4 de 5 atributos devolveu **0** similares; tirar um único atributo da
  dimensão mais rala devolveu **13 peças em 4 marcas**.
- **Duas cores da mesma dimensão colapsam o conjunto.** `vestido + preto` dá
  202, `vestido + branco&cru` dá 153, as três juntas dão **12** — porque título
  de produto quase nunca lista duas cores. Dentro da mesma dimensão os termos
  deveriam competir (OR), não se exigir (AND).
- **A A49 abriu um caminho assimétrico.** A peça do usuário sabe qual é a cor
  principal; o produto do painel não, porque a cor dele sai do título. Dá para
  exigir que a cor **principal** case, evitando que uma busca por verde devolva
  peça 80% rosa com detalhe verde.
- **O maior buraco isolado:** 4.509 produtos dizem "estampado" no título e só
  1.100 receberam termo de `estampa`. São ~3.400 peças que o painel declara
  estampadas e o motor não consegue casar.

**Toca o app publicado? SIM** — o motor de similares é RPC do Supabase e o 1.1
o consulta. Uma mudança aqui aparece imediatamente para quem já baixou.

### 2.4 Decisões de produto não tomadas (não são dívida)

| Item | Origem |
|---|---|
| Taxonomia `blusa_top` (auditoria, inclusive `camiseta`) | `ESTADO.md`; a A20 exige definição visual exclusiva, volume, concordância humana, impacto nas séries e migração versionada |
| Fluxo semanal unificado de Trends e Search | `ESTADO.md` |
| Curadoria visual dos similares | `ESTADO.md` |

### 2.5 Infraestrutura

| Item | Origem | O que trava |
|---|---|---|
| **Alerta de "o pipeline nem começou"** | `ESTADO.md`, técnico em ordem de valor | O alerta de falha existe desde 19/08, mas roda no mesmo Mac que executa a coleta: máquina parada, ninguém avisado. `ubuntu-latest` **falha antes de começar** nesta conta, por bloqueio de billing. Sem gastar, a saída é algo fora do GitHub |
| **Definir o número que separa "cobertura aceitável" de "dia inútil"** | `ESTADO.md`, só o JP pode fazer | Decisão sua |

### 2.6 Validações que dependem de material novo

| Item | Origem | O que falta |
|---|---|---|
| **Holdout novo da Luna** | `PENDENCIAS.md` / `ESTADO.md` | A taxonomia expandida deu 57/72 (79,2%) nas mesmas 24 imagens. O conjunto não será repetido nem usado para perseguir décimos: cinco casos difíceis ficam registrados como erro conhecido. Um holdout futuro exige **imagens novas** e orçamento explícito |
| **Calibrar o piso de confiança da cor constante** | criado hoje, A56 | A rota foi exercitada em aparelho pelo JP em 05/09 e responde. O que falta é o número: `CorDaPeca.confiancaMinimaDaCaptura = 0.5` está registrado como **não calibrado**. Precisa de peças fotografadas sob luzes conhecidas com a cor verdadeira anotada — a mesma peça sob lâmpada quente, LED frio e luz de janela, comparadas contra a cor real. Até lá erra para o lado de não sugerir |
| **Validação retroativa / o termômetro (§31)** | `CANARIO.md` §31 | Depende de o cliente entregar uma coleção antiga com desfecho conhecido. Pergunta aberta desde o §36 |

### 2.7 Revogados para a v1, com especificação preservada

| Item | Origem | Situação |
|---|---|---|
| **Visão computacional treinada (Create ML)** | §28, revogada por A7, substituída por A15 | A rota paga da Luna ocupou o lugar. O texto do §28 permanece como spec |
| **Referências internas por cliente (§30)** | revogada por A7, "volta na v1.1" | O cliente não entregou dado nenhum; construir para dado que não existe é desperdício |
| **Importação por URL** | `PENDENCIAS.md` 26/08 | Backend entregue e provado com Farm/tomate, mas **a porta saiu da interface a pedido do JP**. Não é funcionalidade da 1.2; recolocá-la exige reconstruir o cartão — o RPC continua pronto |
| **Multimarcas no painel** | revogado 24/07 | Nenhum dos 4 passou no teste dos 30 segundos. Reversível se o pente fino recuperar algum |
| **Amaro no painel medido** | A-31/07 | 429 persistente de datacenter. Volta com runner residencial |

### 2.8 Anti-escopo §34 que continua de pé

Sem push notification · sem Android/web · sem Instagram/TikTok · sem pagamentos
· sem painel administrativo web · sem modo offline completo (só cache da última
sincronização).

*(Login/conta e closet já foram revogados pela A26 e pela A18; multi-idioma pela
A53 de hoje. Os seis acima seguem valendo, e adiantar qualquer um deles viola o
documento.)*

### 2.9 Depois da validação da 1.3 (blueprint, seção 4)

Android · oferta comercial · billing · organizações e equipes · exportações
profissionais · idiomas adicionais além de pt/en · personalização de marca.

A blueprint é explícita: *"Contratos independentes do cliente preparam esse
caminho; não se construirá uma segunda interface ou sistema de cobrança neste
pacote."*

---

## 3. O que a fila não cobre, e é o buraco maior

Nenhum item acima responde à pergunta que decide a 1.3: **existe alguma fonte
externa legalmente utilizável?** A F1 não é dívida adiada — é o pacote que
nunca começou, e do qual dependem P3, P4, P5 e P6. Ver `ORDEM_PROPOSTA_1_3.md`.
