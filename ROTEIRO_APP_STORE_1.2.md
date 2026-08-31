# Roteiro de envio — DataDrobe 1.2

Estado verificado em 31/08/2026. O binário é `1.2 (1)`, bundle
`br.com.canario.ch3.app`, iPhone com iOS 17 ou posterior. Para iOS, a Apple
aceita reiniciar o build em 1 ao mudar a versão; só aumente para 2 se `1.2 (1)`
já tiver sido processado no App Store Connect ou se for necessário recompilar
depois do primeiro upload.

## 1. Antes do Archive

- [ ] Publicar `POLITICA_PUBLICA_1.2.md` em
  `https://datadrobe.carrd.co/#privacy` e abrir a URL em janela privada.
- [ ] Confirmar Support URL, e-mail de suporte e copyright da ficha 1.2.
- [ ] Confirmar no Supabase de produção Apple, Google e e-mail ativos; criar uma
  conta de demonstração exclusiva para a equipe de revisão.
- [ ] Confirmar que termos/acordos, contratos e dados da organização não têm
  pendências no App Store Connect.
- [ ] Rodar todos os portões de `RELEASE_DATADROBE.md` no mesmo commit.
- [ ] Fazer o teste físico descrito em `TESTFLIGHT.md`, inclusive instalação
  limpa, atualização, câmera, fototeca, PDF, offline, login e exclusão da conta.
- [ ] Capturar telas novas da 1.2 em 6,9 polegadas sem dados pessoais, pop-ups,
  cursor do simulador ou conteúdo de debug; não reutilizar capturas que mostrem
  a interface anterior.

## 2. Archive e upload

1. Abra `app/Canario.xcodeproj` no Xcode 26 ou posterior.
2. Selecione `Any iOS Device (arm64)` e `Product > Archive`.
3. No Organizer, confirme `DataDrobe 1.2 (1)`, bundle e Team.
4. Rode `Validate App`; trate erros e leia todos os avisos.
5. Use `Distribute App > TestFlight & App Store > Upload` sem marcar
   `TestFlight Internal Only`.
6. Aguarde o status `Complete`. Se o upload completo precisar ser substituído,
   altere build para 2, gere e valide um novo Archive.

## 3. TestFlight antes da revisão

- [ ] Distribuir primeiro apenas ao grupo interno.
- [ ] Executar o roteiro de `TESTFLIGHT.md` em ao menos dois iPhones.
- [ ] Conferir crashes, hangs, consumo de memória, login, links externos e
  exclusão definitiva da conta.
- [ ] Registrar modelo, versão do iOS, resultado e qualquer ressalva.

## 4. Página da versão 1.2

- [ ] Copiar What's New, descrição ajustada, keywords e URLs de
  `FICHA_APP_STORE_1.2.md` para todos os locales ativos.
- [ ] Subir as capturas 1.2 e conferir a ordem no preview de cada tamanho.
- [ ] Conferir categoria, classificação etária e direitos sobre o conteúdo.
- [ ] Em App Privacy, declarar exatamente os seis tipos registrados na ficha;
  fotos/vídeos são vinculados ao usuário na 1.2 e tracking é `No`.
- [ ] Responder export compliance de acordo com
  `ITSAppUsesNonExemptEncryption = false`.
- [ ] Preencher Review Notes, contato e credenciais da conta de demonstração.
- [ ] Selecionar o build processado e salvar.

## 5. Envio deliberado

1. Revise uma última vez política pública, capturas, App Privacy e Review Notes.
2. Escolha a forma de liberação; para reduzir risco, prefira liberação manual ou
   gradual depois da aprovação.
3. Clique `Add for Review`, confira o pacote de submissão e só então
   `Submit for Review`.
4. Monitore mensagens da equipe de revisão e responda sempre no Resolution
   Center, preservando o número do build e as evidências dos testes.

O upload para TestFlight não envia a versão à revisão. `Submit for Review` é o
último ato externo e deve ser feito conscientemente por quem responde pela conta.
