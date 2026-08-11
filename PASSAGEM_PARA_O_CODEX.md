# Passagem de bastão — sessão de 07 a 10/08/2026

**Para quem pega daqui:** este arquivo cobre tudo o que foi feito desde a mensagem
do JP *"vamos pela camera, sobre a dobra da comparar dentro do armario, tenho
prints novos do figma"* e tudo o que ficou por fazer, na ordem que eu seguiria.

**Leia antes:** `CANARIO.md` (a lei, com o changelog no fim) e `PENDENCIAS.md`
(o placar). Nada aqui substitui os dois — este arquivo é o contexto da sessão.

**Regra que vale para todo o projeto:** nenhuma etapa nova começa com item
vermelho relevante para ela. E toda decisão nova nasce com uma linha no
`PENDENCIAS.md`.

---

## Parte 1 — O que foi feito nesta sessão

### 1.1 Leitura do design da Bianca e do Davi

O JP mandou prints do Figma. Quatro pontos colidem com o documento, registrados
no changelog do `CANARIO.md` em 07/08. **Três seguem abertos:**

| # | Colisão | Estado |
|---|---|---|
| 1 | **Login / Cadastrar / Account** contra a §34 (*"sem login/conta de usuário"*) | **ABERTO.** O JP esclareceu depois: a conta existe para acessar o armário de outro aparelho. Isso é motivo legítimo e derruba a objeção — mas leva o armário para o servidor, e a ficha de privacidade passa de "não coletamos nada" para coletar e-mail e peças salvas. Precisa de revogação da §34 antes da submissão |
| 2 | **"Métricas da peça"** com gráfico de linha implicando acompanhar a peça do usuário | **RESOLVIDO** — virou o gráfico dos *atributos* (A14, abaixo) |
| 3 | **"Taking measurements" / "Clothing DNA"** prometem medir a peça pela foto | **ABERTO.** Medido: 64,1% só em categoria. O texto de carregamento precisa dizer o que acontece de fato |
| 4 | **"Mostrar similares" com foto de produto** contra o A6 | **RESOLVIDO** — o JP aprovou hotlink (A13, abaixo) |

