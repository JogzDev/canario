# Governança de fontes — Market Intelligence 1.3

| Campo | Valor |
|---|---|
| Versão do contrato | `1.0.0` |
| Vigência | 31/08/2026 |
| Escopo | Radar e relatório de Market Intelligence da versão 1.3 |
| Registro executável | `anexos/fontes_radar.csv` |
| Regra de segurança | **fail closed**: o que não estiver expressamente liberado é bloqueado |

Este documento é o contrato operacional entre descoberta, coleta, Scout,
normalização, Luna, revisão humana e publicação. Ele não substitui parecer
jurídico; transforma as permissões já verificadas em controles que o produto
consegue aplicar e auditar.

## 1. Princípios que não podem ser flexibilizados

1. Uma página ser pública não concede licença para copiar, minerar, treinar IA
   ou redistribuir seu conteúdo.
2. `robots.txt` orienta crawlers; não substitui Termos de Uso, licença,
   copyright ou base legal de privacidade.
3. API oficial não significa uso automaticamente autorizado. O escopo aprovado,
   o tipo de conta, a finalidade e as regras de retenção também precisam bater.
4. A Luna só recebe material depois do portão de direitos. Busca, modelo ou
   prompt nunca servem para contornar um bloqueio de fonte.
5. Texto, foto, vídeo, thumbnail e screenshot de terceiros não entram no app por
   padrão. O padrão visual é gráfico próprio, ficha factual e link canônico.
6. Sinais de fenômenos diferentes permanecem separados. Busca, inspiração,
   publicação de creators, cobertura editorial e varejo não viram uma soma de
   engajamentos incompatíveis.
7. A versão 1.3 não publica automaticamente. Toda edição passa por revisão
   humana até existir um portão de qualidade aprovado em amostra nova.

## 2. Fonte de verdade e precedência

`anexos/fontes_radar.csv` é a fonte de verdade legível por máquina. Uma nota em
outro documento, um segredo disponível ou um coletor antigo não libera uma
fonte ausente ou bloqueada no registro.

No espelho SQL, `registro_sha256` é o SHA-256 dos bytes exatos do CSV e
`contrato_sha256` é o SHA-256 do objeto JSON formado por todos os campos da
linha, com chaves em ordem lexicográfica, UTF-8, `ensure_ascii=false` e
separadores compactos `(',', ':')`. Esses hashes não são colunas editáveis do
CSV: a migração os deriva e os fixa, e o teste de paridade recalcula ambos.

Em caso de conflito, vale a regra mais restritiva nesta ordem:

1. lei, ordem ou obrigação regulatória aplicável;
2. contrato, autorização escrita ou Termos de Uso da fonte;
3. linha vigente de `anexos/fontes_radar.csv`;
4. este contrato;
5. configuração de execução.

Nenhuma variável de ambiente, opção de linha de comando ou fallback pode
promover `yellow` ou `red` para `green` em runtime.

## 3. Taxonomia de tier e status

Tier descreve a natureza do acesso; status decide se ele pode operar. São eixos
independentes: uma API `T1` pode estar `red`.

| Tier | Significado | Exemplos |
|---|---|---|
| `T0` | conteúdo próprio ou acesso diretamente contratado/autorizado | curadoria DataDrobe, feed de cliente com autorização escrita |
| `T1` | API oficial ou feed com licença explícita | Google Trends alpha, YouTube Data API |
| `T2` | web pública usada sob limites específicos | RSS para descoberta, página de produto com dados estruturados |
| `T3` | método incompatível, inelegível ou sem autorização suficiente | scraping social, paywall, endpoint privado, download de vídeo |

| Status | Efeito obrigatório |
|---|---|
| `green` | elegível somente para o método e os campos autorizados na linha |
| `yellow` | quarentena: descoberta/manual é permitida quando indicada, mas Scout e Luna não processam automaticamente |
| `red` | rejeitado por padrão; nenhuma coleta, processamento, retenção ou fallback |

Ausência de linha, campo obrigatório vazio, valor desconhecido, revisão de termos
vencida ou redirecionamento para domínio fora da allowlist equivalem a `red`.

## 4. Contrato do CSV

