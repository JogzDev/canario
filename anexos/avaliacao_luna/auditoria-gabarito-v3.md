# Auditoria do gabarito Luna — categoria e cor v3

Data: **13/08/2026**. Imagens: as mesmas 24 da run `31452732941`.
Esta etapa não chamou a OpenAI.

## Fontes humanas

- Fadul: 24/24, revisão cega.
- Bianca: 24/24, revisão cega.
- JP: adjudicação das 10 amostras que divergiam no portão, com comentários
  descritivos preservados.
- Auditoria estrutural: leitura pixel a pixel contra as definições operacionais,
  sem usar a antiga resposta do Luna como voto.

Os dois revisores completos concordaram em apenas 19/24 categorias e 17/24
cores primárias. A auditoria encontrou quatro casos em que o consenso ou a
adjudicação ainda contrariava a própria definição estrutural da rubrica:

| amostra | antes | final | evidência decisiva |
|---|---|---|---|
| S01 | `camisa` | `blusa_top` | regata de gola redonda, sem colarinho, carcela, abertura frontal ou punhos |
| S03 | `camisa` | `blusa_top` | top de alças com bojo e barra curta, sem construção de camisaria |
| S11 | `vestido` | `saia` | midriff visível separa top e saia; a saia longa domina área, centro e enquadramento |
| S20 | `vestido` | `camisa` | colarinho, carcela, botões e nó frontal; a cauda não forma painel inferior inequívoco |

Essas correções não “ensinam a resposta” ao prompt. Elas removem do ouro o uso
coloquial de *camisa* para qualquer peça superior e aplicam a mesma hierarquia
que será exigida em produção: alvo → estrutura → categoria derivada.

## Casos-limite mantidos conscientemente

- **S10:** permanece `vestido`. A mudança abrupta preto/branco não prova duas
  peças e os revisores viram continuidade. Como as duas cores ocupam áreas
  grandes e próximas, `branco_cru` e `preto` são respostas primárias aceitas.
- **S14:** permanece `ambiguous_target`. Blusa e short de renda são pares de um
  conjunto; nenhuma das duas peças vence visualmente. O verde é fundo.
- **S18:** permanece `saia`. Há painéis sobrepostos e movimento, mas não existe
  evidência inequívoca de crotch, inseam ou dois tubos de perna. O rótulo fraco
  do catálogo dizia short, mas o teste é visual.
- **S21:** permanece `short` com `multiple_garments_target_clear`. É difícil,
  mas o short está inteiro, central e recebe o enquadramento inferior completo.
- **S23:** permanece `camisa`. O crop e o detalhe favorecem a parte superior do
  conjunto. Listras vermelhas e brancas são quase equilibradas, então ambas as
  cores primárias são aceitas sem esconder a matriz de confusão.

## Contrato v4 que nasce desta auditoria

1. Regata, camisole, bustier, top de alças ou camiseta sem construção de
   camisaria nunca viram `camisa` por uso coloquial.
2. `short` exige crotch, inseam ou duas aberturas/tubos de perna visíveis. Fenda,
   prega, wrap ou painéis móveis não bastam.
3. Pele no midriff, barra do top, cós separado ou sobreposição na cintura
   provam duas peças; só mudança de cor ou textura não prova.
4. Camisa longa só vira vestido quando a mesma peça forma inequivocamente um
   painel inferior que cobre a parte de baixo do corpo.
5. Cada resposta registra de uma a quatro evidências visuais. Título, marca,
   pasta e nome de arquivo são proibidos como evidência.
6. Empate real de cor pode ter duas respostas aceitas no gabarito, mas a saída
   do app continua ordenada e tem uma única cor primária.

O portão continua igual: no mínimo **20/24 em categoria** e **20/24 em cor
primária**, medidas separadamente. A meta de produto permanece **90%+**; 80% é
apenas autorização para ampliar o teste.