O Davi não vai desenhar as telas novas ("ele não sabe fazer e já pegou um embalo
no figma"). O JP disse que manda prints mais tarde.

### 1.2 Câmera e fototeca (A12)

Decisão do JP: *"se necessário, o app vai passar a pedir permissão sim"* e
*"camera pode ser antes da submissão"*.

**Feito:**
- `app/Canario/Telas/CapturaDeCamera.swift` — `UIImagePickerController` embrulhado
  para SwiftUI. `allowsEditing = false` **de propósito**: o recorte do iOS
  devolve a imagem já cortada, e o corte feito com o dedo mudaria a cor dominante
  que o `CorDaPeca` mede — o app estaria medindo o enquadramento, não a peça.
- `PhotosPicker` para a fototeca, em `ImportarPeca.swift`.
- `LeitorDeArquivo.ler(_ imagem: CGImage)` — porta de entrada nova, em memória.
- `Info.plist`: `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription`.
  **NÃO existe** `NSPhotoLibraryAddUsageDescription`: o app não salva foto
  nenhuma, nem a que ele mesmo tirou.
- `PrivacyInfo.xcprivacy` reescrito. `NSPrivacyCollectedDataTypes` **continua
  vazio** — permissão de acesso e coleta de dado são coisas diferentes.

**Invariante a preservar:** as três entradas (arquivo, fototeca, câmera) terminam
no mesmo `LeitorDeArquivo`. Câmera e fototeca entregam a imagem **em memória**;
não existe caminho de disco em nenhuma das três. O que não existe não pode ser
esquecido ligado.

### 1.3 Visão computacional — o que foi medido e descartado

Esta é a parte com mais tempo gasto e menos resultado. **Leia antes de tentar de
novo.**

| tentativa | resultado | veredito |
|---|---|---|
| **MobileCLIP** (proposta do Gemini) | — | **Proibido.** `LICENSE_MODELS` do `apple/ml-mobileclip` libera os pesos *"exclusively for Research Purposes"* e diz que isso *"does not include any commercial exploitation, product development or use in any commercial product or service"*. App publicado é produto, mesmo grátis, mesmo sendo TCC |
| **Centroide da Vision** (`VNGenerateImageFeaturePrint`) | **49,6%** em categoria | Abaixo do piso |
| **Create ML**, 2.574 imagens, 4 aumentos | **64,1%** validação (75,9% treino) | Abaixo do piso de 80% da §28 |
| **Create ML**, mais dado | *nunca terminou* | Treino com 4.790 imagens não fecha em 90 min; com 2.574 fechava em 6 |
| **`VNClassifyImageRequest`** | **1 de 8** categorias existe | **Descartado por vocabulário, não por acurácia.** A taxonomia da Apple tem 1303 rótulos FIXOS; dos nossos 8 de categoria só `jacket` existe. Estampa, tecido e estética: 0 de 16 testados |
| **Foundation Models multimodal** | — | **É a resposta certa, e não cabe no prazo.** `Attachment` é **iOS 27.0+ e Beta**. A App Store não aceita binário compilado contra SDK beta. Vira v1.1 |

**A API do Foundation Models, para quando o iOS 27 sair:**

```swift
@Generable enum Categoria { case vestido, calca, saia, camisa, blusa, short, macacao, casaco }

let session = LanguageModelSession()
let r = try await session.respond(
    generating: Categoria.self,
    options: GenerationOptions(samplingMode: .greedy)
) {
    "Escolha o rótulo que melhor representa esta peça:"
    Attachment(imagem)
}
```

**Ferramentas que ficaram prontas** (rodam no i7, nunca na máquina pessoal do JP):
- `ferramentas/gerar_centroides.swift`
- `ferramentas/treinar_categoria.swift`
- `.github/workflows/centroides.yml` — `workflow_dispatch`, fixo em
  `[self-hosted, macOS]`, teto de 90 min

**Cache no i7:** `~/canario-imagens-treino/<categoria>/<produto_id>.jpg`, com
**4.790 imagens** já baixadas. Não baixe de novo o que está lá.

**Armadilha da regra 7, que eu violei sem perceber:** de 10.702 tentativas de
download, **5.411 foram HTTP 429** — e o código contava e seguia batendo na mesma
cadência. Agora o intervalo por domínio dobra a cada 429, até 30s. Se for mexer
em download de imagem, mantenha isso.

### 1.4 Portão de saúde — o pipeline diário caiu 09 e 10/08

**Causa:** `varejo/Amaro retornou zero`. No log da coleta:

```
Amaro   visit=0 grav=0 (3s)   {'erro': 'http 500'}
PatBo   visit=0 grav=0 (61s)  {'erro': 'http 429 (persistiu apos backoff longo)'}
```

São **as lojas respondendo**, não bug nosso. Medido em 9 dias: Amaro 8 dias bons
e 2 zerados; PatBo 8 bons e 2 zerados **e recuperou sozinha**.

**Conserto** (`coletor/coletor_varejo.py`, `alertas_criticos`):

| situação | comportamento |
|---|---|
| zero **com motivo HTTP**, menos de 3 dias seguidos | **aviso** — não trava |
| zero **sem motivo nenhum** | trava (não saber é pior que saber que foi recusa) |
| zero por **3 dias seguidos** | trava |

`alertas_criticos` agora devolve `(criticos, avisos)`. Só os críticos travam.

**Atenção:** isso **não garante verde**. Se a Amaro seguir recusando, o terceiro
dia trava de novo — e deve travar.

### 1.5 Abas e Armário (A10, A11)

- Abas hoje: **Adicionar · Armário · Dados · Comparar** (`CanarioApp.swift`).
- `PecaSalva` + `PecasSalvas` (ator, JSON em Application Support, teto de 200).
- Botão **Guardar** no `RelatorioDaPeca`.
- **A11 (revogação do JP):** o nome voltou a ser "Armário". A função dele vem
  depois, com o design.

**A trava que não pode cair:** `PecaSalva` guarda **só o que o usuário digitou** —
`id`, `apelido`, `termoIds`, `criadaEm` — e **nenhum número calculado**. Índice,
estado e z são recomputados do dado de hoje a cada abertura.
`testPecaSalvaNaoGuardaNumeroCalculado` falha se alguém acrescentar `indice`,
`estado`, `z` ou `ultimaLeitura`, com a razão na mensagem de falha.

Se a função do Armário que vier envolver **acompanhar a peça ao longo do tempo**,
a §34 precisa de revogação com consequência de método, não só de rótulo: a peça
do cliente não está no painel e nenhuma marca que medimos vende ela.

### 1.6 A13 — foto do similar por hotlink

Decisão do JP: *"quero muito usar, de verdade, podemos usar Hotlink sem
problemas, desde que funcione"*.

- `similares_da_peca()` passa a devolver `imagem` (URL do CDN **da própria loja**).
- `Similares.Peca.imagem`, `MarcaVisual` desenha com `AsyncImage`.
- **O bloco de cor do A6 não saiu — virou o fundo.** É o que aparece enquanto
  carrega, quando a loja tira a imagem do ar e quando o produto não tem foto.
- O card cresceu de **34×52 para 72×96**: na medida antiga (que era do bloco de
  cor, abstrato) a foto virava mancha e o JP não percebeu que existia.

**Hotlink, não cópia.** O aparelho busca na origem, na hora. Nada é copiado para
o nosso servidor nem para o binário. **Em aberto e é do JP:** o "Google faz
assim" vem de *fair use* americano e o Brasil não tem *fair use* geral (Lei
9.610/98 tem exceções enumeradas). Vale conferir os termos das lojas.

