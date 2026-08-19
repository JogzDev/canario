# Luna v6 — o prompt aprendeu agasalho casual

## Por que a v6 existe

O JP fotografou um fleece quarter-zip da Patagonia e o app pré-selecionou
**Tops & T-shirts**. A leitura da Luna, na mesma tela, dizia o contrário:
*"visible long sleeves, pullover construction, and quarter-zip front"* e *"so it
is not shirt construction"*.

Ela não errou. O prompt define `upper_outer_layer` só com evidência de
alfaiataria — lapela, ombro estruturado, bolso embutido, transpasse. Um fleece
não tem nenhuma. E `upper_other` é o residual "depois de descartar camisa e
agasalho". Ela descartou camisa com evidência, não achou sinal de blazer, e caiu
no residual.

A v6 dá uma segunda família de evidência: zíper no peito (inteiro, meio ou
quarter), capuz, punho canelado, superfície de fleece, matelassê, acolchoado ou
impermeável, cordão de ajuste. E diz explicitamente que **construção pullover
não exclui agasalho**.

## O resultado medido: nada mudou

| | categoria |
|---|---:|
| v5 com segmentador | 20/24 — **83,3%** |
| v6 com segmentador | 20/24 — **83,3%** |

Uma imagem mudou, e trocou um erro por outro: `12550.jpg` (humano: `camisa`)
saiu de `not_visible` para `casaco_jaqueta`.

## Por que o benchmark não consegue medir esta correção

O gabarito das 24 imagens tem `casaco_jaqueta` três vezes, e as três são peças
de alfaiataria — o caso que a v5 **já acertava**. **Não há um único fleece,
moletom, parka ou corta-vento na amostra.**

Ou seja: a correção mira um caso que a amostra não contém. O número não podia
subir, e não subiu. Isso não é evidência de que a correção não funciona; é
evidência de que **esta amostra não responde a esta pergunta**.

## O sinal de risco, que não escondo

`12550.jpg` migrar para `casaco_jaqueta` sugere que a definição mais larga pode
estar puxando camisa para agasalho. Um ponto não é tendência, mas é o lugar
para onde olhar se a próxima medição piorar.

## O que fazer com isto

1. **Verificação direta:** refotografar o quarter-zip e conferir se agora lê
   `casaco_jaqueta`. É o único teste que responde à pergunta que originou a v6.
2. **A amostra precisa de agasalho casual.** Enquanto as 24 não tiverem fleece,
   moletom ou parka, nenhuma mudança nesse eixo será mensurável.

## Estado do portão

O portão humano em `portao_luna_24.json` é da **v5** (`f376aba9…`). O prompt
agora é **v6** (`328ea36b…`). `validar_portao_24` exige que as versões batam,
então o benchmark pago de 300 está **bloqueado** até o portão ser regerado.

O gabarito humano não precisa ser refeito — ele não depende do prompt. O que
falta é regerar o arquivo do portão a partir das respostas da v6 contra o mesmo
gabarito, o que é mecânico e ainda não foi feito.
