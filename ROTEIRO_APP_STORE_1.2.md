# Roteiro de envio — DataDrobe 1.2

Estado verificado em 20/09/2026. O candidato é `1.2 (2)`, bundle
`br.com.canario.ch3.app`, iPhone com iOS 17 ou posterior. O build 1 foi aceito
pela Apple em 31/08, mas antecede o consumidor A57/A58 e não deve ser
reutilizado.

**Assinatura resolvida:** a exportação diagnóstica de 20/09 confirmou a conta,
a identidade Apple Distribution e o perfil App Store com Sign in with Apple e
Associated Domains. Ela não foi enviada. O Archive do build 2 só será gerado
depois dos sete marcos de observação.

**Janela operacional:** 19 e 20/09 fecharam verdes (2/7). Os ciclos agendados
de 21 a 25/09 ainda precisam comprovar pipeline verde, data pública do próprio
dia e cota em até 85%. Não antecipar o Archive ou fabricar um marco com coleta
manual.

## Quem faz o quê

| Etapa | Codex pode fazer | JP precisa fazer |
|---|---|---|
| Código, testes, versão e textos | preparar, corrigir, testar e manter o roteiro | aprovar decisões de produto e conteúdo |
| Conta/certificado Apple | conferir o estado e continuar assim que a sessão existir | entrar no Xcode/App Store Connect, concluir 2FA e aceitar contratos da organização |
| Exportar e validar | executar o Archive/export e tratar erros técnicos | autorizar prompts da conta ou do Keychain, se aparecerem |
| Upload | enviar o binário e acompanhar o processamento | manter a sessão Apple disponível |
| TestFlight interno | configurar o build e organizar o roteiro | instalar no iPhone e testar câmera, fototeca, login Apple e exclusão no aparelho real |
| Capturas e metadados | gerar capturas limpas, revisar dimensões e preencher os campos | aprovar o material e confirmar declarações legais/privacidade |
| Revisão | deixar tudo pronto até `Add for Review` | autorizar explicitamente o envio; `Submit for Review` é o ato final externo |

Em outras palavras: depois que a conta Apple estiver ativa neste Mac, Codex
consegue conduzir exportação, validação, upload, organização do TestFlight,
capturas e preenchimento. JP continua indispensável para credenciais/2FA, o
teste físico e a decisão final de submeter a versão à Apple.

## 1. Antes do Archive

- [ ] Completar a política em `https://datadrobe.carrd.co/#privacy`: o texto
  público já descreve a 1.2, mas em 20/09 ainda omitia que novas sessões Apple
  retêm o refresh token somente para revogá-lo na exclusão e o apagam junto da
  conta. Publicar o parágrafo de `POLITICA_PUBLICA_1.2.md` e conferir a URL fora
  de uma sessão autenticada.
- [ ] Confirmar Support URL, e-mail de suporte e copyright da ficha 1.2.
- [ ] Confirmar no Supabase de produção Apple, Google e e-mail ativos; criar uma
  conta de demonstração exclusiva para a equipe de revisão. Não registrar a
  senha no Git; as credenciais entram somente no App Store Connect.
- [ ] Conferir em produção a migração
  `20260831152000_a50_tokens_de_revogacao_apple.sql`, as funções
  `registrar-credencial-apple` e `excluir-conta` e os secrets
  `APPLE_TEAM_ID` (`67AYPRFZH8`), `APPLE_SIGN_IN_KEY_ID` e
  `APPLE_SIGN_IN_PRIVATE_KEY`. O valor da chave `.p8` nunca entra no
  repositório ou em logs. `APPLE_CLIENT_ID` pode ficar ausente, pois o app usa
  `br.com.canario.ch3.app` como padrão.
- [ ] Depois disso, criar uma conta Apple nova de teste, excluí-la e confirmar
  a resposta `apple_revocation: revoked` no log da Edge Function. Uma conta
  Apple antiga, criada antes dessa mudança, pode não ter refresh token e deve
  cair no atalho manual do Apple Account — isso é esperado e continua apagando
  todos os dados do DataDrobe.
- [ ] Confirmar que termos/acordos, contratos e dados da organização não têm
  pendências no App Store Connect.
- [ ] Fechar os sete marcos operacionais e rodar todos os portões de
  `RELEASE_DATADROBE.md` no mesmo commit.
- [ ] Fazer o teste físico descrito em `TESTFLIGHT.md`, inclusive instalação
  limpa, atualização, câmera, fototeca, PDF, offline, login e exclusão da conta.
- [ ] Capturar telas novas da 1.2 em 6,9 polegadas sem dados pessoais, pop-ups,
  cursor do simulador ou conteúdo de debug; não reutilizar as capturas de
  agosto. Embora `1320 × 2868` e `1284 × 2778` sejam resoluções aceitas, o lote
  antigo mostra dados de 30/08, Closet vazio e uma aparência escura que não
  representa o candidato light-only.

### Matriz das capturas finais (ordem proposta)

1. **Explore / Market panel** — painel com data observada atual e fonte clara.
2. **Similar Pieces** — peça real, preço, marca e link; a idade do painel deve
   aparecer quando o dado não for de hoje.
3. **Analyze an item** — as três entradas e o disclosure de privacidade.
4. **Fill the info** — categoria, prioridade das cores e intended price.
5. **Closet preenchido** — itens reais de demonstração, busca e favorito; não
   usar o estado vazio como uma das cinco primeiras imagens.
6. **Account / sync** — conta explicitamente opcional e sincronização privada.

Cada imagem deve vir do build 2 final e usar o mesmo tamanho dentro do conjunto.
O lote JPEG não tem canal alfa e é o formato seguro para upload; os PNGs RGBA
atuais permanecem apenas como fonte histórica.

## 2. Archive e upload

1. Abra `app/Canario.xcodeproj` no Xcode 26 ou posterior.
2. Selecione `Any iOS Device (arm64)` e `Product > Archive`.
3. No Organizer, confirme `DataDrobe 1.2 (2)`, bundle e Team.
4. Rode `Validate App`; trate erros e leia todos os avisos.
5. Use `Distribute App > TestFlight & App Store > Upload` sem marcar
   `TestFlight Internal Only`.
6. Aguarde o status `Complete`. Se o upload completo precisar ser substituído,
   incremente o build, regenere o projeto e valide um novo Archive.

## 3. TestFlight antes da revisão

- [ ] Distribuir primeiro apenas ao grupo interno.
- [ ] Executar o roteiro de `TESTFLIGHT.md` em ao menos dois iPhones.
- [ ] Conferir crashes, hangs, consumo de memória, login, links externos e
  exclusão definitiva da conta.
- [ ] Registrar modelo, versão do iOS, resultado e qualquer ressalva.

## 4. Página da versão 1.2

- [ ] Copiar Subtitle, Promotional Text, What's New, Description, Keywords e URLs de
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
