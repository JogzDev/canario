# Abrir o projeto num Mac novo

Escrito em 18/08/2026, depois de perder quinze minutos de duas pessoas fazendo
exatamente isto. Se algo aqui estiver errado, corrija o arquivo — ele existe
para a terceira pessoa não repetir a mesma sequência.

## Diagnóstico primeiro

Antes de mexer em qualquer coisa, rode isto na raiz do repositório. Ele diz em
cinco segundos qual dos quatro problemas você tem:

```bash
echo "Xcode: $(xcodebuild -version | head -1)"
echo "Config: $([ -f Config.xcconfig ] && echo existe || echo AUSENTE)"
echo "Branch: $(git branch --show-current) ($(git rev-list --count HEAD..origin/main 2>/dev/null) commits atras do main)"
```

## 1. Xcode 26 ou mais novo

Não é preferência. O app usa APIs do iOS 26 — `GlassEffectContainer`,
`.buttonStyle(.glass)` e `Tab(role: .search)`. Elas estão protegidas por
`#available(iOS 26.0, *)` em tempo de execução, **mas compilar exige o SDK do
iOS 26**.

Em Xcode 16 ou 17 o erro é enganoso: *"cannot find GlassEffectContainer in
scope"*, que parece código faltando e é versão de ferramenta.

## 2. Clonar (o repositório é privado)

```bash
git clone https://github.com/JogzDev/canario.git ~/Canario && cd ~/Canario
```

**A senha da conta não funciona.** O GitHub removeu autenticação por senha no
Git em 2021, e a mensagem de erro não diz isso — diz apenas "authentication
failed", o que leva a pessoa a trocar a senha achando que errou.

No prompt, use:

- **Username:** seu usuário do GitHub
- **Password:** um **token**, não a senha

O token sai de https://github.com/settings/tokens/new — escopo `repo`, nada
mais. Ele aparece uma única vez; copie na hora.

Ao colar no campo de senha, **o terminal não mostra nada**. Sem asterisco, sem
bolinha. Parece travado. Cole e dê Enter.

Se você já errou algumas vezes, o macOS pode ter guardado a credencial ruim e
nem perguntar de novo. Limpe antes:

```bash
printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase
```

Quem entra precisa ser colaborador do repositório. Confira em
**Settings → Collaborators**, no GitHub.

## 3. `Config.xcconfig` — a causa mais comum

Este arquivo está no `.gitignore`, então **nenhum clone o traz**. E o projeto o
referencia como base de configuração: sem ele o Xcode falha **antes de
compilar**, com erro que não explica a causa.

```bash
cp Config.xcconfig.example Config.xcconfig
```

Depois preencha `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` com os valores
reais, que o JP fornece. Mais rápido ainda: peça o arquivo pronto por AirDrop.

Deixe `REMOTE_ANALYSIS_ENABLED = NO`, que é o padrão.

**E saiba o que isso faz com a tela de adicionar peça.** Com o interruptor em
`NO`, o app não chama a Luna: ele lê apenas o **texto impresso na imagem**, no
próprio aparelho. Foto de roupa quase nunca tem texto, então o fluxo chega em
"Confirm your item" com o cartão **"No attributes were read"** e nenhum
atributo marcado. **Isso é o comportamento correto do build desligado, não
defeito da tela nem da análise.** Foi exatamente o que aconteceu no primeiro
teste da `BranchFadul`, em 26/08/2026, e custou uma investigação inteira.

Para testar a análise de verdade, peça ao JP o `Config.xcconfig` com
`REMOTE_ANALYSIS_ENABLED = YES` — cada análise consome crédito da API, então
combine antes. Ligar sozinho sem a chave certa não adianta: a chamada falha e a
tela cai na mesma leitura local.

A chave desse arquivo é a **publishable**, pública por desenho — ela já vai
embutida no `.ipa` e qualquer um a extrai. Passá-la a um colega não é
vazamento. A chave `sb_secret_...` nunca entra aqui: vive só nos GitHub Secrets.

## 3b. Já tenho o projeto e quero pegar o que mudou

Esta seção é para quem já rodou o app antes e só precisa continuar de onde o
outro parou. **Quase tudo dá para fazer pelo Xcode, sem Terminal.**

### Pelo Xcode, que é o caminho curto

1. Abra `app/Canario.xcodeproj`.
2. Menu **Source Control → Pull…** → confirme.
3. Se o trabalho novo estiver em outra branch, abra o **Source Control
   navigator** (⌘2), a pasta **Remotes → origin**, clique com o botão direito na
   branch e escolha **Checkout**.
4. Escolha um **iPhone simulado** no seletor de destino e dê ▶.

Se o Pull reclamar que há alterações locais, **pare e mande print** em vez de
escolher qualquer opção: alterações locais podem ser trabalho seu que ninguém
quer perder.

### Três coisas que o pull NÃO traz

**1. O `Config.xcconfig`.** Ele está no `.gitignore` e nenhum clone o traz.
Se você já tem o seu de antes, ele continua valendo — não precisa fazer nada.
Se não tem, volte à seção 3.

**2. Um build do Xcode altera `Localizable.xcstrings`, e isso é normal.**
O Xcode varre o código e acrescenta ao catálogo cada texto novo que apareceu na
interface — e remove os que sumiram dela. Então, depois do primeiro build,
`git status` vai mostrar esse arquivo modificado **sem você ter editado nada**.
Isso não é erro: é o Xcode fazendo o trabalho dele. Esse arquivo **deve** entrar
no commit junto com o resto.

**3. Branch antiga não precisa ser reaproveitada.** Trabalho que já virou PR e
foi mesclado **já está** no que você acabou de puxar. Não tente reaplicar
`stash`, nem mesclar branch velha na nova: você estaria trazendo de volta uma
cópia antiga do mesmo código.

### Onde colocar o seu trabalho

Antes de começar a mexer, crie uma branch sua a partir do que você acabou de
puxar. Assim duas pessoas nunca escrevem na mesma branch ao mesmo tempo.

No Xcode: **Source Control → New Branch…**, dê um nome como `davi/nome-da-tela`
e confirme.

Quando terminar: **Source Control → Commit…**, marque os arquivos, escreva uma
frase do que mudou, marque **Push to remote** e confirme. Depois avise o JP com
o nome da branch.

**Nunca** faça push direto para `main`. Ela está protegida desde 26/08 e exige
PR com revisão — se você tentar, o GitHub recusa, o que é o comportamento certo.

## 4. Abrir e rodar

```bash
open app/Canario.xcodeproj
```

No seletor de destino, escolha um **iPhone simulado** — não "Any iOS Device".
No simulador a assinatura não entra em jogo.

Para rodar num aparelho de verdade você precisa estar no time `67AYPRFZH8`
(peça ao JP em Certificates, Identifiers & Profiles → People) ou trocar o
**Team** para o seu, apenas na sua máquina — **sem commitar essa mudança**.

## O que nunca commitar

- `Config.xcconfig` — está no `.gitignore` e deve continuar
- troca de `DEVELOPMENT_TEAM` feita para rodar no seu aparelho
- qualquer token ou chave
