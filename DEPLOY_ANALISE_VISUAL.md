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
3. Implantar a função `analisar-peca` **pela CLI oficial, com `--use-api`**:

   ```
   supabase functions deploy analisar-peca \
     --project-ref tbluoqpnjqsflfoclmms --use-api
   ```

   `--use-api` empacota no servidor. Sem ele a CLI tenta usar Docker e trava
   sem imprimir nada — o Mac do JP não tem Docker.
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


## Como saber que a função está de pé (18/08/2026)

Um POST com corpo vazio, usando só a publishable key, distingue os três estados
sem gastar um token da OpenAI — a função confere os secrets **antes** de validar
a imagem:

| Resposta | Significa |
|---|---|
| `503 {"code":"BOOT_ERROR"}` | a função **não sobe**; o artefato publicado está quebrado |
| `503 {"error":"analysis_not_configured"}` | sobe, e falta `OPENAI_API_KEY` ou `AI_RATE_LIMIT_SALT` |
| `400 {"error":"invalid_image"}` | sobe e os secrets estão cadastrados |

```
curl -s -X POST "$SUPABASE_URL/functions/v1/analisar-peca" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" -d '{}'
```

### O episódio que motivou esta seção

Em 18/08 a função respondia `BOOT_ERROR` desde o deploy de 14/08. Ninguém
percebeu porque `REMOTE_ANALYSIS_ENABLED` estava `NO` e o app nunca a chamava.
Cadastrar os secrets não teria resolvido: ela nem chegava a lê-los.

O diagnóstico foi por eliminação, com uma função-sonda descartável que subia o
mesmo import e o mesmo estilo de handler. Provou-se que `npm:@supabase/server`,
`withSupabase({auth:"publishable"})` e os recursos de TypeScript usados sobem
normalmente, e que o `index.ts` do disco estava íntegro — 288 linhas, chaves
balanceadas. Ou seja: **o artefato publicado não era o arquivo do disco.**

A correção foi republicar do disco pela CLI. Deploy por transcrição de conteúdo
é o que se deve evitar aqui: o `INSTRUCTIONS` é o prompt, e o `prompt_sha256`
amarra o portão das 24 ao que roda em produção. Um caractere trocado muda o
comportamento pago sem que nenhum teste local perceba — o `teste_edge_luna.py`
confere o arquivo, não a implantação.
