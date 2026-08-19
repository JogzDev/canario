# Passagem de bastão — telas, tendências e curadoria — 13/08/2026

## Leia primeiro

1. `CANARIO.md` é a lei e contém as revogações.
2. `PENDENCIAS.md` é o placar. A navegação de 13/08 virou **NQ1–NQ19**.
3. Este arquivo é a ordem de execução para continuar sem refazer diagnóstico.

Não marque item verde porque existe uma função. Verde exige caminho completo:
dado atualizado, view real, build/teste e evidência no iPhone.

---

## O que entrou neste pacote

### Produto

- O bloco que fingia ser “O que mudou” virou **Tendências da semana**.
- A vitrine recusa leitura com mais de 21 dias. Histórico antigo continua no
  relatório, mas não se apresenta como novidade.
- Os cards são agrupados em Em alta · Destaques editoriais · Estáveis · Em
  queda. A data de atualização fica explícita.
- “+1,56 desvios” deixou de ser o título. A intensidade humana é principal; o
  número estatístico permanece apenas na explicação auditável.
- “vestido de bolinha” e “vestido de poá” preservam a palavra usada pela pessoa
  na apresentação, mas continuam mapeando internamente para `geometrica`.
  **Não renomeie id nem série por causa de copy.**
- O placeholder final “Ainda sem cobertura — peças novas por combinação” saiu.
  Não havia função, prazo nem ação para o usuário.
- O vidro ganhou reflexão, dupla borda e sombras. Ellipsis e X são a mesma view,
  com o mesmo frame e os mesmos recuos.

### Precisão editorial

- `camisa` agora exige contexto de moda no título ou uma segunda evidência de
  vestuário no título+resumo. O perfil do Vini Jr. (“camisa 7”) e a metáfora
  “vestir a camisa da empresa” são regressões locais.
- A regra é deliberadamente estreita. Aplicá-la a todas as categorias sem
  medir recall seria trocar ruído por buraco de cobertura.
- Coleta diária e backfill usam a mesma função.
- **Isto não limpa o banco sozinho.** Para corrigir a série histórica é preciso
  validar o filtro, reprocessar artigos e rodar motor/publicação.

### Verificação já feita

- `swift test`: **134 testes, 0 falhas**.
- Build iOS no simulador: **BUILD SUCCEEDED**.
- Regressões editoriais: **7 casos, 0 falhas**.
- Menu inspecionado no simulador: o vidro tem profundidade e o controle é único.
  A gravação de abrir/fechar no iPhone segue pendente; não transformar em verde
  sem ela.

---

## Ordem de execução recomendada

## P0.1 — Restaurar a credibilidade temporal e editorial

### 1. Medir o filtro antes do backfill

Arquivos:

- `coletor/coletor_editorial.py`
- `coletor/backfill_editorial.py`
- `coletor/teste_contexto_editorial.py`

Trabalho:

1. Sorteie pelo menos 100 matches de `camisa`: metade aceita pelo filtro, metade
   recusada; o revisor não vê a decisão do código.
2. Rotule “moda / não moda”.
3. Exija precisão ≥95% e recall ≥90%. Se falhar, ajuste com exemplos reais e
   regressão — não com uma lista infinita de palavras intuitivas.
4. Só então faça dry-run do backfill, compare contagens semanais e execute a
   publicação completa.

Aceite:

- Vini Jr. não aparece em `meta.exemplos` nem move `camisa`.
- Uma matéria legítima como “6 looks com camisa branca” continua contando.
- Nenhum card da vitrine tem mais de 21 dias; categorias principais alertam aos
  14 dias sem atualização.
- Saúde, motor e app provam a mesma semana operacional em São Paulo.

### 2. Não esconder “sem estado”; recuperar as duas pernas

Hoje “Sem estado” é frequentemente verdadeiro: a série amostrada tinha índice,
mas só uma das duas fontes brasileiras. Não converta nulo em estável.

Trabalho:

- Tornar frescor/cobertura por termo visível no health gate.
- Resolver M3/M4 do `PENDENCIAS.md`: resolução temporal compatível e série
  editorial construída do banco, não somente dos feeds daquela execução.
- Trocar a apresentação por **“Sem direção confirmada”**, com fonte que falta e
  data da última tentativa, depois da decisão final de idioma.

Aceite: estado somente com busca + editorial BR; ausência nomeia a causa.

---

## P0.2 — Transformar Analytics/Search no produto principal

O destino é uma única tela de tendências da semana, não dois fluxos soltos.

### Arquitetura de informação

1. Cabeçalho: “This week in fashion” (copy final depende de A16).
2. Barra de busca fixa que filtra enquanto a pessoa digita.
3. Filtros: categoria, estado e recência.
4. Feed: Em alta · Estáveis · Em queda; “destaque editorial isolado” é contexto,
   não sinônimo de tendência confirmada.
