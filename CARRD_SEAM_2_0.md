# Seam 2.0 — texto para suporte e privacidade

Rascunho para substituir a página pública antes do envio da 2.0. O endereço
final da página e a data de vigência entram na publicação. A página atual da
1.2 (`datadrobe.carrd.co`) continua histórica até a troca. Publicação: JP.

## Português — suporte

**Seam: moda, medida.** O Seam reúne sinais observados do mercado de moda
feminina e mostra as peças que sustentam cada Leitura. Ele descreve o que foi
coletado; não prevê vendas.

Você pode usar o app sem conta. No Estúdio, traga uma peça por foto ou arquivo;
na Busca, descreva a peça com suas palavras. O Acervo guarda suas peças e as
Leituras que você decide salvar neste iPhone. Uma conta opcional sincroniza os
dados estruturados do Acervo e miniaturas reduzidas entre seus aparelhos.

**Ajuda e correções:** canarioch3@gmail.com. Ao relatar uma Leitura, inclua a
data que aparece na tela, o atributo e o link da fonte. Não envie senhas nem
fotos pessoais por e-mail.

**Excluir conta:** no app, Conta → Perfil → Excluir conta. Você também pode
apagar somente o Acervo local em Conta → Ajustes. A exclusão da conta remove
os registros e as miniaturas sincronizados, além dos dados dessa conta no
iPhone.

## Português — privacidade

**Política de privacidade do Seam 2.0**

Data de vigência: **[preencher na publicação]**. O Seam é publicado pela
Fundação Padre Leonel Franca. Não há anúncios, venda de dados pessoais nem
rastreamento entre apps ou sites. Você pode usar o app sem criar conta.

**Leituras solicitadas.** Ao pedir uma Leitura, as palavras digitadas, eventual
resposta de refinamento, atributos confirmados da foto e preço opcional são
enviados ao serviço no Supabase. O serviço usa a OpenAI para interpretar o
pedido e redigir frases fundamentadas nos dados do painel. A foto original não
é enviada nessa etapa. Um resumo criptográfico do pedido e sua interpretação
podem ser guardados por sete dias para manter Leituras repetidas consistentes;
o texto original do pedido não é guardado nesse cache. As Leituras que você
salva ficam no iPhone e não são sincronizadas com a conta.

**Fotos escolhidas.** Câmera e Fototeca só são acessadas após sua ação. Cor,
texto visível e separação da peça são processados no iPhone. Depois de você
confirmar a peça alvo, o app pede autorização separada antes de enviar uma
cópia reduzida, sem metadados, pelo Supabase à OpenAI para sugerir atributos.
A foto original não é enviada e o Seam não guarda a cópia submetida. A OpenAI
pode reter registros de monitoramento de abuso por até 30 dias. Você pode
revisar cada sugestão ou usar o preenchimento manual.

**Acervo e conta opcional.** Sem conta, os itens, miniaturas reduzidas e
Leituras salvas ficam neste iPhone. Com conta Apple, Google ou e-mail, o
Supabase processa seu identificador de conta, e-mail quando fornecido e
credenciais de sessão. O Seam não recebe sua senha Apple/Google nem guarda a
senha do e-mail. A sessão local fica no Chaves do iOS.

Ao entrar, o Seam sincroniza nome, atributos confirmados, preço alvo, canal,
data, favoritos, escolhas explícitas sobre similares e uma miniatura reduzida
sem metadados por peça, com até 720 pixels no lado maior. Esses dados ficam
vinculados à conta, em área privada com controle de acesso por usuário. A foto
original permanece no iPhone. Apagar uma peça remove sua miniatura
sincronizada; apagar a conta remove os registros e miniaturas da conta.

**Limites e fontes externas.** Para limitar abuso da análise opcional, o
servidor guarda por até sete dias um hash irreversível e salgado derivado da
origem da requisição, e não o endereço IP em si. Imagens de produtos similares
carregam do servidor da loja ou de sua rede de distribuição; esses serviços
recebem os dados normais de uma requisição de imagem. Links de compra abrem o
site da loja, sujeito à política dela. O Seam consulta medições publicadas do
mercado, sem criar previsão de vendas.

