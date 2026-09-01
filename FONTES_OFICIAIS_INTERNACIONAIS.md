# Fontes oficiais internacionais — veredito de viabilidade

Revisão corrigida em **18/08/2026**, baseada apenas na documentação oficial de cada
plataforma. O objetivo não é aumentar o painel por quantidade: cada fonte só
entra se acrescentar um sinal definido, reproduzível e permitido.

## Resumo executivo

| Fonte | O que mede | Acesso real hoje | Veredito |
|---|---|---|---|
| Google Trends API (alpha) | interesse de busca | inscrição já enviada; acesso limitado e sem SLA de aprovação | **Manter como substituição prioritária**, mas não pode sustentar a operação hoje |
| Pinterest Trends API | intenção/inspiração visual e busca dentro do Pinterest | endpoint oficial e `trends_read` não bastam: pesquisa de plataforma exige autorização escrita para o uso declarado | **Bloqueada** até autorização expressa para análise comercial e IA |
| Guardian Open Platform | publicação editorial, filtrável por seção/tag | Developer é somente não comercial; o produto precisa de chave e licença **Commercial** negociadas | **Condicionada à licença comercial**, sem confirmar demanda |
| YouTube Data API | publicação/engajamento em vídeo | chave Google; 100 buscas/dia por padrão; permite restringir por canal | **Candidata condicionada** a canais curados, políticas e validação de precisão |
| Wikimedia Analytics | visualizações de verbetes | aberta, sem chave | **Não usar no índice de moda**: mede consulta enciclopédica, não procura por produto/estilo |
| TikTok Research API | conteúdo e métricas públicas | no Brasil, elegibilidade oficial está limitada a pesquisa de segurança juvenil por instituição acadêmica/sem fins lucrativos | **Inviável para o Canário** |

## 1. Google Trends oficial

A API oficial segue em alpha e aceita inscrições. Ela promete cinco anos de
dados, agregações diária/semanal/mensal/anual, recortes regionais e escala
consistente entre requisições. Isso eliminaria exatamente a fragilidade do
endpoint privado atual: não seria necessário refazer toda a janela nem agrupar
termos em lotes normalizados separadamente.

- Documentação: <https://developers.google.com/search/apis/trends>
- Estado: **aguardando resposta da candidatura do JP**.
- Decisão: o coletor atual fica como ponte de baixa cadência e com circuit
  breaker. Recusa 429 não autoriza disfarçar User-Agent, trocar proxy ou repetir
  imediatamente. Quando a alpha for concedida, migrar e fazer uma sobreposição
  mínima de quatro semanas antes de trocar a série.

## 2. Pinterest Trends — bloqueada até autorização escrita

A API oficial retorna palavras em crescimento por região, `pct_growth_wow`,
`pct_growth_mom`, `pct_growth_yoy` e uma série semanal de um ano normalizada de
0 a 100. O endpoint documentado é
`GET /v5/trends/keywords/{region}/top/{trend_type}`. A resposta é limitada a 50
tendências e representa a data atual; não existe consulta retroativa arbitrária.

- Trends: <https://developers.pinterest.com/docs/analytics-and-reports/trends/>
- Acesso: <https://developers.pinterest.com/docs/getting-started/connect-app/>
- Tiers: <https://developers.pinterest.com/docs/key-concepts/access-tiers/>
- Rate limit documentado para `trends_read`: 1.000/dia no Trial, 60/minuto no
  Standard. Uma chamada semanal por região fica muito abaixo disso.

Esses fatos provam que o endpoint existe; não provam que o Canário pode usá-lo.
As Developer Guidelines vedam plataforma insights, benchmarking ou pesquisa de
concorrentes sem autorização escrita do Pinterest e também vedam scraping e uso
de Pinterest Materials para desenvolver ou melhorar modelos de IA sem permissão
expressa. Aprovação de app, Trial e escopo `trends_read` são controles técnicos,
não essa autorização de finalidade.

- Developer Guidelines: <https://policy.pinterest.com/en/developer-guidelines>
- Estado no registro executável: **`red`**.

### Sequência para um eventual piloto, sem misturar métodos

1. Descrever por escrito o produto comercial, os fatos pretendidos, a passagem
   minimizada pela Luna, exibição e retenção; obter autorização expressa do
   Pinterest para esse escopo antes de coletar.
2. Criar conta Pinterest Business e registrar o app Canário com política de
   privacidade pública.
