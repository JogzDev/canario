# Subir para o TestFlight

> **Correção de 18/08/2026 — leia antes de seguir este guia.**
> O bundle que está em revisão na App Store é **`br.com.canario.ch3.app`**, não
> `com.canario.app`. Existem dois registros na App Store Connect; o `ch3` é o que
> tem perfil de distribuição emitido e o que recebeu o envio. Menções a
> `com.canario.app` abaixo são históricas — **não "corrija" o projeto para elas**,
> ou o upload vai para o app errado.

O que já está pronto no código e o que só você pode fazer. Escrito em 01/08/2026
para o prazo de segunda, 03/08.

---

## Já resolvido (verificado, não presumido)

| O que | Estado |
|---|---|
| Ícone do app | ✅ Gerado e empacotado. Verificado: `AppIcon60x60@2x.png` e `Assets.car` saem dentro do `.app` |
| Manifesto de privacidade | ✅ `PrivacyInfo.xcprivacy`, com as três respostas verdadeiras: sem coleta, sem rastreio, sem API de motivo obrigatório |
| Conformidade de exportação | ✅ `ITSAppUsesNonExemptEncryption = false` no Info.plist. Só fazemos HTTPS, que é isento — evita a pergunta a cada envio |
| Compila para aparelho real | ✅ `-sdk iphoneos -configuration Release` passa. Não é só simulador |
| Versão | ✅ `0.1` (build `1`) |
| Orientação, idioma, tela de abertura | ✅ Retrato, pt-BR |

**O ícone é provisório.** Fiz na paleta neutra que você fixou — preto, cinza e
branco, sem figura — para não ocupar decisão de marca que é da Bianca. É um arco
com três marcas crescentes: a curva e a escada de grade. Trocar depois é
substituir um PNG, nada mais.

---

## O que depende de você (não consigo fazer no seu lugar)

Tudo abaixo exige a sua conta Apple. São ~30 minutos.

### 1. Conferir a conta de desenvolvedor
O changelog registra que a conta saiu sem custo (A6, regra 13 intacta). Para o
TestFlight ela precisa estar **matriculada e ativa** — conta gratuita não sobe
build. Confira em [developer.apple.com/account](https://developer.apple.com/account).

### 2. Criar o app no App Store Connect
Bundle ID exato, sem inventar: **`br.com.canario.ch3.app`**

Se preferir outro, me avise **antes**: ele está no `gerar_projeto.py` e muda em
um lugar só.

### 3. Ligar a assinatura no Xcode
Abrir `app/Canario.xcodeproj` → alvo Canario → *Signing & Capabilities* →
marcar *Automatically manage signing* e escolher o seu time.

O projeto já vem com `CODE_SIGN_STYLE = Automatic`; falta só o time, que é
pessoal e não entra no repositório.

### 4. Garantir que o `Config.xcconfig` existe
Ele está no `.gitignore`. Sem ele o app compila e **sobe sem saber falar com o
servidor** — abre e não mostra nada.

```bash
cp Config.xcconfig.example Config.xcconfig
```

Depois preencha `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`. A chave
publishable é pública por construção; quem protege o banco é a RLS.

### 5. Arquivar e enviar
No Xcode: destino *Any iOS Device* → *Product* → *Archive* → *Distribute App* →
*TestFlight & App Store*.

---

## Texto para a ficha do TestFlight

Pronto para copiar. Cumpre a regra 1 e a §6 — nenhuma promessa de previsão.

**O que testar**

> Três abas. Em Analisar, descreva uma peça ("vestido de bolinha", "saia midi")
> ou importe um print, uma foto ou um PDF de página de produto — o arquivo é
> lido no próprio aparelho e descartado. Em Explorar, veja a curva de tamanhos
> do painel, as reposições e remarcações das marcas monitoradas, e o que mudou
> na semana. Em Comparar, ponha de 2 a 6 atributos lado a lado.
>
> O que mais interessa saber: algum número apareceu sem você entender de onde
> veio? Alguma tela disse "não sei" onde você esperava resposta — e isso
> incomodou ou ajudou?

**Descrição**

> Canário mede o mercado brasileiro de moda feminina e organiza a evidência
> para quem decide coleção, compra e reposição. Os números vêm de coleta
> própria em 16 marcas, da busca no Google Trends e de veículos de moda
> brasileiros e internacionais, com origem e data ao lado de cada leitura.
> Não é previsão de venda: informa a decisão, não decide.

---

## Uma decisão sua, e é rápida

O app se chama **Canário** na tela inicial. Mas a A8 diz que o codinome do
projeto nunca vira produto, e o teste de vocabulário barra "canario" como token
isolado na interface.

Nunca alinhamos se **Canário é o codinome ou é o nome do produto**. Enquanto foi
só simulador não fazia diferença; no TestFlight o nome passa a circular.

Se for o nome do produto, tudo certo e eu registro a exceção no changelog para o
teste não brigar depois. Se for codinome, precisamos de um nome antes de subir.
Não decido isso por você.

---

## O que NÃO vai nesta build, e é intencional

Para você não ser pego de surpresa se alguém perguntar:

- **Não existe número único da peça.** Falta o índice do cluster ponderado por
  raridade (K5). A tela declara isso em vez de mostrar uma média que enganaria.
- **A perna de varejo não tem z-score** (decisão B1) — entra como camada
  descritiva, e é de onde vem a curva de tamanhos.
- **O estado editorial usa 6 semanas de história**, não 8, pela exceção pontual
  que você abriu em 30/07. A tela declara quantas semanas sustentam o número.
- **Nomear a peça a partir de uma foto não existe.** Da imagem sai o texto (por
  OCR) e a cor (medida no pixel). Categoria exige modelo treinado.
- **Os veículos por trás de cada leitura** só aparecem a partir da coleta de
  01/08 — as linhas mais antigas não têm essa informação gravada.