**Suas escolhas.** Você pode sair da conta, apagar uma peça, apagar o Acervo
local ou excluir a conta dentro do app. A exclusão da conta remove os dados
sincronizados e a sessão no iPhone. Para sessões novas com Iniciar Sessão com a
Apple, o serviço usa o token de atualização somente para revogar o acesso no
momento da exclusão. Para uma sessão Apple antiga sem token disponível, o app
mostra como remover a autorização restante na Conta Apple. Você pode revogar
o acesso à câmera e à fototeca nos Ajustes do iOS.

**Contato:** canarioch3@gmail.com. Esta página será atualizada antes de uma
versão publicada mudar os dados que saem do aparelho.

## English — support

**Seam: Fashion, Measured.** Seam brings together observed signals from the
women's fashion market and shows the items behind each Reading. It describes
collected evidence; it does not predict sales.

You can use the app without an account. Bring a garment into Studio by photo
or file, or describe it in Search. Archive keeps the garments and Readings you
choose to save on this iPhone. An optional account syncs structured Archive
details and reduced thumbnails across your devices.

**Help and corrections:** canarioch3@gmail.com. For a Reading, include the
date shown in the app, the attribute and the source link. Do not email
passwords or personal photos.

**Delete an account:** in the app, Account → Profile → Delete account. You can
erase only the local Archive in Account → Settings. Account deletion removes
synced records and thumbnails and that account's data on the iPhone.

## English — privacy

**Seam 2.0 Privacy Policy**

Effective **[set on publication]**. Seam is published by Fundação Padre Leonel
Franca. It has no advertising, sale of personal data or tracking across apps
or websites. You can use the app without an account.

**Readings you request.** When you request a Reading, the words you entered,
any follow-up answer, confirmed photo attributes and optional price go to our
Supabase service. The service uses OpenAI to interpret the request and write
sentences supported by panel data. Your original photo is not sent in this
step. A hash of the request and its interpretation may be kept for seven days
to make repeated Readings consistent; the original request text is not kept
in that cache. Readings you save remain on this iPhone and do not sync to your
account.

**Photos you choose.** Camera and Photo Library access follow your action.
Colour, visible text and garment separation are processed on the iPhone. After
you confirm the target garment, the app asks separately before sending a
reduced, metadata-free copy through Supabase to OpenAI for attribute
suggestions. The original is not uploaded, and Seam does not store the
submitted copy. OpenAI may retain abuse-monitoring logs for up to 30 days.
You can edit every suggestion or enter attributes manually.

**Archive and optional account.** Without an account, saved items, reduced
thumbnails and saved Readings remain on this iPhone. If you sign in with Apple,
Google or email, Supabase processes your account identifier, email when
provided and session credentials. Seam does not receive your Apple or Google
password or store your email password. The local session stays in the iOS
Keychain.

When signed in, Seam syncs each item's name, confirmed attributes, target
price, channel, date, favorite state, explicit similar-item choices and one
metadata-free thumbnail up to 720 pixels on its longest side. These are
linked to your account and stored privately with access restricted to that
account. Original photos remain on the iPhone. Deleting an item removes its
synced thumbnail; account deletion removes all its synced records and
thumbnails.

**Limits and external sources.** To prevent abuse of optional analysis, the
server keeps a salted, irreversible hash derived from request origin for up
to seven days, rather than the IP address itself. Similar-product images load
from the retailer or its CDN, which receives the network information normally
sent for an image request. Store links open the retailer's site under its own
privacy policy. Seam reads published market measurements and does not forecast
sales.

**Your choices.** You can sign out, delete an item, erase the local Archive or
permanently delete your account inside the app. Account deletion removes its
synced data and the iPhone session. For new Sign in with Apple sessions, the
service uses an Apple refresh token only to revoke access during deletion.
For older Apple sessions without a revocable token, the app explains how to
remove the remaining authorization in Apple Account. You can revoke camera
and photo access in iOS Settings.

**Contact:** canarioch3@gmail.com. This page will be updated before a
released version changes what leaves the device.