### 1.7 A14 — `serie_do_cluster()` e o gráfico

RPC nova: série semanal do índice **dos atributos** da peça. Migração
`supabase/migrations/20260810180000_p3_serie_do_cluster.sql`.

**Dois erros meus, achados na verificação — não repita:**

1. **A raridade é chaveada por `(categoria, termo_id)`** — nove linhas por termo
   (uma por categoria mais `(todas)`). A primeira versão esqueceu o recorte, o
   join multiplicou por nove, e ela reportou *"27 atributos com peso"* para três
   pedidos. O número saía plausível e estava errado.
2. Escrevi no comentário que **o último ponto do gráfico bate com o número
   grande**. Não bate: o número grande é a leitura mais recente de *cada*
   atributo (de semanas possivelmente diferentes); o ponto é o que havia
   *naquela* semana. Medido: −0,43 contra −0,57.

No app: `app/Canario/Rede/SerieDoCluster.swift` e `blocoDoHistorico` no
`RelatorioDaPeca`. Cada ponto carrega `n_atributos`, e semana com menos atributos
que o pedido aparece **marcada** — a linha sozinha mente por omissão.

### 1.8 Performance

O JP: *"continua MUITO lento mesmo pra rodar, nível de tela preta sem nada por
alguns segundos"*, com `Hang detected: 5.25s` e `Operation timed out` no Xcode.

**Medido em 10/08 contra o servidor real:**

```
termos              1,74s para   9 kB
indices_do_app      1,25s para 122 kB
eventos reposicao   2,87s para  96 kB
series_do_app       0,38s para 168 kB   <-- o MAIOR e o mais rápido
```

**O custo é abertura de conexão, não tamanho.** Quatro causas consertadas:

1. `Analisar` (primeira tela) fazia as duas consultas **em fila**: 1,74 + 1,25 =
   os ~3s do `Hang detected`. Agora `async let`.
2. `timeoutIntervalForRequest` de 20s → **10s**. Com a segunda tentativa em cima,
   uma requisição travada segurava 40s.
3. **Tempo esgotado não repete mais.** 5xx continua repetindo (ali o servidor
   respondeu, e rápido).
4. `TabView` ganhou `selection` + `.tag` para não montar as quatro abas juntas —
   eram mais de dez requisições simultâneas na abertura fria.
5. `alvos.first(where:)` dentro do laço do `Explorar` era O(n×m) no ator
   principal. Virou dicionário.

**Antes disso, em 06/08:** as views `indices_do_app` e `series_do_app` cortaram
o tráfego em **−66% e −56%** — 86% do peso era a coluna `meta`, e o app lê três
escalares dela.

**Não verificado no device.** O JP precisa rodar e confirmar.

### 1.9 Trends — fechou

**40 dos 41 termos na semana mais recente**, média de 256 pontos por termo. Só
`outras_cores` segue sem série (vermelho antigo). A fila por defasagem se
resolveu sozinha.

**Contexto que importa:** a perna de busca teve um bug de rótulo de **seis dias**
(o Trends marca a semana pelo domingo; o coletor jogava para a segunda anterior).
Corrigido, com `coletor/teste_semana_da_busca.py` travando contra a função real
do coletor editorial. Uma tentativa de trocar a janela semanal por diária foi
**revertida** — não havia frescura a ganhar e o diário apaga termo de volume
baixo (`viscose_fluido`: 0,9% de semanas em zero no semanal, 73,5% no diário).