Cada linha representa uma combinação de fonte e método. A mesma plataforma pode
ter uma linha oficial e outra proibida; isso impede que uma falha de API caia
silenciosamente para scraping.

Campos obrigatórios:

| Campo | Contrato |
|---|---|
| `id` | identificador ASCII estável e único |
| `nome` | nome humano da fonte/método |
| `sensor` | fenômeno medido, nunca um sinônimo de plataforma |
| `tier` | `T0`, `T1`, `T2` ou `T3` |
| `metodo` | via de aquisição autorizada ou rejeitada |
| `status` | `green`, `yellow` ou `red` |
| `ai_processing` | `none`, `facts` ou `full_text` |
| `openai_retention_mode` | `none` ou `standard_30d`; qualquer outro valor exige nova versão do schema |
| `display_rights` | forma máxima de exibição; não implica direito além dela |
| `retencao_dias` | máximo de dias do payload bruto; `0` significa não persistir |
| `retencao_fatos_dias` | máximo de dias dos fatos normalizados; `0` significa não persistir |
| `base_url` | origem HTTPS canônica permitida; vazia somente em `T0` com `metodo=curadoria_interna`, que nunca entra no Scout web |
| `url_scope` | `internal`, `exact_host` ou `domain_tree`; nunca é inferido a partir do nome da fonte |
| `termos_url` | documento primário HTTPS que governa o uso; na curadoria interna, este próprio contrato local |
| `termos_versao` | versão, data efetiva ou identificação da autorização revisada |
| `termos_revisados_em` | data ISO da última leitura humana dos termos |
| `autorizacao_sha256` | SHA-256 da evidência de autorização aprovada; obrigatório em `green` |
| `aprovada_por` | identificador nominal do responsável pela promoção a `green` |
| `aprovada_em` | data ISO da aprovação |
| `autorizacao_expira_em` | data ISO em que a autorização deixa de valer; o início desse dia já bloqueia a fonte |
| `observacao` | condição, escopo ou ação pendente que não cabe nos enums |
| `ativa` | `true` ou `false`; uma linha inativa permanece auditável, mas nunca autoriza execução |

O cabeçalho e a ordem contratual são exatos; coluna ausente, extra ou reordenada
falha fechada para impedir que uma mudança de schema seja interpretada pela
versão errada do gate:

```text
id,nome,sensor,tier,metodo,status,ai_processing,openai_retention_mode,display_rights,retencao_dias,retencao_fatos_dias,base_url,url_scope,termos_url,termos_versao,termos_revisados_em,autorizacao_sha256,aprovada_por,aprovada_em,autorizacao_expira_em,observacao,ativa
```

IDs obedecem a `[a-z0-9]+(?:[._-][a-z0-9]+)*`. Retenções são inteiros não
negativos, datas usam `AAAA-MM-DD`, e os enums de tier, status,
`ai_processing`, `openai_retention_mode`, `display_rights`, `url_scope` e `ativa` são
fechados. Linha inválida nunca é silenciosamente ignorada: invalida o registro
carregado por aquela execução.

IDs têm no máximo 80 caracteres; nome 160; sensor 80; método 120; versão de
termos 160; observação 2.000; URLs 2.048. `retencao_dias` não pode exceder 90 e
`retencao_fatos_dias` não pode exceder 3.650. A aprovação é preenchida como um
bloco indivisível; fonte `green` sem hash SHA-256, responsável, data e validade
futura falha fechada.

Na linha interna `datadrobe_curadoria_interna`, a evidência de autorização é
este próprio documento: `autorizacao_sha256` contém o SHA-256 dos bytes exatos
do arquivo UTF-8
`GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md`. O digest não é reproduzido no
documento e existe somente no registro executável; assim o cálculo não contém
autorreferência. Qualquer alteração, inclusive espaço ou quebra de linha, muda
o digest e faz o teste de integridade falhar até uma nova revisão humana,
atualização do bloco de aprovação e recálculo do hash. O hash atesta a versão
aprovada do contrato, não substitui assinatura jurídica nem prova direitos
sobre conteúdo de terceiros.

`ai_processing` tem semântica fechada:

- `none`: nenhum campo da fonte é enviado a modelo generativo;
- `facts`: somente pacote estruturado e minimizado de fatos autorizados que já
  passou por extração determinística fora do modelo;
