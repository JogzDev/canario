# AUDITORIA INICIAL — Canário

**Base:** `CANARIO.md` v1.0 (23/07/2026) + Anexos A, B e C
**Data:** 23/07/2026 | **Autor:** agente (Claude Code)
**Status:** aguardando respostas do JP. Nenhuma linha de código escrita, conforme §2.

A lista **não voltou vazia**. São 6 bloqueadores, 6 contradições internas, 11 constantes ausentes e 7 ambiguidades menores.

---

## Como responder

Responda por código (`B1`, `C3`, ...). Escrever **"ok"** significa aceitar minha recomendação como está. Só preciso de B1–B6 e C1–C6 para começar a F1; as constantes da parte 3 eu assumo pelos valores propostos se você não disser nada, e todas ficam registradas no changelog.

---

## 1. Bloqueadores

Estes impedem começar. Os quatro primeiros são de calendário e de coleta, e cada dia parado é história perdida (§16).

### B1 — Qual a data da Mostra?

O documento dá o calendário completo da AV28 (§10) mas **nunca diz quando é a apresentação**. Isso decide o projeto inteiro, porque §8 exige 8 semanas de história para exibir z-score e a perna de varejo nasce do zero.

Os três marcos de demo não têm a mesma exigência:

| Marco de demo | Precisa de z-score? | Semanas mínimas |
|---|---|---|
| 1. Curva de tamanhos (efeito Ozempic) | Não — é razão descritiva de velocidade | ~4 |
| 2. Divergência oferta x demanda | Sim, nas duas pernas | 8+ |
| 3. Consulta "verde e lilás no masculino" | Não — a graça é exibir o limite | 0 |

**Recomendação:** me diga a data. Se faltarem menos de ~10 semanas para a Mostra a partir do primeiro dia de coleta, o marco 2 não fecha com honestidade e é melhor decidir isso agora do que na véspera — o marco 1 sobrevive com metade do tempo e o marco 3 funciona no dia 1.

### B2 — A coleta de varejo pode começar antes da aprovação da taxonomia?

**Conflito entre duas regras invioláveis.** A regra 4 diz que linhas com status diferente de `aprovado` não entram em coleta — e os 35 termos do Anexo A estão todos `proposto`. Lido ao pé da letra, nada pode ser coletado até sua sessão de aprovação. Mas §16 diz que dado de ruptura não tem passado recuperável.

O ponto técnico: o snapshot de varejo (preço, grade, título) **não depende de termo nenhum**. A taxonomia só entra depois, no casamento título→termo. Já Trends e editorial são consultas por termo e essas sim dependem da aprovação.

**Recomendação:** ler a regra 4 como governando a coleta *por termo* (Trends, matching editorial) e o índice e a tela — e me autorizar a ligar o snapshot de varejo imediatamente. Preciso do seu sim explícito porque é interpretação de regra inviolável (regra 12 me proíbe resolver isso sozinho).

### B3 — O plano gratuito do Supabase não aguenta o volume de snapshots

Conta de guardanapo: ~20 marcas × ~1.500 produtos no segmento ≈ 30 mil linhas de snapshot por dia. Com o jsonb da grade, algo entre 10 e 15 MB/dia. O limite de banco do plano gratuito (500 MB, **a confirmar quando a conta existir** — §33 já manda verificar) enche em torno de 5 a 7 semanas. E a regra 13 proíbe pagar.

Ou seja: no ritmo atual o banco estoura **antes** da Mostra, e provavelmente no meio da coleta.

**Recomendação:** gravar linha de snapshot **só quando algo mudou** em relação ao dia anterior (preço, disponibilidade, grade), mais um batimento semanal por produto. A série diária contínua é reconstruída na leitura por carry-forward. Nada se perde: reposição, remarcação e velocidade de quebra *são* exatamente as transições, e transição é o que fica gravado. Volume cai para ~10%. Preciso do seu ok porque muda o significado da tabela `snapshots` no Anexo D.

### B4 — `segmento` está na marca, mas multimarca cobre todos os segmentos