### 1.10 API da OpenAI — preços levantados

| modelo | entrada /1M | saída /1M |
|---|---|---|
| Sol | $5,00 | $30,00 |
| Terra | $2,00 | $12,00 |
| **Luna** | **$0,20** | $1,20 |

Estimando ~1.000 tokens por imagem + ~10 de saída:

| | por foto | 300 imagens | as 68.525 do painel |
|---|---|---|---|
| Luna | ~$0,0002 | **~$0,06** | **~$14** |
| Terra | ~$0,002 | ~$0,60 | ~$140 |

**Recomendação:** começar na **Luna**. Distinguir vestido de calça é tarefa fácil,
e dá para descobrir se ela basta por seis centavos.

**Duas rotas, e a diferença não é preço:**

- **API no runtime** (foto do usuário → OpenAI): ponte que termina no iOS 27. Mas
  o Foundation Models exige iPhone 15 Pro+; quem tem aparelho antigo nunca vai
  ter. Muda a ficha de privacidade e a promessa de retenção zero.
- **Rotular o painel offline → Create ML**: ~$14 uma vez, modelo local que roda
  em iOS 17+ em qualquer aparelho, para sempre, sem custo por uso. A foto do
  usuário nunca sai do celular.

**Ressalva medida:** o diagnóstico dos 64,1% apontou para **volume e ruído da
imagem** (modelo, cenário, props), não para rótulo ruim. É bem possível que
rótulo melhor não levante muito. O teste das 300 responde isso por $0,06.

---

## Parte 2 — Tudo o que falta, na ordem que eu seguiria

### Ordem proposta

A lógica: **primeiro o que trava o Demo Day, depois o que trava o usuário, depois
o que trava a qualidade.**

#### Bloco A — antes da submissão (bloqueia publicação)

| # | O que | Por quê agora |
|---|---|---|
| A1 | **Confirmar a performance no device** | O JP ainda não validou. Se continuar lento, tudo o resto espera |
| A2 | **Decidir login/conta** e, se sim, revogar a §34 com entrada própria | Muda a ficha de privacidade da App Store. Não dá para descobrir isso na revisão |
| A3 | **Reescrever o texto de carregamento** do Figma ("Taking measurements", "Clothing DNA") | Promete medição que não fazemos. É §2 e A8 |
| A4 | **Dobra da Comparar dentro do Armário** | A Comparar ainda seleciona *termos soltos* — origem do *"camisa e branco tá na mesma lista mas são categorias diferentes"*. Com peças guardadas isso se resolve |
| A5 | **Definir a data nova de feature freeze** | Era 10/08 e o JP mandou esticar. Sem data, não há corte |
| A6 | **Conferir termos das lojas para o hotlink** | Decisão do JP, com risco jurídico que eu não sei avaliar |

#### Bloco B — qualidade do que já está na tela

| # | O que | Estado |
|---|---|---|
| B1 | **Cobertura de z da perna editorial** | **Este é o gargalo real do app hoje.** Só ~7% das linhas editoriais têm z (687 de 10.104 no BR). A §22 precisa de duas pernas e a segunda não chega: na semana de 27/07, **37 termos têm só `{busca}`** e nenhum estado |
| B2 | **`coleta-editorial` no runner residencial** | FFW e Business of Fashion dão 403 do datacenter e 200 do IP residencial (medido, com o `CanarioBot`). A variável `RUNNER_COLETA` **não está criada**. Ligar faz a coleta depender do Mac ligado; o conserto sem esse custo é a série editorial vir de `artigos` no banco, e não dos feeds da execução |
| B3 | **Teste das 300 imagens com a Luna** | Precisa da chave da OpenAI (nunca no chat: `Config.xcconfig` local ou secret do GitHub) |
| B4 | **Identidade visual dos cards** (A6, Bianca) | O bloco de cor é placeholder desde sempre |

#### Bloco C — vermelhos antigos do `PENDENCIAS.md`

