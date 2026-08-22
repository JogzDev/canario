# DataDrobe 1.1 — corte, assinatura e distribuição

Estado conferido em 21/08/2026. Este é o guia ativo do próximo envio; a ficha
da 1.0 permanece apenas como registro histórico.

| Campo | Valor do candidato |
|---|---|
| Produto | **DataDrobe** |
| Bundle ID | `br.com.canario.ch3.app` |
| Versão | **1.1** |
| Build | **5** |
| Team | `67AYPRFZH8` |
| Plataforma | iPhone, iOS 17+ |
| Idioma-fonte | inglês |
| Análise visual | Luna v8 habilitada, sempre com consentimento explícito |

A versão 1.0 já está publicada. O upload da 1.1 deve ir para o mesmo registro;
`com.canario.app` é um identificador histórico sem relação com este envio.

**Corte executado em 21/08:** Archive Release validado, exportação App Store
concluída e upload 1.1 (2) aceito às 09:18. O pacote entrou em processamento no
TestFlight e não foi submetido à App Review. O Archive está preservado no
Organizer como `DataDrobe 1.1 (2) 09.15.xcarchive`.

**Candidato atual:** build 5. Ele preserva as correções do build 4 e corrige a
semana parcial que reduzia o Compare a Dress, a regra que apagava a curva de
tamanhos de Stripes, o excesso de altura na ajuda e a repetição visual dos
sinais. O build 4 foi aceito pelo App Store Connect às 19:49; o build 5 ainda
será arquivado e enviado ao TestFlight. Nenhum build foi submetido à App Review.

## Portões antes do Archive

Todos precisam estar verdes no mesmo commit:

1. Workflow **Testes / Coletores (Python)** — todas as 28 suítes Python.
2. `cd app && swift test` — lógica e contratos de rede.
3. `xcodebuild test -project Canario.xcodeproj -scheme Canario -destination
   'platform=iOS Simulator,name=iPhone 17' -only-testing:CanarioUITests
   CODE_SIGNING_ALLOWED=NO` — fluxos de interface.
4. `python3 ferramentas/testar_edge_luna.py --so-contrato` — Edge Function
   disponível sem gastar uma análise.
5. Luna v8 conferida contra o gabarito humano: categoria 19/24 (79,2%) e cor
   principal 20/24 (83,3%). Em uma amostra de 24, cada acerto vale 4,17 pontos
   percentuais e 80% exatos não são atingíveis; 19/24 é o inteiro mais próximo
   da meta. O aceite é aplicação proporcional do portão, não exceção de um
   build nem redução da busca por excelência. Registro ativo:
   `anexos/portao_luna_24.json`.
6. `app/Config.xcconfig` preenchido e `REMOTE_ANALYSIS_ENABLED = YES`. O arquivo
   é ignorado pelo Git; nunca copiar suas chaves para documentação ou log.
7. Pipeline e saúde do dado verdes, sem publicação parcial silenciosa.

## Archive e validação

No Xcode, use **Any iOS Device (arm64)** e **Product > Archive**. Em seguida,
no Organizer:

1. abra o Archive 1.1 (5);
2. escolha **Validate App**;
3. confirme DataDrobe, `br.com.canario.ch3.app` e Team `67AYPRFZH8`;
4. leia todos os warnings e corrija qualquer divergência de entitlement,
   assinatura, versão ou privacidade;
5. escolha **Distribute App > TestFlight & App Store > Upload**.

Não marque **TestFlight Internal Only**, porque isso impediria usar o mesmo
build numa futura revisão. Upload ao TestFlight não autoriza nem realiza envio
à App Review.

## Teste físico obrigatório antes de App Review

Em uma instalação limpa e também atualizando a 1.0:

- câmera, fototeca e arquivo/PDF;
- seleção e ajuste do alvo, zoom/crop e volta à imagem original;
- disclosure da nuvem antes do envio e caminho manual quando recusado/offline;
- sugestões da Luna, correção humana e salvamento no Closet;
- miniatura, favorito, edição e exclusão local;
- Similar Pieces e links externos em pelo menos duas marcas;
- aparência clara inclusive com o iPhone em modo escuro, Dynamic Type e VoiceOver;
- espera de importação medida num iPhone físico, sem tela travada;
- navegação completa em iOS 17/18 e numa versão atual.

O aceite em aparelho é um portão humano: simulador não reproduz câmera real,
permissões, desempenho térmico nem o renderizador do iOS 18.

## Privacidade que precisa acompanhar este binário

A 1.1 pode enviar somente a cópia reduzida e sem metadados confirmada pela
pessoa, via Supabase para OpenAI, depois de um consentimento separado. O app
não guarda a imagem enviada; a OpenAI pode manter logs de monitoramento de
abuso por até 30 dias. Não há conta, tracking, publicidade nem ligação da foto
a uma identidade. O App Privacy deve declarar **Photos or Videos**, não ligado
à pessoa, não usado para tracking, finalidade **App Functionality**.

Essas frases precisam estar de acordo em quatro lugares: tela Privacy,
disclosure antes do envio, `PrivacyInfo.xcprivacy` e ficha da App Store 1.1.

## Se a assinatura falhar

- `No profiles for ...`: confirme que a equipe `67AYPRFZH8` possui o App ID
  explícito e acesso a Certificates, Identifiers & Profiles.
- certificado sem chave privada: baixe/recrie um Apple Distribution na conta
  correta; não troque o Bundle ID para contornar o erro.
- versão/build já usados: incremente apenas o build no projeto e no gerador,
  depois rode novamente o teste de identidade.
- falha de autenticação no upload: renove a sessão da conta no Xcode; preserve
  o Archive validado para repetir o upload sem recompilar.

Metadados para copiar estão em `FICHA_APP_STORE_1.1.md`; instruções operacionais
curtas do beta estão em `TESTFLIGHT.md`.
