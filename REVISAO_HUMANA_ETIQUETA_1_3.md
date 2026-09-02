# Revisão humana da Etiqueta 1.3 — roteiro operacional

## O que fazer agora

Nada. A página de revisão é uma ferramenta interna do laboratório, não uma tela
do app e não precisa ser aberta até existir uma execução real autorizada do
pacote da Etiqueta. A RPC A52 e o workflow continuam separados da produção.

## O que a página faz

Cada cartão mostra somente um pequeno trecho de etiqueta e o fato extraído dele.
Repetições exatamente iguais em produtos diferentes aparecem uma vez; a decisão
é reaplicada somente às ocorrências com a mesma assinatura semântica. Acima de
250 assinaturas únicas o piloto para e pede uma estratégia de shards, em vez de
congelar o navegador ou impor uma revisão humana impraticável.
O revisor escolhe uma destas decisões:

- **sustenta:** o trecho afirma exatamente o fato exibido;
- **rejeita:** família, faceta ou valor estão incorretos;
- **contexto insuficiente:** o trecho não permite decidir com segurança.

A página não mostra produto, marca, contagem, participação, confiança do parser,
conclusão de tendência nem a resposta de outra pessoa. Ela não tem rede e salva
o rascunho apenas no navegador. Se o armazenamento estiver bloqueado, avisa que
o rascunho existe só naquela sessão: exporte antes de fechar a página.
O alias identifica a função (`R1`, `R2`, `A1`),
não precisa conter nome real.

## Quando o piloto real for autorizado

1. Execute manualmente no GitHub Actions o workflow
   `Market Intelligence — pacote privado da Etiqueta`.
2. O workflow cria dois artefatos separados. O coordenador baixa e guarda
   `radar-etiqueta-coordenador-<run id>`, que contém o pacote factual necessário
   à consolidação. Para `R1` e `R2`, distribui apenas
   `radar-etiqueta-revisao-cega-<run id>`, que contém o HTML autocontido. Nunca
   entregue `radar-etiqueta-facts.json` a `R1`, `R2` ou `A1`; abrir esse JSON
   revelaria produtos, marcas, confiança e agregados e quebraria o cegamento.
   Os artefatos têm as mesmas permissões do repositório: a separação dos ZIPs
   facilita a distribuição correta, mas não é uma barreira de acesso entre
   colaboradores do GitHub. Revisores recebem somente o HTML.
   Antes de continuar, confira que `package_id` e `payload_sha256` do JSON são
   exatamente os dois hashes registrados no resumo daquela execução do Actions;
   é esse registro externo que ancora o arquivo baixado.
3. A primeira pessoa abre o HTML, usa o alias `R1`, revisa todos os fatos e
   exporta o JSON.
4. Uma segunda pessoa, sem consultar `R1`, abre o mesmo HTML, usa `R2` e exporta
   outro JSON. Os aliases precisam representar pessoas realmente distintas;
   trocar apenas o texto do alias não cria independência.
5. Use o mesmo commit que gerou o artefato. Coloque os dois JSONs ao lado do
   pacote e rode, a partir da raiz do projeto. Nos comandos abaixo, substitua
   `etiqueta-R1.json`, `etiqueta-R2.json` e `etiqueta-A1.json` pelos nomes
   efetivamente exportados (`etiqueta-<prefixo do lote>-<alias>.json`):

   ```sh
   python3 ferramentas/consolidar_revisao_etiqueta_radar.py \
     --pacote radar-etiqueta-facts.json \
     --revisao etiqueta-R1.json \
     --revisao etiqueta-R2.json \
     --saida radar-etiqueta-reviewed.json
   ```

6. Se houver consenso integral, `radar-etiqueta-reviewed.json` será o pacote
   privado revisado. Se houver divergências, ele será uma comparação auditável e
   o comando criará automaticamente
   `radar-etiqueta-reviewed-adjudicacao.html`.
7. Uma terceira pessoa, que não seja `R1` nem `R2`, abre somente a página de
   adjudicação, usa `A1` e exporta o JSON. Essa página contém apenas as
   divergências e não revela as escolhas anteriores.
8. Consolide de novo:

   ```sh
   python3 ferramentas/consolidar_revisao_etiqueta_radar.py \
     --pacote radar-etiqueta-facts.json \
     --revisao etiqueta-R1.json \
     --revisao etiqueta-R2.json \
     --adjudicacao etiqueta-A1.json \
     --saida radar-etiqueta-reviewed-final.json
   ```

## O que acontece depois

O resultado recalcula contagens e shares somente com fatos confirmados. Ele
continua privado, exige revisão conceitual e bloqueia staging de evidência. Não
grava no Supabase, não chama a Luna, não cria briefing e não publica nada no app.
Essa promoção pertence ao walking skeleton seguinte e terá outro portão.

O artefato do Actions expira em sete dias. Até o processo terminar, guarde juntos
o pacote original, as duas submissões, eventual adjudicação e o consolidado;
os hashes entre eles impedem misturar execuções, rubricas ou revisores.