| id | O que | Impacto |
|---|---|---|
| A1 | `flag_tipo` presumido por categoria e palavra-chave | Nada preenche |
| K2/K3 | Continuativo (idade ≥ 26 semanas, 3 reposições em 12) | **Depende de história que o projeto não tem.** Sem eles, o badge de peça clássica da §27 não aparece e a §23 não separa continuativo de coleção |
| A3 | Forma descritiva do marco de demo 2 | Não feito |
| K9 | Alerta de saúde vira issue no repositório | Não feito |
| §20 | Limiar dos 70% na queda de fonte | Parcial |
| K11 | Regra dos 25% de ausência na célula | Parcial |
| — | `outras_cores` sem série de busca | 1 dos 41 termos |
| — | `artigo_termos` vazia | Tabela existe e não é usada; os veículos vivem em `series_semanais.meta` |
| — | Fábula: 0 coletas | Reprovada por princípio (API fechada no edge), aguarda autorização escrita do cliente |
| — | `unaccent` no schema `public` | WARN do advisor do Supabase; mover exige cuidado com o `_vocabulario_por_termo` |

#### Bloco D — v1.1, depois do Demo Day

| # | O que |
|---|---|
| D1 | **Foundation Models multimodal** quando o iOS 27 for público. Substitui toda a via de visão e é grátis |
| D2 | Recortar a peça do fundo antes de treinar (`VNGenerateForegroundInstanceMaskRequest`), se ainda houver modelo local |
| D3 | Referências internas (§30, revogado pelo A7) |
| D4 | Termômetro / validação retroativa (§31) — depende dos dados do Pedro |

---

## Parte 3 — Armadilhas medidas (não redescubra)

1. **PostgREST corta em 1000 linhas por resposta e não avisa.** `limit=2000`
   devolve 1000 caladamente. Foi assim que o coletor de busca concluiu "36 termos
   sem série" quando eram quatro. **Pagine.**
2. **`anon` tem `statement_timeout = 3s`**, `authenticated` 8s, `service_role`
   900s.
3. **A raridade é chaveada por `(categoria, termo_id)`** — 9 linhas por termo.
   Joinar sem recorte multiplica por 9.
4. **Confirme o push ANTES de disparar workflow.** Eu errei isso três vezes e
   duas execuções rodaram no commit errado. `git ls-remote origin refs/heads/main`
   e compare com `git rev-parse HEAD`.
5. **O projeto Xcode usa lista explícita de arquivos** (`project.pbxproj`, sem
   `fileSystemSynchronized`). Arquivo novo precisa ser registrado em quatro
   lugares ou o app não compila com ele.
6. **`swift test` só compila o alvo `CanarioLogica`** (lógica pura, listada no
   `Package.swift`). As telas SwiftUI só compilam pelo `xcodebuild`. Rode os dois.
7. **Regra 7:** 1 req/s por domínio, User-Agent identificável, robots.txt, e
   **recuar de verdade no 429**. Nada de proxy nem header alternativo.
8. **Nada roda na máquina pessoal do JP.** O que precisa de macOS ou de IP
   residencial vai para o **Mac i7** (runner self-hosted, online, labels
   `[self-hosted, macOS, X64]`).

---

## Parte 4 — Estado verificado em 10/08

| O que | Como está |
|---|---|
| Testes Python | 14 suítes, todas verdes |
| Testes Swift | 125, 0 falhas |
| Build iOS | `BUILD SUCCEEDED` no simulador |
| Advisor do Supabase | 0 ERROR; 1 WARN (`unaccent`), 4 WARN de função `security definer` (intencionais, §33), 10 INFO de RLS sem policy (postura correta para tabela só de coletor) |
| `serie_do_cluster` | 49 pontos para vestido+preto+floral — **desenha** |
| `similares_da_peca` | 6 peças, **6 com imagem** |
| Trends | 40/41 termos na semana mais recente |
| Pipeline diário | Vermelho em 09 e 10/08 por 429 da Amaro; portão corrigido, **não garantido verde** |

---

## Parte 5 — Decisões que são do JP e estão em aberto

1. **Data nova do feature freeze** (era 10/08).
2. **Login/conta**: o que exatamente ela habilita além de sincronizar o armário?
3. **Função do Armário** — a "roupagem diferente" que ele mencionou.
4. **Ligar `RUNNER_COLETA`** para a coleta editorial (custo: depende do Mac ligado).
5. **Termos das lojas** para o hotlink de imagem.
6. **Rota da visão**: API no runtime (ponte) ou rotular offline (~$14, permanente).
7. **`editorial_intl`** já virou contexto e não confirma mais direção — vale ele
   conferir na tela se o efeito é o esperado (114 "em alta" → 78).