5. A busca preserva a expressão humana (“polka-dot dress”) e mostra o rótulo
   técnico somente se ele ajudar, nunca “Vestido + Geométrica e étnica”.
6. Toque abre relatório conjunto, histórico, evidências e similares.

Arquivos iniciais:

- `app/Canario/Telas/Explorar.swift`
- `app/Canario/Telas/Analisar.swift`
- `app/Canario/Rede/Traducao.swift`
- `app/Canario/Telas/RelatorioDaPeca.swift`

Aceite:

- “vestido de bolinha” vira frase natural e resultado pesquisável.
- A mesma consulta nunca mostra “semana de 13/07” como tendência atual em agosto.
- Busca, filtro e rolagem funcionam sem remontar todas as abas nem tela preta.
- VoiceOver anuncia estado, data e cobertura.

---

## P0.3 — Fechar telas e linguagem antes de embelezar mais

### Menu

Os seis botões hoje ainda levam a alertas provisórios. Não reescreva o alerta:
implemente a tela ou retire a ação do build de demonstração até ela existir.

- **Favorites:** decidir se são peças do Closet ou produtos do painel.
- **Account:** somente depois do escopo de sincronização e RLS.
- **Terms:** termos reais, revisados; não inventar texto jurídico.
- **Settings:** permissões, dados e conta que realmente existam.
- **Privacy:** câmera/fotos, miniatura local, OpenAI, Supabase, hotlink, retenção,
  exportação e exclusão.
- **Q&A:** respostas factuais sobre índice, estado, atualização e análise da foto.

Arquivos:

- `app/Canario/Telas/MenuLateral.swift`
- `app/Canario/CanarioApp.swift`

### Figma → app

Crie uma matriz para cada frame: view, estados (loading/vazio/erro/sucesso),
copy, ação, fonte do dado e screenshot de aceite. Prioridade:

1. add/import/confirm/loading;
2. Clothing DNA/relatório — renomear se a promessa continuar maior que o dado;
3. detalhes da peça e tendências;
4. menu;
5. login/cadastro somente quando conta estiver metodologicamente fechada.

### Idioma

A16 determina inglês. Não traduza string por string dentro das views. Migre para
catálogo/localização, escolha o nome (Label/Labl/Stitched ainda estão abertos) e
faça revisão humana. O pacote atual melhora a semântica em português porque era
o texto em produção; ele **não revoga A16**.

---

## P1 — Taxonomia sem multiplicar ruído

`blusa_top` hoje contém blusa, top, cropped, regata, camiseta e t-shirt. É uma
fronteira larga; o incômodo do JP é legítimo. Também é verdade que dividir agora
não corrige automaticamente as cinco divergências do Luna: várias eram conjunto
ou alvo não visível.

### Protocolo

1. Monte distribuição de títulos/imagens por termo candidato: camiseta, blusa,
   top/cropped, regata, body; considere também blazer/casaco, bermuda/short e
   conjunto como problemas separados.
2. Faça dupla rotulação de amostra cega e matriz de confusão.
3. Cada categoria nova precisa:
   - definição visual positiva e fronteiras negativas;
   - volume suficiente no painel;
   - matcher com precisão medida;
   - cobertura de busca/editorial ou declaração de que será apenas atributo
     visual, sem índice;
   - migração/alias que preserve o histórico.
4. Nunca troque o significado de `blusa_top` no lugar. Deprecie/alie e
   reclassifique de forma versionada.

Portão: classes visualmente exclusivas, concordância humana ≥90% e Luna medida
no holdout. Categoria sem série não recebe estado só porque a API escreveu bem.

---

## P1 — Mais marcas, mas com curadoria

O CSV já registra marcas que funcionam, falharam e cumprem papéis distintos.
Comece por `anexos/painel_marcas.csv`; não redescubra endpoints já reprovados.

### Matriz obrigatória

Para cada candidata, registre:

- Brasil/internacional;
- núcleo/adjacente/âncora/direção;
- faixa de preço e categorias cobertas;
- plataforma e rota pública documentada;
- robots/termos, teste de 30 s e estabilidade por 7 dias;
- valor marginal: qual célula ela melhora?

As internacionais medem **direção/contexto**, nunca confirmam sozinhas o índice
do mercado brasileiro. Quantidade de logos não é cobertura.

Aceite: marca só entra após sete coletas saudáveis, mapeamento de tamanhos e
prova de que não derruba a célula por ausência estrutural.

---

## P1 — Imagem limpa com limites honestos

### Foto do usuário

A19 já usa `VNGenerateForegroundInstanceMaskRequest`, em memória, e salva PNG
transparente sem EXIF. Falta o ensaio físico:

- 24 fotos: fundo liso/ocupado, cabide, manequim, corpo, conjunto, oclusão;
- medir preservação da peça, halo e fallback;
- manter `Replace photo` sempre disponível.

