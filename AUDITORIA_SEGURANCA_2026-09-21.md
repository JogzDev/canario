# Auditoria de segurança — 21/09/2026

Escopo: app iOS, Edge Functions, Supabase, GitHub Actions e cadeia de
dependências. Esta matriz distingue proteção comprovada de proteção parcial;
ela não trata ausência de evidência como conclusão positiva.

## Resultado executivo

- **12 controles atendidos** no escopo atual.
- **7 controles parciais**, com risco e próxima ação declarados.
- **1 controle não aplicável** ao app nativo (cookies de sessão).
- A busca no histórico Git não encontrou chave OpenAI, chave secreta do
  Supabase, token GitHub, chave AWS nem chave privada. Os três acertos do padrão
  de URI de banco eram placeholders documentais, não credenciais.
- `npm audit` dos dois laboratórios retorna zero vulnerabilidades conhecidas.
- Nenhuma conclusão abaixo depende de a chave publicável do Supabase ser
  secreta: ela é pública por desenho e a autorização depende de RLS.

## Os 20 controles

| # | Controle | Estado | Evidência e limite |
|---|---|---|---|
| 1 | Esconder API keys | **Atendido** | OpenAI e `service_role` existem apenas no servidor/Secrets. O app recebe somente chave publicável. `.gitignore` exclui `Config.xcconfig`, `.env`, PEM e KEY. |
| 2 | Limpar secrets do Git | **Parcial** | Varredura integral do histórico não achou segredo real e o novo teste impede chaves servidoras dentro de `app/`. Secret scanning da plataforma ainda precisa ser habilitado se o plano do repositório privado oferecer o recurso. |
| 3 | Public key do banco | **Atendido** | O binário usa `SUPABASE_PUBLISHABLE_KEY`; nenhuma `SUPABASE_SERVICE_ROLE_KEY` existe no alvo do app. |
| 4 | Ativar RLS | **Atendido** | Tabelas internas têm RLS; `closet_items`, `estado_dos_produtos` e tokens Apple usam `FORCE ROW LEVEL SECURITY`. As políticas do Closet prendem leitura/escrita a `auth.uid()`. |
| 5 | Criptografia de dados | **Parcial** | Tráfego exige HTTPS, sessão fica no Keychain `ThisDeviceOnly` e o provedor cifra armazenamento. O refresh token Apple ainda não tem criptografia de aplicação além da camada de disco do provedor; migrá-lo exige desenho de rotação e não deve ser improvisado. |
| 6 | Auth server-side | **Atendido** | Identidade é validada pelo Supabase Auth; operações administrativas e revogação Apple ficam nas Edge Functions com `service_role`, nunca no app. |
| 7 | Restringir acessos | **Parcial** | RLS e permissões do workflow são restritas; `main` bloqueia force-push/deleção e exige os checks. Administrador não está submetido à regra e não há revisão obrigatória, decisão que evita bloquear um projeto hoje mantido por uma pessoa. O colaborador remanescente foi mantido por decisão explícita do responsável. |
| 8 | Bloquear mass assignment | **Atendido** | `aplicar_mudancas_closet` tipa/seleciona campos, atribui `auth.uid()` no servidor, limita 250 mudanças por chamada, 200 itens ativos e 400 totais. |
| 9 | Proteger cookies | **Não aplicável** | Não há sessão web por cookie: o cliente é nativo, usa `URLSession` efêmera para Auth e persiste apenas os tokens no Keychain. |
| 10 | Hash nas senhas | **Atendido** | Senhas são entregues por TLS ao Supabase Auth e não são armazenadas pelo app ou pelo schema da aplicação; hashing é responsabilidade do provedor de identidade. |
| 11 | Rate limit | **Atendido** | A análise visual reserva atomicamente 12 usos por origem/dia e 120 globais/dia sob advisory lock; Auth também responde a 429. |
| 12 | Bot protection | **Parcial** | Há limite por hash salgado de origem e teto global, mas não App Attest/DeviceCheck. O endpoint visual continua utilizável sem conta por decisão de produto, portanto rate limiting é mitigação, não prova de aparelho legítimo. |
| 13 | Queries parametrizadas | **Atendido** | O app usa JSON/RPC e encoding PostgREST; coletores usam cliente REST. As rotas públicas não concatenam input humano em SQL. |
| 14 | Validação de inputs | **Atendido** | A imagem aceita apenas JPEG/PNG, Base64 válido e até 3 MB; hint até 160 caracteres; saída da IA obedece schema fechado; URLs de produto exigem HTTPS; mudanças do Closet têm tipo e cardinalidade validados. |
| 15 | Evitar vazamento de conteúdo | **Parcial** | RPCs públicas projetam apenas campos consumidos e Edge Functions devolvem erros genéricos. Falta um inventário automatizado de toda nova função/tabela exposta antes de cada migration. |
| 16 | Restringir uploads | **Atendido** | Bucket de miniaturas é privado, JPEG, 3 MB, caminho iniciado por `auth.uid()` e políticas por proprietário; o app reduz para 720 px, remove metadados e verifica checksum. |
| 17 | Trim de respostas de API | **Atendido** | Views/RPCs enxutas removem metadados que o app não lê; Edge Functions não devolvem detalhe do provedor; respostas sensíveis usam `no-store`. |
| 18 | Security headers | **Parcial** | As três Edge Functions agora devolvem `Cache-Control: no-store` e `X-Content-Type-Options: nosniff`. Headers do site Carrd e da borda Supabase são gerenciados pelos provedores e precisam ser conferidos na versão 2.0 publicada. |
| 19 | Forçar HTTPS | **Atendido** | O cliente agora rejeita explicitamente `http://` e falha fechado; ATS permanece ativo e URLs públicas de produto já eram validadas como HTTPS. |
| 20 | Scan de dependências | **Parcial** | Actions usam SHA imutável, imports Deno foram fixados em versões exatas, `npm audit` está limpo e Dependabot foi configurado para Actions e os dois laboratórios. Swift/Deno ainda precisam de alerta automatizado equivalente. |

## Mudanças desta rodada

1. Endpoints Supabase/Auth com `http://` deixam de ser aceitos e desativam o
   cliente em vez de transmitir dados em claro.
2. Imports remotos das Edge Functions foram fixados nas versões auditadas
   `@supabase/server@1.7.0` e `@supabase/supabase-js@2.116.0`.
3. Todas as respostas das Edge Functions carregam `no-store` e `nosniff`.
4. Dependabot acompanha Actions e os dois lockfiles npm.
5. `teste_seguranca.py` impede regressão de HTTPS, headers, versões, SHA de
   Actions e inclusão de segredos servidores no app.

## Pendências priorizadas

1. Habilitar alertas de vulnerabilidade/Dependabot Security Updates no GitHub,
   conforme a disponibilidade do plano privado.
2. Desenhar criptografia de aplicação e rotação para o refresh token Apple;
   não alterar a tabela antes de existir caminho de migração e revogação.
3. Avaliar App Attest/DeviceCheck para o endpoint visual antes da versão 2.0.
4. Criar um portão de migration que inventarie qualquer novo `GRANT` a
   `anon`/`authenticated` e exija justificativa explícita.
5. Conferir headers externos de Carrd e Supabase na auditoria final da versão
   2.0, junto com política e ficha da App Store.