No Anexo D, `segmento` é coluna de `marcas` e `produtos` não tem nenhuma. Consequência: um vestido da Dafiti (`multimarca_geral`) não consegue ser atribuído a `feminino_casual_br` e portanto **não alimenta a célula termo × segmento × semana** — apesar de §13 tratar multimarca como multiplicador de cobertura.

**Recomendação:** `segmento` passa a ser coluna de `produtos`, derivada por produto a partir do mapa de categorias (B5), com `marcas.segmento` sobrando como padrão. É uma linha de migração agora e uma reescrita de histórico depois.

### B5 — Não existe mapa de categorias por marca

§17 manda "varrer o catálogo do segmento v1", mas nada define como a árvore de categorias de cada site vira `feminino_casual_br`. São ~20 mapeamentos manuais, cada site com nomenclatura própria, e isso está no caminho crítico da F2.

**Recomendação:** eu gero `anexos/mapa_categorias.csv` (`marca, caminho_no_site, segmento, incluir`) a partir do próprio endpoint de categorias de cada site, tudo com `status=proposto`, e você aprova na mesma sessão da taxonomia. Uma sessão sua, dois anexos.

### B6 — Falta o e-mail do User-Agent

A regra 7 exige `CanarioBot/1.0 (projeto academico; contato: email-do-time)` e `email-do-time` é literal no documento. Sem endereço real, a etiqueta de coleta está descumprida no primeiro request.

**Recomendação:** um alias do projeto, não sua caixa pessoal — esse endereço fica público em todo log de servidor que a gente tocar.

---

## 2. Contradições internas

### C1 — "Conta" não existe na v1, mas duas seções configuram coisas "por conta"

§34 proíbe login e conta de usuário. §15 diz que o preset de estação é "configurável por conta"; §30 diz que o arquivo do cliente não sobe ao servidor "(não existe conta de usuário)".

**Recomendação:** ler "conta" como "ajuste local do dispositivo" em toda a v1, e eu corrijo a redação de §15 por entrada ADITIVA no changelog.

### C2 — A exclusividade intra-dimensão não vale em duas das seis dimensões

§11 promete que dentro de uma dimensão os termos são mutuamente exclusivos ("uma peça é midi OU longa"). Não é o que o Anexo A entrega:

- **`modelagem`** mistura dois eixos: comprimento (`curto`, `midi`, `longo`) e silhueta (`flare`, `reta_wide`). Um vestido é midi **e** flare ao mesmo tempo.
- **`tecido`** mistura fibra (`algodao`, `linho`, `viscose_fluido`) com construção (`malha`, `trico_croche`). "Malha de algodão" é os dois.

Isso não é preciosismo: o formulário de confirmação da foto (§28) não pode usar seletor de escolha única onde a dimensão é multivalorada, e o peso de raridade (IDF, §22) conta atributos errado se a cardinalidade por dimensão for tratada como 1.

**Recomendação:** (a) quebrar `modelagem` em `comprimento` e `silhueta` — dois eixos genuinamente distintos, e nenhum `id` muda, então a regra de id estável de §11 é respeitada; (b) adicionar uma coluna `exclusiva` (sim/não) por dimensão, para `tecido` e `cor` poderem ser honestamente multivaloradas (peça bicolor existe). Passa a 7 dimensões.

### C3 — O teste triplo de admissão mata termos que o sistema precisa

§11 diz que o termo só existe se tiver volume detectável no Google Trends BR, e "falhou em um, não entra". Vários `termo_busca` do Anexo A quase certamente ficam abaixo do detectável: `roupa lisa`, `roupa listrada`, `roupa de malha`, `roupa basica`, `roupa branca`.

O problema é que **`liso` é o contrafactual da dimensão estampa**. Sem ele, "share de floral no sortimento" perde denominador e a dimensão inteira fica sem base de comparação. O teste de admissão está eliminando o termo mais estrutural da taxonomia.

**Recomendação:** manter esses termos como `aprovado` e marcá-los `sem_perna_busca` em coluna nova. O índice simplesmente reporta menos pernas ativas — mecanismo que §8 já prevê e a tela já sabe declarar. Isso serve melhor à regra 2 (nunca inventar dado) do que descartar o termo. Preciso do seu ok porque flexibiliza uma regra de §11.

### C4 — O estado `pico` não morre rápido, ao contrário do que o documento afirma

