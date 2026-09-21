# Inventário de acesso público do banco

Este arquivo descreve a superfície intencional entregue à chave publicável do
aplicativo. Ele não transforma essa chave em segredo: a autorização continua
dependendo de privilégios mínimos, RLS e funções estreitas.

## Superfície existente em 21/09/2026

- Leitura de séries, índices, termos e cobertura já publicados.
- Leitura por coluna das peças, marcas e eventos necessários às views do app;
  colunas internas e qualquer coluna criada no futuro permanecem fechadas.
- RPCs de similares v1 e v2, eventos recentes, série por combinação, lookup de
  produto, resumo de eventos e busca de referência editorial.
- Para usuários autenticados, leitura do próprio Closet e a RPC tipada que
  aplica mudanças vinculando o registro ao `auth.uid()`.

As migrations também contêm concessões históricas posteriormente estreitadas
ou revogadas. O CI guarda uma impressão digital de todo esse histórico para
impedir que uma migration aplicada seja reescrita silenciosamente.

## Regra para qualquer migration nova

Todo `GRANT` destinado a `anon`, `authenticated` ou `PUBLIC` precisa ter, na
linha não vazia imediatamente anterior:

```sql
-- acesso-publico: motivo específico com pelo menos trinta caracteres
grant ... to anon;
```

O comentário deve dizer o dado ou a operação que o app precisa e por que uma
projeção mais estreita não basta. `service_role` não é superfície do cliente e
fica fora desta regra. O portão está em `coletor/teste_seguranca.py` e roda em
todo push e pull request.
