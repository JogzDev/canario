# Implantação da análise visual A15

O código do app fica desligado até este roteiro terminar. Nenhuma chave da
OpenAI entra no Xcode, no GitHub ou neste arquivo.

## O que já existe

- `supabase/migrations/20260814150000_p6_limite_da_analise_visual.sql`:
  reserva atômica por origem e por projeto, sem guardar IP cru;
- `supabase/functions/analisar-peca/index.ts`: autentica a publishable key,
  limita tamanho, chama `gpt-5.6-luna` com `store=false`, valida a resposta e
  devolve apenas o contrato aprovado;
- app iOS: consentimento explícito, timeout, ids filtrados pela taxonomia e
  fallback local/manual;
- `REMOTE_ANALYSIS_ENABLED=NO` por padrão.

## Implantar

1. Aplicar as migrations pendentes no projeto ligado.
2. Em Edge Functions > Secrets, cadastrar:
   - `OPENAI_API_KEY`: chave do projeto OpenAI;
   - `AI_RATE_LIMIT_SALT`: valor aleatório de pelo menos 24 caracteres, criado
     localmente. Não enviar esse valor por chat nem commitar.
3. Implantar a função `analisar-peca` usando o dashboard ou a CLI oficial.
4. Confirmar no dashboard que a função aceita publishable API key e que o
   platform JWT check está desligado conforme `supabase/config.toml`.
5. Fazer primeiro um teste de contrato sem foto. Só depois executar **uma** foto
   real deliberadamente, sabendo que essa segunda chamada consome poucos
   créditos.
6. Acrescentar `REMOTE_ANALYSIS_ENABLED = YES` ao `Config.xcconfig` local usado
   pelo build Release.
7. Recompilar e verificar no iPhone: disclosure → análise → atributos marcados
   → correção humana → Save to Closet → exclusão.

## Reverter sem quebrar o app

Definir `REMOTE_ANALYSIS_ENABLED = NO` e gerar novo build. OCR, cor local e
formulário continuam disponíveis. Revogar o secret da Edge Function impede
novos gastos no servidor; não colocar uma chave vazia no app.