§22 define `pico` como evento pontual que "morre rápido", detectado por z editorial ≥ +2,5 com as demais fontes neutras. Mas §18 dá à perna editorial uma **janela móvel de 4 semanas**. Uma semana viral entra na média e continua dentro dela por 4 semanas — então `pico` acende e fica aceso quase um mês, que é exatamente o oposto do que o estado promete significar.

(A regra das "2 semanas consecutivas" dos estados `em alta`/`em queda` sofre do mesmo efeito, mas ali a exigência de 2 fontes concordando já protege. `pico` é single-source por definição, então fica exposto.)

**Recomendação:** calcular `pico` sobre a contagem editorial **da semana crua**, não sobre a janela de 4 semanas, mantendo a janela para tudo o mais. É a única métrica do sistema que quer sensibilidade em vez de estabilidade.

### C5 — Lyst está dentro de `veiculos.csv` mas §12 lhe dá slot próprio

Se as linhas do Lyst entrarem na soma do share of voice editorial, um agregador global de luxo e streetwear contamina um sinal editorial de mid-market brasileiro.

**Recomendação:** manter a linha no arquivo, mas excluir `tipo=dado_agregado` da perna editorial por construção e dar ao Lyst um valor de `fonte` próprio em `series_semanais`. Ele passa a não atingir o mínimo de 8 semanas por um tempo e a interface o declara inativo — honesto e automático, sem tratamento especial.

### C6 — A lista negra de vocabulário barra rótulos factuais legítimos

§6 proíbe "vender"/"venda" em qualquer texto de interface, e manda implementar um teste automatizado que varre a interface contra a lista. Mas §30 e §31 precisam **exibir** `pct_vendido_preco_cheio` — que é fato passado sobre a coleção do próprio usuário, não previsão. O teste ingênuo reprova "% vendido a preço cheio" e derruba o build.

**Recomendação:** a lista negra proíbe as formas futuras e prescritivas; o teste carrega uma allowlist explícita de rótulos factuais no passado, escrita no próprio arquivo de teste para a exceção ficar auditável e curta. Preciso do seu ok porque é exceção a um Won't Have permanente.

---

## 3. Constantes que o documento exige e não fornece

Assumo os valores propostos se você não responder, e registro todos no changelog.

| # | Parâmetro | Onde | No documento | Proposta |
|---|---|---|---|---|
| K1 | Dias para "saída de linha" | §17, §23 | "N dias" | 14 dias ausente **com o coletor daquele domínio saudável** no período — senão uma queda de site vira saída de linha em massa |
| K2 | "Idade longa no ar" (flag continuativo) | §23 | indefinido | ≥ 26 semanas de presença contínua |
| K3 | "Reposição frequente" | §23 | indefinido | ≥ 3 eventos de reposição em 12 semanas |
| K4 | Profundidade mínima de remarcação | §23 | "queda de preço" | queda ≥ 5% — abaixo disso é arredondamento e cupom, não decisão comercial |
| K5 | Corpus do IDF (raridade) | §22 | indefinido | share de SKUs do painel na semana corrente, no segmento; **fallback de pesos iguais** enquanto varejo não tiver 8 semanas, com a tela declarando que a ponderação por raridade está inativa |
| K6 | Unidade de `{variacao}` no template | §29 | indefinido | variação percentual do valor bruto na janela, com o z entre parênteses. Nunca apresentar z como se fosse porcentagem |
| K7 | Batching de consultas ao Trends | §19 | indefinido | grupos de até 5 termos com **um termo-âncora fixo comum a todos os grupos**, para os níveis ficarem comparáveis; âncora gravada nos metadados da consulta |
| K8 | Entrada do matching editorial | §18 | contraditório | apenas título + resumo do feed. §18 diz "casar título + resumo" mas também "o texto pode ser processado em memória" — título+resumo é uniforme entre veículos e imune a paywall (BoF, WWD e Vogue Business são pagos) |
| K9 | Canal do alerta de saúde | §20 | só arquivo | além do `SAUDE.md`, abrir/atualizar uma issue no próprio repositório privado: grátis, sem serviço novo (regra 13), sem push no app (§34) |
| K10 | Pesos das fontes após o termômetro | §22 vs §31 | ambíguo | o termômetro recalibra **apenas limiares**; pesos seguem iguais na v1 salvo decisão sua no changelog — senão §22 perde a proteção contra curve fitting |
| K11 | Marca em quarentena dentro da série | §35 vs regra 5 | não tratado | série computada sobre coorte fixa de marcas; semana com marca ausente fica marcada, e se a ausência passar de 25% da coorte a célula vira "cobertura insuficiente" em vez de um número enviesado |

