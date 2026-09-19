# Retomada: publicação, capacidade e execução

## Resultado desta rodada

Código na branch `codex/verificacao-publicacao-painel`, baseado na main
`d2e610b`. Nenhum push, merge, workflow disparado, migration, coleta ou
compactação em produção. As consultas foram somente leitura. O SQL Editor
foi usado em uma aba separada; credenciais não foram copiadas para código ou
relatórios. O supervisor e o agendamento da madrugada não foram modificados.

### 1. O falso verde foi corrigido no código local

O pipeline de 19/09 (`35435828292`) concluiu o motor com
`observacoes_publicadas=0`. A API pública confirmou o painel em **02/09**,
17 dias antes. A sonda anterior verificava contrato, não atualização.

Agora existem duas provas explícitas:

- Contrato: as três RPCs públicas existem e devolvem o formato esperado. Pode
  passar com dado antigo e declara que não verificou atualização.
- Publicação diária: depois do motor, similares e eventos precisam declarar
  a mesma data publicada, igual ou posterior à data operacional da coleta.
  A data vem da primeira etapa do pipeline, não do relógio ao terminar.

Ausência/data antiga sai com código 2; leituras divergentes são
**inconclusivas**, também sem aprovação. Falha de rede/contrato sai com 1.
O JSON preserva o diagnóstico. O alerta diário passa a depender dessa prova
para encerrar incidente. Não há retry de coleta nem mudança da regra SQL.
Uma reexecução que altera zero marcadores pode passar se o dia já foi publicado.

**Limite de escopo:** o gate é do painel `feminino_casual_br` no pipeline diário.
Não atesta frescor do catálogo candidato, da direção internacional nem de todo
o editorial. A sonda manual continua sendo de contrato; não libera o app.

### 2. Capacidade medida, não presumida

Evidência bruta: `anexos/observacao_2026-09-19.json`.
Consultas repetíveis: `91_diagnostico_pos_poda.sql`.

- Cota na última consulta: **418.536.245 bytes**, 83,71% de 500 MB.
- Margem até 85%: **6.463.755 bytes**.
- `snapshots`: **73.138.176 bytes físicos**, sendo heap 50.298.880 e índices
  22.790.144, para **83.400 linhas**; conteúdo lógico medido em 12.470.120 bytes.
- Heap estimado após reconstrução: 13.445.538 bytes; índices conhecidos:
  1.871.867 + 2.620.614; TOAST atual de 8.192 bytes. Aproximadamente **18 MB**
  no total, antes de pequenas estruturas auxiliares.
- Potencial estimado: **cerca de 55 MB recuperados**; cota hipotética perto
  de **363 MB**, mantendo constantes as outras relações. Não é promessa de
  tamanho, duração ou sustentabilidade futura.

A poda já retirou linhas antigas, mas o espaço físico continua reservado para
reutilização da tabela. **Não é necessário apagar mais histórico para estudar
esta recuperação.** Não foram instaladas extensões de diagnóstico.

`VACUUM FULL` reescreve a relação e requer lock exclusivo e espaço temporário;
não é uma rotina diária. A documentação oficial confirma essas limitações:
[PostgreSQL 17 — VACUUM](https://www.postgresql.org/docs/17/sql-vacuum.html).

Não atribuir crescimento diário pelos tamanhos acima: esta é uma baseline,
não um par antes/depois de cada coleta. Os contadores de updates são
acumulados. Os dias 18 e 19 também não são intercambiáveis: 44.554 snapshots
na retomada contra 516 no dia seguinte. Não extrapolar um deles como média.
Após compactar, novas inserções podem voltar a alocar páginas; a redução
pontual da cota não substitui a observação do volume da janela de retenção.

### 3. A cobertura bloqueadora foi identificada

Das **15 marcas esperadas**, 14 têm visitação positiva, acima do piso de 30%
do histórico positivo de sete dias, sem flags de corte. **Animale é a única
fora dessas condições hoje**, com zero e `robots proibe a busca` no run de
19/09. O código posterior da PR29 deixa a nova rota desligada por capacidade.

Não é correto retirar a Animale da coorte apenas para avançar o relógio.
O ensaio da rota pública já terminou com 5.090/5.104 páginas interpretadas,
1.811 produtos do recorte, 14 falhas externas. Não atesta catálogo completo.
Habilitar essa rota ainda depende de margem para escritas reais e de acompanhar
as falhas registradas; esta rodada não a habilitou.

O catálogo candidato tem seu próprio marco em 25/08. A prova do painel diário
não resolve nem certifica esse outro segmento.

## Verificação executada

- 35 suítes Python sem rede passaram; `teste_30s.py` foi excluído por fazer
  descoberta externa de lojas, como no CI existente.
- 14 mutações de workflow provam que o gate não pode ser removido, ignorado,
  perder a data original ou deixar o alerta fechar apenas com o motor verde.
- Sonda estrita contra produção, com chave pública: código 2,
  `observacao_anterior`, data 02/09 nas duas RPCs. Nenhuma escrita.
- Laboratório SQL de significado: 25 verificações, incluindo as oito consultas
  do diagnóstico novo executadas em transação READ ONLY.
- Ensaio do roteiro: verde; caso adicional de snapshots com dados sintéticos
  preservou contagem e hash de todas as linhas e ambos os índices válidos.
  Espaço no laboratório: **22.593.536 → 7.913.472 bytes**. Isso não estima tempo
  de produção nem reproduz exatamente sua população.
- Swift/UI não foram reexecutados nesta rodada: não houve mudança no app.
- Actions desta branch ainda não rodou: a branch não foi enviada.

## Sequência recomendada, com limites explícitos

1. Preparar uma única janela curta para recuperação física de `snapshots`:
   conferir backup/recuperação, ausência de motor/coletas, locks e espaço
   temporário; registrar contagem e assinatura antes/depois; manter timeouts
   do executor. O comando de compactação de produção **não foi adicionado
   a nenhum job nem executado**. Precisa de autorização para essa nova janela.
2. Medir o ganho real e reavaliar margem para a Animale e o restante da coleta.
   Somente então combinar o rollout da flag com a verificação de publicação.
   Não liberar a flag só porque a estimativa parece suficiente.
3. Fazer a coleta real controlada e verificar a data pública, a cobertura e
   a cota ao final. Só contar como dia saudável quando esses critérios passarem.
4. Seguir a observação, podendo desenvolver/testar o app offline durante ela.

**Dependência do supervisor:** ele hoje interrompe futuras coletas se o pipeline
falhar. Implantar só o novo gate, enquanto a Animale está desligada, poderá
acionar essa interrupção. Por isso este pacote não foi publicado isoladamente.
Isso não é motivo para enfraquecer o gate ou chamar um dia parcial de saudável.

**Execução durável:** na consulta desta rodada havia zero runners registrados,
como esperado entre as janelas efêmeras. Os dois workflows agendados estavam
ativos. Hoje a execução ainda depende do notebook e do supervisor com prazo em
26/09. A proteção de energia de 20/09 não resolve disponibilidade permanente.
Escolher uma máquina sempre disponível, com acesso residencial quando exigido
pelas fontes, antes desse prazo. Não foram comprados serviços, reativadas
máquinas de terceiros nem criadas rotinas permanentes.
