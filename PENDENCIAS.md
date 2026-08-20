# Pendências do DataDrobe

Triagem da revisão de uso de 20/08/2026 (JP, Davi e Bianca), mais o que já
estava aberto. As categorias têm os nomes que o JP pediu para manter.

O critério da triagem foi um só: **isto me faz confiar mais no app, ou é
preferência?** Nem tudo que foi relatado é defeito, e está anotado qual é qual.

---

## Vale muito, mas não é barato

Nenhum destes é dúvida sobre *se* deve ser feito. São todos trabalho real,
grande demais para caber numa noite.

### Telas que ainda não existem
Favorites · Account · Settings · Terms · Privacy · Q&A.

**Terms e Privacy não são opcionais** — a App Store exige as duas, e hoje elas
são texto dentro de `TelaDoMenu`, não telas próprias. As outras quatro são
produto.

### Similares com foto no painel
> *"E aí ter os similares logo em seguida e com foto! Não tô mais vendo eles e
> acho que é a parte mais legal da nossa ferramenta."*

O dado já vem: `similares_da_peca` devolve `imagem_url` desde a P3, e hotlink é
o que a regra permite (hotlink não é cópia). Falta a tela. **Concordo que é a
parte mais interessante do produto e que ela está escondida.**

### Hierarquia do Market panel
Atributos confirmados como ícones horizontais em vez de lista vertical; `Result`
mais curto ou ausente; similares logo em seguida. Isso é desenho de tela, não
ajuste — precisa de uma proposta antes de código.

### Filtro no armário
Por atributo e por favoritado. Depende de decidir se favorito é um campo novo em
`PecaSalva` ou uma lista separada.

### Os 2,9% de link quebrado
> *"e tem uns q tá dando página não encontrada"*

Medido e real. A peça sai do ar na marca e o app continua oferecendo o link.
Precisa de uma verificação de vida do link, e ela custa requisição — o que
esbarra na regra 7 (1 req/s por domínio).

### Menos texto na tela "Which item"
Concordo com o diagnóstico. Precisa de redação, não de código.

### Fotos na tela de Trends
> *"Tem como adicionar foto das imagens? Seria maravilhoso!"*

Mesmo caminho dos similares com foto.

### Composição da amostra das 24
As 24 imagens do portão da Luna não têm **um único** fleece, moletom, parka ou
corta-vento, e nenhuma peça com etiqueta de marca visível. São exatamente os
dois casos que a v6 e a v7 corrigiram e que só o aparelho do JP verificou. É
trabalho de curadoria: escolher imagens novas e rotular à mão.

---

## Investigar antes de decidir

Aqui não sei ainda se é defeito nosso. Medir primeiro, decidir depois.

### Similares somem depois de corrigir a categoria
> *"E identificou como blusa ao invés de casaco. Após eu trocar para casaco,
> nenhum resultado de similares foi encontrado."*

Mesmo sintoma do print do JP: painel vazio com seis atributos marcados. Pode ser
a regra dos 70% de semelhança mordendo, pode ser bug de recálculo. **Não mexer
sem medir** — mudar o limiar no escuro troca um erro visível por um invisível.

### Loading de ~30 s ao importar peça no iPhone 15
Aberto desde 19/08. O que era reproduzível no Mac foi reduzido (242 → 241 ms), e
**a causa dos 30 s continua sem prova**. Precisa de medição no aparelho.

### "Earth tones" no lugar de cinza escuro
A v6 consertou a parte da categoria (moletom lido como casaco). A cor continua:
uma peça cinza-escura voltou como `terrosos`. Suspeita de balanço de branco na
foto, não de prompt — mas é suspeita.

### Artefato de cor rosa na tela Add
Relatado em 19/08. O feixe do topo parou de pintar oliva no escuro, mas o relato
original era de algo **rosa**, e isso não reproduzi: só há runtime iOS 26.2
nesta máquina, e o iPhone 15 com 18.7 usa o caminho de compatibilidade.
**Precisa de uma foto.**

### Todas as categorias escondidas
> *"Não sei se tem porque TODAS as categorias estarem escondidas."*

Parte disso já caiu em 20/08 — cor, estampa, tecido e estética deixaram de
depender de categoria escolhida. Falta entender se o relato era sobre isso ou
sobre o `DisclosureGroup` vir recolhido.

### "Preço a ser praticado sumiu dessa tela?"
Não confirmei se sumiu ou se mudou de lugar. Uma tela, cinco minutos, mas
precisa ser olhado antes de "consertar" algo que talvez esteja certo.

---

## Discordo, ou é preferência (registrado, não agendado)

Não estão aqui por serem ruins. Estão aqui porque a decisão é do JP e eu tenho
uma posição.

**Deixar o app só em modo claro.** Contra. O problema descrito é a paleta escura
puxar para o esverdeado — isso conserta nos tokens. Apagar o modo escuro por
causa de um tom errado é amputar para tratar unha encravada, e quem usa o
aparelho no escuro perde.

**Título em minúscula vs. CAPS LOCK.** Não é defeito nosso: é como cada marca
escreve o próprio produto. Dá para normalizar na exibição, mas normalizar também
distorce o dado da marca — e a diferença some da tela sem sumir do mundo.

**Compare junto do Weekly Trends**, botão melhor para guardar, tirar o "1 of
200" e o texto abaixo dele: preferência legítima, custo baixo, sem urgência.

**Taxonomia amigável.** O JP levantou: *"não seja muito amigável com o usuário
fazer ele descrever o que é uma peça romântica"*. Concordo com o incômodo — mas
`estetica` alimenta o casamento de similares, então trocar o vocabulário mexe no
motor, não só no rótulo. É um projeto, não um ajuste, e merece entrar como tal
quando for a vez.

---

## Infraestrutura

**`VACUUM FULL` não volta sozinho.** O banco saiu de 93% para 55% em 20/08, mas
o inchaço volta com o uso: `produtos` é reescrita todo dia. Vale medir de novo
em algumas semanas, e considerar `pg_repack` — está disponível na instância e
reconstrói sem lock exclusivo, ao custo de instalar a extensão e rodar o
binário cliente.

**Alerta de "o pipeline nem começou".** O alerta de falha existe desde 19/08,
mas roda no mesmo Mac que executa a coleta. Se a máquina estiver parada, ninguém
é avisado. `ubuntu-latest` **falha antes de começar** nesta conta, por bloqueio
de billing — medido em 19/08. Sem gastar, a saída é algo fora do GitHub.

**Benchmark de 300 imagens.** Liberado desde 20/08, quando as três rodadas
somadas abriram o portão (81,9% categoria, 83,3% cor, 72 observações). Nunca foi
rodado com o segmentador atual.