---

## 4. Ambiguidades menores

1. **Mínimo de 8 marcas (§8): conta quais?** As marcas `grupo` são proibidas de contar como mercado externo (§13) e `multimarca` não pode ser misturado sem distinção. Sobram 16 candidatas externas no segmento v1 (8 núcleo + 4 adjacente + 4 âncora). Minha leitura é que o mínimo se aplica só às externas. Se o teste dos 30 segundos reprovar metade — e Renner, C&A e Amaro são os candidatos mais prováveis a ter proteção anti-bot — o segmento v1 fica raspando o mínimo. Confirmar a leitura.
2. **Editorial BR vs internacional.** O Anexo C tem 9 veículos brasileiros e 11 internacionais. Com pesos iguais (§22), a imprensa estrangeira decide um índice de mid-market brasileiro. Proposta: duas séries separadas, `editorial_br` e `editorial_intl` — aditivo, e o documento já sabe declarar pernas.
3. **Rastreabilidade do Trends (regra 3).** Não existe "página de origem" por número. Proposta: link para a consulta reconstruída em trends.google.com com os mesmos parâmetros, mais o timestamp de coleta.
4. **Fronteira entre §24 e a regra 1.** §24 permite recomendar composição de grade; §6 proíbe "recomendamos produzir". A diferença é de redação. Proposta: template de grade sempre em proporção e sempre condicional ("se você produzir 100 peças, a grade observada no painel é..."), nunca em unidades absolutas.
5. **`{janela}` no parágrafo-resumo.** O template de §29 põe uma janela de tempo no resumo, mas §27 manda janelas irem para a letra miúda dos insumos. Proposta: seguir §27 e tirar `{janela}` do template.
6. **RLS em views (§33).** Views no Postgres não herdam RLS por padrão. Vou usar `security_invoker` nas views expostas mais policies nas tabelas base. Decido eu, informativo.
7. **Anexos.** Vieram na raiz do zip; o documento os referencia em `anexos/`. Já movidos. Informativo.

---

## 5. Verificado e correto — não gaste tempo aqui

- `0 6 * * *` UTC = 03:00 BRT ✓ (Brasil sem horário de verão desde 2019, então não há deriva sazonal)
- Anexo A: 35 termos, 6 dimensões, ids únicos, nenhum status fora do vocabulário ✓
- Anexo B: 21 marcas em `feminino_casual_br`, dentro do alvo de 15–25 (§13); papéis todos válidos ✓
- Template de referências internas (§30): 10 colunas, confere ✓
- Marco de demo 3 é coerente por construção: `verde` e `lilas_roxo` existem na taxonomia, o masculino não está no painel, então a resposta honesta sai sozinha ✓
- GitHub Free: 2.000 min/mês em repo privado, limite de gasto zero por padrão ✓ (consumo estimado ~300 min/mês)

---

## 6. Uma coisa para pedir ao cliente agora

Nada de novo para a §36, mas com uma ressalva de prazo: a pergunta 3 (**coleção antiga com desfecho conhecido**) é a única resposta do cliente que trava uma fase inteira — sem ela não existe termômetro (§31), e sem termômetro os limiares de §22 ficam sendo chute documentado até o fim do projeto. É também a que depende de alguém lá dentro procurar arquivo. Vale pedir já, mesmo que a F6 esteja longe.

---

## 7. Próximo passo

Parado, conforme §2. Assim que vierem B1–B6 e C1–C6, começo a F1 (repo, secrets, schema, materialização dos anexos).

Se B2 for "sim", ligo o snapshot de varejo em paralelo à F1 em vez de esperar a F2 — cada dia conta e o snapshot não depende de taxonomia aprovada.
