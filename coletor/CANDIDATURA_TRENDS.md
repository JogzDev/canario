# Candidatura ao alpha da Google Trends API — texto pronto

**Para o JP submeter hoje.** O formulário do alpha costuma ser em inglês, então
o caso de uso vai em inglês abaixo, com a versão em português logo em seguida
para conferência. Preencha os campos do formulário com os trechos
correspondentes. A latência de aprovação é o motivo da pressa: submeter cedo é o
que importa, mesmo que o texto seja ajustado depois.

Dados de contato a usar: `canarioch3@gmail.com`.

---

## Use case (English — paste into the form)

**Project name:** Canário

**Organization / context:** Academic capstone project at the Apple Developer
Academy (Brazil). Non-commercial, student-built.

**What we are building:** An iOS app that helps fashion retail teams read the
Brazilian womenswear market with organized, traceable evidence. The app informs
decisions about collections, buying and replenishment. It explicitly does **not**
forecast sales, assign probabilities, or recommend production volumes — it
reports relative, sourced signals only.

**How we would use the Trends API:** Google Trends is one of three measurement
legs in our index, alongside our own public-catalog retail collector and an
editorial share-of-voice signal. We query a **fixed, closed list of ~35
Portuguese fashion terms** (garment categories, prints, fabrics, silhouettes and
color families — e.g. *vestido floral*, *alfaiataria feminina*, *tricô*),
**geo = BR**, on a **weekly cadence**. On first run we backfill **5 years** of
history per term to establish each term's seasonal baseline; after that, one
weekly incremental pull per term. All queries share a fixed anchor term so
levels stay comparable across pulls, and we store the query metadata (interval,
geo, collection date) with every series because Trends values are relative to
the query.

**Volume:** ~35 terms, weekly. Well within any reasonable rate limit. We cache
aggressively and never re-query unchanged windows.

**Why the official API (vs. scraping):** We want a stable, terms-of-service-
compliant source. The project's design rules forbid circumventing protections or
using unofficial endpoints as a permanent solution; the official API is the
correct long-term path.

**Data handling:** Only aggregated Trends series are stored, on our own backend
(Supabase/Postgres). No personal data is involved. Series are shown in the app
with a link back to the equivalent Trends query and the collection timestamp, so
every number is traceable to its source.

**Feedback to the product:** As an active academic project with a model client
from fashion retail, we can provide structured feedback on the API's fit for
seasonal-trend measurement use cases.

**Contact:** canarioch3@gmail.com

---

## Caso de uso (português — para conferência)

**Projeto:** Canário — trabalho de conclusão acadêmico na Apple Developer
Academy (Brasil), não comercial, feito por estudantes.

**O que é:** app iOS que ajuda times de varejo de moda a ler o mercado de moda
feminina brasileiro com evidência organizada e rastreável, para decisões de
coleção, compra e reposição. O app **não** prevê vendas, não atribui
probabilidade e não recomenda volume — só reporta sinal relativo e com fonte.

**Uso do Trends:** é uma das três pernas de medição do índice, ao lado do
coletor próprio de varejo (catálogo público) e do sinal editorial. Consultamos
uma **lista fechada de ~35 termos de moda em português** (categorias, estampas,
tecidos, silhuetas e famílias de cor), **geo = BR**, em **cadência semanal**. Na
primeira execução, backfill de **5 anos** por termo para fixar a linha de base
sazonal; depois, uma consulta incremental semanal por termo. Todas as consultas
compartilham um termo-âncora fixo para os níveis serem comparáveis entre coletas,
e guardamos os metadados da consulta (intervalo, geo, data) em cada série,
porque valores do Trends são relativos à consulta.

**Volume:** ~35 termos por semana. Muito abaixo de qualquer limite razoável.
Cache agressivo, sem reconsulta de janela que não mudou.

**Por que a API oficial:** queremos fonte estável e dentro dos termos de uso. As
regras do projeto proíbem burlar proteção ou depender de endpoint não oficial em
definitivo; a API oficial é o caminho certo de longo prazo.

**Dados:** só séries agregadas, no nosso backend (Supabase/Postgres). Nenhum dado
pessoal. Cada número no app tem link para a consulta equivalente no Trends e o
carimbo de data da coleta.

**Contato:** canarioch3@gmail.com

---

## Enquanto o alpha não sai (§19)

O plano B já está no documento e não depende desta candidatura: `pytrends` com
cache agressivo, retry com backoff exponencial e cadência semanal; se quebrar de
vez, exportação manual de CSV do site do Trends, com o agente gerando a lista
exata de consultas. A candidatura é o caminho oficial de longo prazo; a coleta
de busca não fica bloqueada esperando por ela.