- `full_text`: texto integral pode ser processado, reservado a conteúdo próprio
  ou licença que cubra expressamente esse uso.

`facts` autoriza o redator a receber o pacote factual; não autoriza um modelo a
abrir, pesquisar ou extrair a página de origem. Como o Scout usa
`hosted web_search`, ele toca conteúdo da página durante a busca e só pode
admitir uma fonte externa com `ai_processing=full_text` expressamente contratado.

`store=false` impede o Scout de criar estado persistente da Response, mas não é
uma promessa de retenção zero. No modo padrão, a OpenAI pode manter conteúdo em
logs de monitoramento de abuso por até 30 dias, ressalvadas obrigações legais e
de segurança. Nesta primeira fundação, o enum executável admite somente `none`
e `standard_30d`: o segundo exige `retencao_dias >= 30` e uma autorização que
aceite a política aplicável. MAM ou ZDR não podem ser autoatestados por texto no
CSV; só entram por nova versão do schema depois de o projeto ser verificado
contra o controle administrativo da OpenAI e sua retenção efetiva ser testada.
`none` é obrigatório quando `ai_processing=none` e é proibido quando conteúdo
for enviado à Luna. O compartilhamento voluntário para treinamento permanece
desligado.

`metodo=hosted_web_search_domain_tree` é a única linha que o Scout web pode
usar. Ela exige `url_scope=domain_tree` e uma `base_url` que seja apenas a
origem HTTPS, sem path, porta, query ou fragmento. O filtro da ferramenta cobre
o host registrado e seus subdomínios; portanto a autorização escrita precisa
cobrir toda essa árvore. API, RSS, host exato ou prefixo de caminho usam um
adaptador próprio e nunca são reinterpretados como busca hospedada.

Os escopos são literais: `internal` proíbe origem web; `exact_host` autoriza
somente o hostname exato, nunca seus subdomínios; `domain_tree` cobre o hostname
registrado e seus subdomínios. Em linhas que não entram no Scout, um path em
`base_url` pode identificar a página canônica do produto ou contrato, mas não
vira prefixo de autorização nem amplia o método. Somente a combinação exata de
`metodo`, `url_scope`, status, direitos e aprovação vigente libera uma rota.

O Scout web só pode selecionar uma linha quando:

```text
ativa == true
status == "green"
AND metodo == "hosted_web_search_domain_tree"
AND url_scope == "domain_tree"
AND ai_processing == "full_text"
AND openai_retention_mode é compatível com retencao_dias
AND retencao_fatos_dias > 0
AND host da URL pertence à árvore declarada por base_url
AND termos e autorização não estão vencidos
```

Para `T1` e `T2`, a revisão dos termos vence em 90 dias; para `T0`, em 365 dias
ou na data de expiração da autorização, o que ocorrer primeiro. Mudança anunciada
pela fonte vence a revisão imediatamente. A linha `T3` nunca pode ser `green`.
No início do dia UTC de vencimento, uma linha ativa que ainda estiver marcada
como `green` invalida o carregamento em vez de ganhar tolerância implícita.

Uma fonte interna `T0` pode estar `green` sem `base_url` porque seu conteúdo é
admitido por outro processo. Essa exceção não cria um domínio fictício: o Scout
web a ignora e aborta se não restar nenhuma fonte externa vigente com direito de
IA. Esse aborto é o bloqueio esperado, não uma razão para recorrer à web aberta.
Hoje não há fonte externa `green` com esse método; por isso o preflight real
termina em `blocked` e a API não é chamada.

## 5. Fluxo obrigatório

### 5.1 Descoberta

- Consulta de buscador e snippet servem somente para achar a URL canônica.
- Snippet, resumo de buscador ou resposta de IA não são evidência.
- Login, cookie de sessão, CAPTCHA, paywall e URL privada encerram a tentativa.

### 5.2 Portão de direitos

Antes de baixar conteúdo para análise, resolver `id`, `metodo`, `status`,
`ai_processing`, controle de retenção da OpenAI, retenções locais e domínio.
`yellow` vai para fila humana; `red` é descartado e registrado apenas como
motivo de recusa, sem payload.

### 5.3 Quarentena efêmera

