# Fontes oficiais internacionais — veredito de viabilidade

Revisão em **13/08/2026**, baseada apenas na documentação oficial de cada
plataforma. O objetivo não é aumentar o painel por quantidade: cada fonte só
entra se acrescentar um sinal definido, reproduzível e permitido.

## Resumo executivo

| Fonte | O que mede | Acesso real hoje | Veredito |
|---|---|---|---|
| Google Trends API (alpha) | interesse de busca | inscrição já enviada; acesso limitado e sem SLA de aprovação | **Manter como substituição prioritária**, mas não pode sustentar a operação hoje |
| Pinterest Trends API | intenção/inspiração visual e busca dentro do Pinterest | conta Business, app aprovado e OAuth; até 50 tendências atuais; confirmar `trends_read` no token concedido | **Melhor candidata nova; fazer piloto após aprovação Trial** |
| Guardian Open Platform | publicação editorial, filtrável por seção/tag | chave gratuita para uso não comercial, 500 chamadas/dia | **Recusado em 23/09/2026**: os termos proíbem mineração para tendências e guardar conteúdo por mais de 24 horas (ver §3) |
| YouTube Data API | publicação/engajamento em vídeo | chave Google; 100 buscas/dia por padrão | **Não priorizar**: muita capacidade de busca, pouco controle de relevância e viés de creator |
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

## 2. Pinterest Trends — candidata recomendada

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

### Plano de piloto, sem misturar métodos

1. Criar conta Pinterest Business e registrar o app Canário com política de
   privacidade pública.
2. Solicitar **Trial access**, confirmar que o token concedido inclui
   `trends_read` e só então gerar o teste. A documentação pública separa o
   endpoint dos níveis de acesso; não presumir que toda aprovação Trial libera
   esse escopo. Nenhum segredo entra no app nem no repositório; só GitHub Secret.
3. Consultar `BR/top/growing` uma vez por semana por quatro semanas.
4. Traduzir palavras retornadas para a taxonomia já aprovada; nunca fazer o
   inverso nem inventar correspondência por embedding.
5. Medir cobertura e precisão humanas antes de exibir. Pinterest nasce como
   perna separada (`pinterest`), não como `busca` e não confirma estado até a
   metodologia ser aprovada no CANARIO.md.

## 3. Guardian Open Platform — editorial adicional

O Guardian oferece API oficial por seção/tag. O tier Developer é gratuito para
uso não comercial, com 1 requisição/s e 500/dia. Para o TCC, basta uma consulta
diária ou semanal à seção fashion e guardar o mesmo mínimo já autorizado para
RSS: título, URL, veículo e data — nunca o texto integral.

- Acesso: <https://open-platform.theguardian.com/access/>
- Documentação: <https://open-platform.theguardian.com/documentation/>

Decisão de 13/08: **tecnicamente viável**, com inclusão em `veiculos.csv`
dependendo da aprovação nominal do JP (§14).

**Recusado em 23/09/2026, depois de ler os termos inteiros** (Open Platform
Terms, lidos na página oficial nessa data). O JP aprovou a entrada e perguntou
se a publicação na App Store mudava algo. A App Store não é o problema.
O problema é o que o editorial faz:

- os termos proíbem usar o conteúdo, a API ou a rede digital do Guardian
  (que inclui os RSS) para fins de "text and data aggregation, analysis or
  mining", inclusive para gerar padrões e tendências, e para fins de IA. A
  perna editorial é exatamente isso: conta matérias por termo e semana para
  achar tendência, e a Luna lê o resultado;
- os termos exigem apagar ou renovar todo conteúdo obtido a cada 24 horas. A
  série editorial guarda título, URL, veículo e data por semanas;
- o tier gratuito é só para uso não comercial. O comercial é negociado caso
  a caso, mas não resolve os dois pontos acima, que valem para qualquer tier.

Não entra nem pela API nem pelos RSS do Guardian. Outra fonte editorial
internacional precisa ter os termos lidos com a mesma pergunta, antes da
sonda técnica: **pode contar para achar tendência, e pode guardar a contagem
por meses?**

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

### YouTube Data API

O `search.list` é oficial e permite busca por palavra, mas o padrão atual é 100
buscas/dia e os resultados misturam moda, publicidade, entretenimento e texto
incidental. Sem uma lista curada de canais e uma validação de precisão, ele
recria em escala maior o problema da matéria “camisa 7”.

- <https://developers.google.com/youtube/v3/docs/search/list>

## Próxima decisão do JP

Autorizar ou recusar as duas candidaturas que fazem sentido:

1. **Pinterest Trial** para um piloto de quatro semanas (recomendado).
2. **Guardian Developer** como novo veículo editorial internacional.

Nenhuma delas deve bloquear o app atual. Google continua sendo a fonte de
busca existente; Pinterest seria uma perna nova, e Guardian amplia somente o
editorial internacional.