3. Solicitar **Trial access**, confirmar que o token concedido inclui
   `trends_read` e só então gerar o teste. A documentação pública separa o
   endpoint dos níveis de acesso; não presumir que toda aprovação Trial libera
   esse escopo. Nenhum segredo entra no app nem no repositório; só GitHub Secret.
4. Consultar `BR/top/growing` uma vez por semana por quatro semanas sem persistir
   o payload além do prazo autorizado.
5. Traduzir palavras retornadas para a taxonomia já aprovada; nunca fazer o
   inverso nem inventar correspondência por embedding.
6. Medir cobertura e precisão humanas antes de exibir. Pinterest nasce como
   perna separada (`pinterest`), não como `busca` e não confirma estado até a
   metodologia ser aprovada no CANARIO.md.

Sem o primeiro passo, os demais não formam um plano autorizado e não promovem a
linha para `yellow` ou `green`.

## 3. Guardian Open Platform — condicionada a Commercial

O Guardian oferece API oficial por seção/tag. O tier Developer é gratuito para
uso não comercial, com 1 requisição/s e 500/dia. Esse tier pode cobrir uma
dissertação isolada; não cobre o runtime nem a pesquisa de um produto comercial.
O próprio Guardian direciona empresas e qualquer produto derivado de seu
conteúdo — inclusive mineração, análise sem reprodução e IA generativa — ao
tier Commercial, com preço, quota e escopo negociados.

- Acesso: <https://open-platform.theguardian.com/access/>
- Documentação: <https://open-platform.theguardian.com/documentation/>

Decisão: **`yellow` até chave e licença Commercial assinadas para o uso exato**.
Mesmo título, URL, veículo e data não ganham licença comercial por serem um
pacote pequeno. Depois da licença, sua inclusão em `veiculos.csv` ainda precisa
da aprovação nominal do JP (§14), retenção contratada e teste de deleção. Ele
melhora diversidade editorial internacional; não mede intenção de compra e não
deve ganhar peso de busca.

## 4. Fontes rejeitadas ou apenas exploratórias

### TikTok

A página oficial limita os candidatos brasileiros a instituições acadêmicas ou
sem fins lucrativos pesquisando segurança juvenil, exige proposta, independência
comercial, proteção de dados e revisão ética. O Canário é um produto de moda;
forçar o enquadramento seria incompatível com o uso declarado.

- <https://developers.tiktok.com/products/research-api/>

### Wikimedia Analytics

A API é aberta e multilíngue, mas conta pageviews de páginas da Wikipédia. Isso
é atenção enciclopédica: uma alta de “tweed” pode vir de história, cinema ou uma
personalidade, sem relação com desejo por roupa. Pode servir futuramente para
pesquisa exploratória, nunca como perna do índice.

- <https://doc.wikimedia.org/generated-data-platform/aqs/analytics-api/documentation/getting-started.html>

## 5. YouTube Data API — candidato condicionado

O `search.list` é oficial e permite busca por palavra, mas o padrão atual é 100
buscas/dia e uma busca aberta mistura moda, publicidade, entretenimento e texto
incidental. O parâmetro `channelId` permite restringir a descoberta a canais
previamente selecionados; portanto a API não precisa ser rejeitada por desenho,
mas uma consulta aberta também não pode ser liberada por conveniência.

Estado: **`yellow`**. Um piloto só abre após lista de canais profissionais
curada por humanos, rubrica que separe publicação de creator de adoção, amostra
de precisão aprovada, política de privacidade compatível com YouTube e definição
de retenção/exibição. Apenas metadados oficiais minimizados podem ser avaliados;
comentários, thumbnail, vídeo, download e scraping ficam fora. O sensor nasce
separado e nunca vira confirmação de busca ou varejo por soma de engajamentos.

- <https://developers.google.com/youtube/v3/docs/search/list>
- <https://developers.google.com/youtube/terms/developer-policies>

## Próxima decisão do JP

Decidir sobre as três diligências que fazem sentido, sem liberar coleta ainda:

1. Pedir ao Pinterest autorização escrita para análise comercial e o escopo de
   IA; Trial sozinho não basta.
2. Solicitar proposta **Guardian Commercial** e avaliar licença, preço, retenção
   e deleção.
3. Aprovar ou recusar a montagem manual da allowlist e da amostra cega do
   YouTube; chave de API sozinha não abre o piloto.

Nenhuma delas deve bloquear o app atual. Pinterest permanece `red`; Guardian e
YouTube permanecem `yellow`; Google continua sendo a fonte de busca existente.
Se autorizadas no futuro, Pinterest e YouTube seriam pernas novas e separadas,
e Guardian ampliaria somente o editorial internacional.
