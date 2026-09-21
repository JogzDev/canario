# Autonomia operacional — 21/09/2026

## Objetivo

Retirar o Mac pessoal do caminho regular de coleta, publicação, verificação e
CI sem abrir mão dos portões que impedem publicação parcial ou estouro do
banco. O computador do responsável deixa de ser executor; continua sendo só
uma estação opcional de desenvolvimento.

## Arquitetura escolhida

- O pipeline diário das 03:00 BRT roda em `ubuntu-latest` do GitHub Actions.
- O catálogo candidato roda segunda e quinta, também em Ubuntu gerenciado.
- A sonda da Edge Function e as verificações de produção rodam em Ubuntu.
- Google Trends usa Ubuntu no caminho regular e `macos-latest` apenas como
  recuperação manual gerenciada. Nenhum dos dois é um computador pessoal.
- A lógica Swift roda uma vez no macOS gerenciado do GitHub. O build do app e
  os fluxos de interface completos usam Xcode Cloud, com configuração pública
  de exemplo e sem acesso a produção.
- A Animale faz varredura integral às segundas-feiras. Nos outros dias, o
  relatório registra `adiado_por_cadencia`, preserva a última observação e não
  afirma que o catálogo foi medido naquele dia. Existe override manual
  explícito e auditável para recuperação.

## Evidência de compatibilidade de rede

Run `35561408640`, sem credenciais Supabase e sem escrita:

| Origem | Ubuntu gerenciado | macOS gerenciado | Decisão |
|---|---:|---:|---|
| VTEX / Cantão | HTTP 206 válido | HTTP 206 válido | Ubuntu regular |
| Shopify / Amaro | HTTP 200 válido | HTTP 200 válido | Ubuntu regular |
| FFW | HTTP 200 válido | HTTP 200 válido | Ubuntu regular |
| Google Trends | fluxo completo HTTP 200 | fluxo completo HTTP 200 | Ubuntu + portão; macOS como recuperação |
| BoF robots | HTTP 403 | HTTP 403 | não contar como cobertura |

Uma execução anterior recebeu HTTP 429 do Google Trends em Ubuntu. Por isso a
compatibilidade não é tratada como promessa de disponibilidade: saúde,
recuperação e publicação atômica continuam obrigatórias.

## Por que a Animale é semanal

O sitemap autorizado expõe 5.104 URLs, mas publica o mesmo `lastmod` diário em
todas elas. Não existe sinal incremental confiável. A execução real de 20/09
levou 6.660 segundos, leu 5.067 páginas e recebeu 37 respostas HTTP 500. Fingir
incrementalidade perderia mudanças silenciosamente; repetir a varredura todos
os dias consumiria quase toda a franquia gratuita.

## Orçamento conservador

Estimativa baseada nas durações reais de 20/09, não em duração teórica:

- pipeline sem Animale: cerca de 42 minutos × 30 dias = 1.260 minutos;
- Animale integral: cerca de 111 minutos × 4 segundas = 444 minutos;
- catálogo candidato: cerca de 11 minutos × 8 execuções = 88 minutos;
- sondas/verificações recorrentes: cerca de 30 minutos;
- total operacional esperado: aproximadamente 1.822 minutos Linux/mês.

O GitHub Free inclui 2.000 minutos por mês em repositórios privados e o Pro,
3.000. Como a margem no plano Free é pequena, o build/UI completo não pode
consumir minutos macOS do GitHub. O Xcode Cloud incluído no Apple Developer
Program oferece 25 horas de computação por mês e fica responsável por essa
parte. Fontes oficiais consultadas em 21/09/2026:

- https://docs.github.com/en/billing/reference/product-usage-included
- https://developer.apple.com/xcode-cloud/

Durante os primeiros sete dias, a duração real é autoridade. Se dias comuns
passarem repetidamente de 60 minutos, ou a segunda-feira passar de 180, a
agenda deve parar para revisão antes de comprometer a franquia. Não se compra
capacidade automaticamente.

## Portões preservados

1. Capacidade é conferida antes de cada frente que escreve.
2. Saúde observa as quatro pernas antes do motor.
3. Recuperação não troca a data operacional no meio da execução.
4. Motor só publica depois de saúde verde.
5. Publicação parcial abre incidente; não vira painel silenciosamente.
6. Animale pulada por cadência é advertência explícita, não falha nem sucesso
   inventado.
7. Jobs automáticos falham no teste estrutural se voltarem a usar rótulos de
   runner pessoal.
8. Actions externas são fixadas por SHA completo.
9. Testes de interface que consultam dados reais exigem
   `CANARIO_REAL_DATA_UI_TESTS=1`; a automação não define essa variável.
10. O script do Xcode Cloud recusa Archive e qualquer contexto fora do Cloud.

## Ordem segura da virada

1. Integrar esta mudança com CI gerenciado verde.
2. Confirmar um build/teste novo no Xcode Cloud.
3. Manter o supervisor local somente até a primeira execução agendada
   integralmente gerenciada concluir com publicação e capacidade em até 85%.
4. Desativar e remover o supervisor local; não deixar dois executores com a
   mesma autoridade.
5. Observar sete marcos consecutivos, incluindo uma segunda-feira com Animale
   e uma segunda/quinta de catálogo candidato.

Não há coleta, migration, limpeza ou alteração de credencial nesta mudança de
código. A troca de executor só ocorre depois dos portões acima.

## Fora do caminho regular

Ferramentas de descoberta de marca, avaliação Luna e geração de centroides
continuam manuais. Elas não bloqueiam nem executam a coleta diária. Antes de
virarem rotina, precisam de orçamento, contrato e portão próprios.