O bruto autorizado existe somente pelo tempo necessário à extração e nunca além
de `retencao_dias`. Segredos, cookies, tokens, e-mail, nome civil, rosto ou outro
dado pessoal desnecessário são removidos antes de qualquer etapa de IA.

### 5.4 Normalização e proveniência

Cada fato deve carregar, no mínimo:

- `source_id`, URL canônica, instante de captura e versão dos termos;
- hash do registro, hash da autorização, responsável e validade vigentes;
- sensor, território, período observado e unidade original;
- `source_family` e `origin_type` (`original_report`, `press_release`,
  `syndication`, `commentary`, `retail_observation`);
- hash do payload ou do conjunto factual que permita auditoria sem reter a obra;
- transformação aplicada, versão da taxonomia e nível de confiança.

Valores ausentes permanecem ausentes. Tradução, embedding ou Luna não podem
inventar correspondência com a taxonomia.

### 5.5 Deduplicação e independência

URL canônica, título normalizado, data, entidades e `source_family` eliminam
republicação e release sindicado. Dez matérias copiando o mesmo release contam
como uma origem, não dez confirmações.

Uma observação de uma única família pode aparecer como **sinal isolado**. Só
recebe linguagem de confirmação quando duas famílias independentes e
compatíveis medirem o mesmo fenômeno no mesmo período. Métricas entre plataformas
nunca são somadas ou comparadas como se tivessem o mesmo denominador.

### 5.6 Pacote para Luna

O redator recebe somente fatos já admitidos, com IDs de evidência. Números,
datas, ranking e variação são calculados e validados deterministicamente. A Luna:

- pode organizar, resumir e apontar contradições do pacote;
- não navega, não escolhe fonte e não resolve direitos;
- não recebe imagem, vídeo ou texto bruto quando `ai_processing=facts`;
- não faz reconhecimento facial nem infere idade, etnia, religião, saúde,
  orientação sexual ou qualquer atributo sensível/protegido;
- não transforma correlação em causalidade nem sinal isolado em tendência;
- não treina nem ajusta modelo com material das fontes.

Toda frase publicada precisa ser remontável aos fatos recebidos. Saída sem
evidência, com número novo ou com fonte bloqueada falha fechada e usa o template
determinístico de fallback.

### 5.7 Revisão e publicação

O revisor humano verifica: direitos, atualidade, atribuição, independência,
unidade, território, período, incerteza, links e ausência de dado pessoal. As
primeiras 12 edições exigem revisão integral. Automatizar publicação requer nova
decisão versionada e amostra cega aprovada; não é parte deste contrato.

## 6. Direitos de exibição e imagens

`display_rights` limita o que pode sair do backend:

| Valor | Saída máxima |
|---|---|
| `own_content` | conteúdo criado e detido pela DataDrobe |
| `facts_and_canonical_link` | fatos próprios normalizados, atribuição e link |
| `link_only` | nome da fonte e link; nenhum corpo ou mídia |
| `official_metadata_with_attribution` | metadados oficiais sem alteração, conforme regras da API |
| `licensed_content` | somente itens e formatos cobertos pela licença anexada |
| `none` | nada é exibido |

Foto de passarela, arquibancada, creator, produto ou matéria permanece protegida
mesmo quando está publicamente visível. A v1.3 usa paleta, ícones, silhuetas e
gráficos próprios. Thumbnail, screenshot, reprodução de texto ou embed social
só entram depois de licença/termos específicos e revisão de privacidade do
tracking. O link abre no navegador do sistema.

## 7. Privacidade e LGPD

Handles, nomes e perfis públicos podem ser dados pessoais. A coleta deve provar
finalidade, necessidade e balanceamento, além de oferecer contato e oposição
quando aplicável. Para o radar:

- priorizar dados agregados e contas profissionais que participem por contrato;
- não criar dossiê de pessoa, perfil comportamental individual ou lista de
  menores;
- não guardar comentários, foto de perfil ou identificador quando um fato
  agregado resolve a pergunta;
- apagar dado pessoal diante de revogação válida e respeitar o prazo mais curto
  entre lei, contrato e registro;
- manter opt-out e canal de correção documentados antes de abrir painel de
  creators.

## 8. Falha, custo e observabilidade

