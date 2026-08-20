# v6 e v7 — as duas correções que só o aparelho confirmou

Registro de 19–20/08/2026. As duas nasceram de uma peça real que o JP
fotografou: um fleece quarter-zip cinza da Patagonia, com etiqueta roxa no
peito.

## v6 — o prompt ensinava que agasalho é alfaiataria

**Sintoma:** o app pré-selecionou `Tops & T-shirts`. A leitura da Luna, na mesma
tela, dizia *"visible long sleeves, pullover construction, and quarter-zip
front"* e *"so it is not shirt construction"*.

**Causa:** a Luna não escolhe a categoria — ela descreve a estrutura e o app
mapeia. E `upper_outer_layer` estava definido só com evidência de alfaiataria:
lapela, ombro estruturado, frente estruturada, bolso embutido, transpasse. Um
fleece não tem nenhuma. `upper_other` é o residual "depois de descartar camisa e
agasalho", então ela descartou camisa **com evidência**, não achou sinal de
blazer, e caiu no residual.

**Correção:** segunda família de evidência — zíper no peito (inteiro, meio ou
quarter), capuz, punho ou barra canelada, superfície de fleece, matelassê,
acolchoado ou impermeável, cordão de ajuste. E a frase que faltava: *pullover
construction does NOT rule out an outer layer*.

**Confirmado no aparelho:** a mesma peça passou a ler `Coats & jackets`, com a
evidência *"consistent with an outer layer"*.

## v7 — etiqueta de marca contava como cor da peça

**Sintoma:** a peça saiu com `Gray` **e** `Purple & lilac`. O roxo é a etiqueta
da Patagonia, de poucos pixels. Com seis atributos marcados, o painel devolveu
zero peças semelhantes.

**Causa:** o prompt já tinha o limiar de área — *"a secondary color must cover
about 10 percent of the target"* — e já mandava ignorar *"tiny trim, buttons,
crystals, shadows, skin, and background"*. Etiqueta de marca não é nenhuma
dessas coisas.

**Correção:** logo, patch no peito, etiqueta tecida, tag, wordmark impresso e
bordado entraram na lista, com o exemplo literal: *"A grey fleece with a purple
brand patch is grey, not grey and purple."*

**Confirmado no aparelho:** `Purple & lilac` desmarcado.

## Por que o benchmark não mede nenhuma das duas

| | o que a correção precisa | o que as 24 têm |
|---|---|---|
| v6 | agasalho casual — fleece, moletom, parka | `casaco_jaqueta` 3×, **as três de alfaiataria** |
| v7 | peça com etiqueta de marca visível | nenhuma |

A v6 foi medida e deu **83,3%**, idêntico à v5 — não porque não funciona, mas
porque a amostra não contém o caso. A v7 não foi medida.

**Consequência prática:** enquanto as 24 forem estas, mudanças nesses dois eixos
continuarão invisíveis ao portão. A amostra precisa de agasalho casual e de peça
com etiqueta antes de servir para julgar este tipo de correção.

## Estado do portão

O portão é da **v6** (`328ea36b…`). O prompt é **v7**. `validar_portao_24` exige
que as versões batam, então o benchmark pago de 300 está bloqueado até uma
rodada v7 realinhar o arquivo.

O gabarito humano não precisa ser refeito: ele não depende do prompt.
