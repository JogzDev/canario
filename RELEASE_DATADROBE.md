# DataDrobe — assinatura, Archive, TestFlight e App Store

Estado verificado em 14/08/2026:

- nome exibido: `DataDrobe`;
- versão do bundle: `1.0` (`build 1`);
- destino: somente iPhone (`TARGETED_DEVICE_FAMILY = 1`), iOS 17+;
- criptografia: somente HTTPS isento (`ITSAppUsesNonExemptEncryption = NO`);
- estilo de assinatura: Automatic;
- Bundle ID atual: `com.canario.app`;
- o Archive Release foi criado, mas a exportação para a loja depende da equipe
  Apple Developer dona do App ID e do registro no App Store Connect.

Um Archive Release local foi gerado com sucesso em `/tmp/DataDrobe.xcarchive`.
Ele usou o profile de desenvolvimento da equipe `8B25GA8AC6`; isso prova que o
Bundle ID e a assinatura local existem, mas a exportação `app-store-connect`
continua sendo o teste que confirma certificado/profile de distribuição.

Resultado desse teste: a exportação falhou com `No profiles for
'com.canario.app' were found`. Ao permitir atualização automática, a Apple
respondeu que a equipe “João Pedro Souza Carvalho de Oliveira” **não tem
permissão para criar profiles iOS App Store**. Portanto não é erro de Swift nem
do Archive: o Account Holder/Admin da equipe precisa criar o profile de
distribuição ou conceder ao usuário atual acesso a Certificates, Identifiers &
Profiles. Depois disso, repetir a exportação/Organizer.

## Por que passar pelo TestFlight

Não é outro binário nem retrabalho. O mesmo Archive enviado ao App Store
Connect aparece primeiro como build processado e pode ser distribuído no
TestFlight; depois esse mesmo build é selecionado na versão 1.0 e enviado à
revisão. Para este app, o teste interno é o portão final para câmera, recorte,
permissão explícita de nuvem, links externos, dark mode e desempenho em device.

Não escolher **TestFlight Internal Only**: esse tipo de build não pode ser
submetido aos clientes. No Organizer, escolher **TestFlight & App Store**.

## Passo a passo exato no Xcode

1. Abra `app/Canario.xcodeproj`.
2. Clique no projeto azul **Canario** > target **Canario** > **Signing &
   Capabilities**.
3. Selecione **All** ou, separadamente, **Release**.
4. Ative **Automatically manage signing**.
5. Em **Team**, escolha a equipe do Apple Developer Program que possui o app.
   O valor precisa ser o mesmo para Debug e Release; não deixe Release usando
   uma equipe pessoal diferente.
6. Confirme que `com.canario.app` é exatamente o Bundle ID cadastrado. Se o App
   ID do DataDrobe no portal for outro, mude primeiro no portal/App Store
   Connect e depois no Xcode — não invente um terceiro identificador.
7. Em App Store Connect > **Apps**, crie ou abra o registro **DataDrobe**, versão
   1.0, associado a esse Bundle ID.
8. No seletor de destino do Xcode, escolha **Any iOS Device (arm64)**, nunca um
   simulador.
9. Use **Product > Archive**. O Organizer abrirá ao terminar.
10. No Organizer, selecione o Archive > **Validate App**. Resolva todos os erros
    antes de continuar; warning também deve ser lido, não descartado por padrão.
11. Clique **Distribute App** > **TestFlight & App Store** > **Upload**.
    Mantenha upload de símbolos e assinatura automática.
12. Aguarde o processamento do build no App Store Connect. O primeiro upload
    cria também a versão beta.
13. Em **TestFlight**, crie o grupo interno do time, adicione o build e preencha
    “What to Test” com: captura/fototeca, seleção do alvo, crop/zoom, isolamento
    do fundo, sugestões do Luna, correção manual dos atributos, salvar no Closet,
    Similar Pieces e links das lojas.
14. Teste no mínimo em dois iPhones físicos e faça uma instalação limpa. Só
    então, na página da versão 1.0, selecione esse mesmo build e envie para App
    Review após completar URLs, App Privacy, screenshots, age rating e notes.

## Se o Archive falhar na assinatura

- `No profiles for ... were found`: a equipe não possui um App ID explícito
  para o Bundle ID atual, ou o Xcode não tem permissão para criar o profile.
  Confirme Team/Bundle ID e faça login em **Xcode > Settings > Accounts**.
- `requires a provisioning profile`: mantenha assinatura automática e clique
  **Download Manual Profiles** na conta; depois tente novamente.
- certificado sem chave privada: no Mac que criou o certificado, exporte o
  certificado **Apple Distribution** com a chave privada pelo Keychain, ou
  deixe o Xcode criar um novo certificado pela conta autorizada.
- `bundle identifier is not available`: o Bundle ID pertence a outra equipe.
  Selecione a equipe correta; não acrescente sufixo só para fazer o build passar,
  porque ele deixará de corresponder ao registro do App Store Connect.

Referências oficiais: Apple, “Preparing your app for distribution”,
“Distributing your app for beta testing and releases”, “Upload builds” e
“Add internal testers”.