Uma fonte fora do ar reduz cobertura e confiança; não derruba todo o pipeline.
Cada adaptador tem timeout, orçamento, rate limit, backoff e circuit breaker
próprios. `401`, `403`, `429`, mudança de contrato, seletor quebrado ou resposta
fora do schema interrompem aquela fonte sem proxy, rotação de identidade,
User-Agent enganoso ou fallback privado.

O relatório de execução separa:

- `healthy`: fonte respondeu dentro do contrato;
- `missing`: fonte esperada não respondeu; edição pode sair com ressalva;
- `quarantined`: conteúdo aguarda decisão humana;
- `blocked`: regra de direitos ou segurança recusou a fonte;
- `invalid`: payload não passou no schema.

Custos dos adaptadores são orçados por edição e por sensor. Estouro de um sensor
desliga só sua perna. O Scout hospedado inicial usa um teto global único
por edição (oito chamadas de busca e 4.500 tokens de saída), registra cobertura
por pauta e nunca se repete automaticamente após falha sem mudança no pacote.
Antes do POST, grava um recibo técnico; depois de iniciado, falha sem resposta é
marcada como custo desconhecido, jamais como “nenhuma chamada”. Candidatos e
recibo têm artefatos e prazos de retenção separados. A credencial e o projeto
OpenAI são exclusivos do laboratório e protegidos pelo environment
`market-intelligence-lab`.

## 9. Mudança de status e resposta a incidente

Promover uma linha para `green` exige, no mesmo diff:

1. evidência da licença, autorização, aprovação de app/auditoria ou termos;
2. escopo de campos, IA, exibição e retenção preenchido;
3. `url_scope`, método, domínio/subdomínios, redirecionamento, rate limit e deleção testados;
4. hash da evidência, aprovação nominal e validade preenchidos;
5. atualização de `termos_versao` e `termos_revisados_em`.

Se houver suspeita de violação: desligar a linha, mudar para `red`, parar jobs,
isolar ou apagar bruto conforme obrigação, preservar somente log técnico mínimo,
avaliar impacto e só reabrir por nova revisão. A existência de dados históricos
não autoriza continuar usando-os após revogação.

## 10. Referências normativas consultadas

- Pinterest Developer Guidelines:
  <https://policy.pinterest.com/en/developer-guidelines>
- Pinterest Trends API:
  <https://developers.pinterest.com/docs/analytics-and-reports/trends/>
- Guardian Open Platform — access tiers:
  <https://open-platform.theguardian.com/access/>
- YouTube API Services Developer Policies:
  <https://developers.google.com/youtube/terms/developer-policies>
- YouTube — políticas adicionais de métricas derivadas e retenção:
  <https://developers.google.com/youtube/terms/derived-metrics-policy>
- Instagram Platform Terms:
  <https://developers.facebook.com/terms/>
- TikTok for Developers — Terms of Service:
  <https://www.tiktok.com/legal/page/us/terms-of-service/en>
- Google Trends API alpha:
  <https://developers.google.com/search/apis/trends>
- Robots Exclusion Protocol, RFC 9309:
  <https://www.rfc-editor.org/rfc/rfc9309.html>
- Lei de Direitos Autorais, Lei 9.610/1998:
  <https://www.presidencia.gov.br/ccivil_03/leis/l9610.htm>
- ANPD — guia de legítimo interesse:
  <https://www.gov.br/anpd/pt-br/centrais-de-conteudo/materiais-educativos-e-publicacoes/copy_of_guia_legitimo_interesse.pdf>
- OpenAI — controles de dados e retenção:
  <https://developers.openai.com/api/docs/guides/your-data>

## 11. Critério de aceite da camada de governança

A camada está válida quando:

- o CSV abre por parser RFC 4180, tem IDs únicos e somente enums conhecidos;
- todos os tiers `T0`–`T3` e status `green`–`red` estão representados;
- toda linha `green` tem `ai_processing`, controle OpenAI, retenção e origem explícitos;
- o hash da autorização interna confere byte a byte com este documento e seu
  bloco nominal de aprovação está completo e vigente;
- toda linha `red` produz recusa por padrão;
- mudanças em termos vencem a liberação até nova revisão;
- nenhum SQL, coletor ou segredo precisa ser alterado para interpretar a política.