### Foto das lojas

Similar, reposição e remarcação são hotlinks. Remover fundo no servidor criaria
uma cópia/derivado que A13 não autorizou. Ordem segura:

1. armazenar/receber múltiplas URLs oficiais quando a plataforma oferecer;
2. selecionar em memória a foto mais limpa com enquadramento/OCR medidos;
3. avaliar segmentação **no aparelho e sem persistir**;
4. medir latência, memória, halo, cache e termos das lojas.

Nunca esconder marca d'água ou texto de titularidade. Se não houver foto limpa,
o bloco visual continua sendo o fallback honesto.

---

## P2 — Sinais internacionais: pesquisa atual, não autorização automática

### 1. Google Trends API alpha — melhor evolução estrutural

Fonte oficial: <https://developers.google.com/search/apis/trends>

- janela móvel de cinco anos;
- agregação diária/semanal/mensal/anual;
- escala consistente entre requisições;
- regiões/sub-regiões;
- acesso ainda limitado a candidatos do alpha.

Ação: inscrever o caso do Canário. Só migrar quando houver acesso e comparação
lado a lado com o coletor atual; a mudança de escala exige recalibração.

### 2. Pinterest Trends — piloto de pesquisa visual

Fonte oficial: <https://help.pinterest.com/pt-br/business/article/pinterest-trends>

- até dois anos de busca, salvamentos e compras;
- recortes por região, semanal/mensal/anual e sazonalidade;
- alguns recursos dependem de conta/país e ainda estão em teste.

Ação: validar se Brasil e termos da taxonomia têm cobertura e se existe rota de
uso/exportação autorizada. O help prova a ferramenta, **não uma API pública**.
Não automatizar a interface.

### 3. TikTok Creative Center — descoberta, não perna confirmatória

Fonte oficial: <https://ads.tiktok.com/help/article/how-to-use-trends?lang=en>

Mostra hashtags por indústria, período, região, linha, vídeos e público. Ação:
piloto manual com rubrica de relevância fashion; só automatizar com API/termos
documentados. Hashtag viral mede atenção, não intenção de compra.

### 4. Lyst Index — contexto trimestral

Fonte oficial: <https://www.lyst.com/data/the-lyst-index/>

É trimestral e combina buscas, views, vendas e sinais sociais globais. Já está
classificado como `dado_agregado`; não deve ser somado à série semanal nem
confirmar direção BR. Serve para card contextual/curadoria internacional.

---

## P2 — Luna, relatório e privacidade

O próximo gasto permitido é repetir as mesmas 24 com prompt `alvo-estrutura-v3`.
Categoria e cor primária precisam fazer **20/24 separadamente**. Só então o
holdout de 300 abre. Meta final: 90%+, com intervalo de confiança reportado.

No runtime:

- foto redimensionada e sem metadados;
- chamada pela Edge Function; chave nunca no app;
- formulário humano continua sendo a verdade salva;
- texto recebe somente fatos calculados e nunca inventa número/estado;
- fallback local funciona se API falhar;
- disclosure não promete retenção zero.

Conta/sincronização exige Supabase Auth, RLS por usuário, exclusão, exportação e
ficha de privacidade antes de login/cadastro entrar na navegação.

---

## Comandos de verificação

```bash
cd app && swift test
cd app && xcodebuild -project Canario.xcodeproj -target Canario \
  -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
python3 coletor/teste_contexto_editorial.py
python3 coletor/teste_workflows.py
git diff --check
```

Rode também as suítes Python que o workflow lista em
`.github/workflows/testes.yml`. Teste de UI no simulador não substitui iPhone
para câmera, recorte, transparência, desempenho e aparência do vidro.

---

## Armadilhas que continuam valendo

- PostgREST devolve no máximo 1000 linhas sem avisar: pagine.
- `anon` tem timeout de 3 s; RPC pública precisa caber nele.
- Raridade é `(categoria, termo_id)`; join sem categoria multiplica linhas.
- Confirme o SHA remoto antes de workflow manual.
- Arquivo Swift novo precisa entrar nos quatro pontos do `project.pbxproj`.
- Regra 7: 1 req/s por domínio, UA identificável, robots e backoff real.
- Nada pesado no Mac pessoal; use o i7 self-hosted.
- Não inclua chave OpenAI nem JSON privado em commit/log.
- Preserve alterações alheias já existentes no `project.pbxproj`.
- Não transforme ausência de duas fontes em “estável”.
- Não trate volume editorial internacional como confirmação do mercado BR.

---

## Próxima ação concreta

Comece em **NQ1/NQ2**: crie o amostrador cego dos 100 matches editoriais,
meça o filtro e só então reprocese o histórico. Em paralelo de produto, desenhe
a estrutura única de Analytics/Search descrita em P0.2. É a menor sequência que
faz o app parecer mais bonito **e** torna verdadeiro o que ele afirma.
