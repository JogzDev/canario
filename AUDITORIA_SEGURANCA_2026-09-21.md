# Auditoria de segurança — 21/09/2026

Escopo: app iOS, Edge Functions, Supabase, GitHub Actions e cadeia de
dependências. Esta matriz distingue proteção comprovada de proteção parcial;
ela não trata ausência de evidência como conclusão positiva.

## Resultado executivo

- **15 controles atendidos** no escopo atual.
- **4 controles parciais**, com risco e próxima ação declarados.
- **1 controle não aplicável** ao app nativo (cookies de sessão).
- O Gitleaks 8.30.1 não encontrou segredo no histórico integral nem na árvore atual.
  O único falso positivo era um checksum público documentado; a exceção exige
  simultaneamente regra, caminho e valor exatos.
- `npm audit` dos dois laboratórios retorna zero vulnerabilidades conhecidas.
- Nenhuma conclusão abaixo depende de a chave publicável do Supabase ser
  secreta: ela é pública por desenho e a autorização depende de RLS.

## Os 20 controles

| # | Controle | Estado | Evidência e limite |
|---|---|---|---|
| 1 | Esconder API keys | **Atendido** | OpenAI e `service_role` existem apenas no servidor/Secrets. O app recebe somente chave publicável. `.gitignore` exclui `Config.xcconfig`, `.env`, PEM e KEY. |
| 2 | Limpar secrets do Git | **Atendido** | O CI faz checkout integral e executa Gitleaks 8.30.1, fixado por versão e SHA-256, sobre todo o histórico e sobre a árvore atual. Os valores ficam 100% redigidos no log. A varredura local inicial não achou segredos; uma exceção de checksum público exige regra, arquivo e valor exatos. A proteção não depende do produto pago de secret scanning do GitHub. |
| 3 | Public key do banco | **Atendido** | O binário usa `SUPABASE_PUBLISHABLE_KEY`; nenhuma `SUPABASE_SERVICE_ROLE_KEY` existe no alvo do app. |
| 4 | Ativar RLS | **Atendido** | Tabelas internas têm RLS; `closet_items`, `estado_dos_produtos` e tokens Apple usam `FORCE ROW LEVEL SECURITY`. As políticas do Closet prendem leitura/escrita a `auth.uid()`. |
| 5 | Criptografia de dados | **Parcial** | Tráfego exige HTTPS, sessão fica no Keychain `ThisDeviceOnly` e o provedor cifra armazenamento. A59 prepara AES-256-GCM com chave versionada para o refresh token Apple, mas está somente na branch local. O controle só fecha depois de implantação coordenada, backfill das linhas A50 e contagem zero de valores legados em claro. |
| 6 | Auth server-side | **Atendido** | Identidade é validada pelo Supabase Auth; operações administrativas e revogação Apple ficam nas Edge Functions com `service_role`, nunca no app. |
| 7 | Restringir acessos | **Parcial** | RLS e permissões do workflow são restritas; `main` bloqueia force-push/deleção e exige os checks. Administrador não está submetido à regra e não há revisão obrigatória, decisão que evita bloquear um projeto hoje mantido por uma pessoa. O colaborador remanescente foi mantido por decisão explícita do responsável. |
| 8 | Bloquear mass assignment | **Atendido** | `aplicar_mudancas_closet` tipa/seleciona campos, atribui `auth.uid()` no servidor, limita 250 mudanças por chamada, 200 itens ativos e 400 totais. |
| 9 | Proteger cookies | **Não aplicável** | Não há sessão web por cookie: o cliente é nativo, usa `URLSession` efêmera para Auth e persiste apenas os tokens no Keychain. |
| 10 | Hash nas senhas | **Atendido** | Senhas são entregues por TLS ao Supabase Auth e não são armazenadas pelo app ou pelo schema da aplicação; hashing é responsabilidade do provedor de identidade. |
| 11 | Rate limit | **Atendido** | A análise visual reserva atomicamente 12 usos por origem/dia e 120 globais/dia sob advisory lock; Auth também responde a 429. |
| 12 | Bot protection | **Parcial** | Há limite por hash salgado de origem e teto global, mas não App Attest/DeviceCheck. O endpoint visual continua utilizável sem conta por decisão de produto, portanto rate limiting é mitigação, não prova de aparelho legítimo. |
| 13 | Queries parametrizadas | **Atendido** | O app usa JSON/RPC e encoding PostgREST; coletores usam cliente REST. As rotas públicas não concatenam input humano em SQL. |
| 14 | Validação de inputs | **Atendido** | A imagem aceita apenas JPEG/PNG, Base64 válido e até 3 MB; hint até 160 caracteres; saída da IA obedece schema fechado; URLs de produto exigem HTTPS; mudanças do Closet têm tipo e cardinalidade validados. |
| 15 | Evitar vazamento de conteúdo | **Atendido** | RPCs públicas projetam apenas campos consumidos e Edge Functions devolvem erros genéricos. `ACESSO_PUBLICO.md` inventaria a superfície; o CI fixa o histórico e reprova qualquer novo `GRANT` a `anon`, `authenticated` ou `PUBLIC` sem justificativa explícita. |
| 16 | Restringir uploads | **Atendido** | Bucket de miniaturas é privado, JPEG, 3 MB, caminho iniciado por `auth.uid()` e políticas por proprietário; o app reduz para 720 px, remove metadados e verifica checksum. |
| 17 | Trim de respostas de API | **Atendido** | Views/RPCs enxutas removem metadados que o app não lê; Edge Functions não devolvem detalhe do provedor; respostas sensíveis usam `no-store`. |
| 18 | Security headers | **Parcial** | As três Edge Functions agora devolvem `Cache-Control: no-store` e `X-Content-Type-Options: nosniff`. Headers do site Carrd e da borda Supabase são gerenciados pelos provedores e precisam ser conferidos na versão 2.0 publicada. |
| 19 | Forçar HTTPS | **Atendido** | O cliente agora rejeita explicitamente `http://` e falha fechado; ATS permanece ativo e URLs públicas de produto já eram validadas como HTTPS. |
| 20 | Scan de dependências | **Atendido** | Actions usam SHA imutável; OSV-Scanner 2.6.0 audita `Package.resolved` e os lockfiles npm no CI; as Edge Functions têm `deno.lock` com integridade da árvore inteira e passam por `deno check` e `deno audit --frozen-lockfile`. Alertas/correções de vulnerabilidade e Dependabot continuam ativos onde a plataforma oferece suporte. |

## Mudanças desta rodada

1. Endpoints Supabase/Auth com `http://` deixam de ser aceitos e desativam o
   cliente em vez de transmitir dados em claro.
2. Imports remotos das Edge Functions foram fixados nas versões auditadas
   `@supabase/server@1.7.0` e `@supabase/supabase-js@2.116.0`.
3. Todas as respostas das Edge Functions carregam `no-store` e `nosniff`.
4. Dependabot acompanha Actions e os dois lockfiles npm.
5. `teste_seguranca.py` impede regressão de HTTPS, headers, versões, SHA de
   Actions e inclusão de segredos servidores no app.
6. O repositório passou a exigir SHA imutável em Actions e teve alertas de
   vulnerabilidade e correções automáticas de segurança habilitados.
7. Swift e Deno ganharam portões gratuitos e reproduzíveis: OSV sobre o
   `Package.resolved`; lock, verificação de tipos e auditoria nativa no Deno.
   A execução local inicial encontrou 8 pacotes Swift e nenhuma vulnerabilidade
   conhecida; o `deno.lock` também passou sem achados.
8. O histórico e a árvore atual ganharam portão gratuito com Gitleaks fixado e
   checksum verificado. O checkout do job é completo, a saída é redigida e a
   configuração estende — não substitui — as regras oficiais.

## Pendências priorizadas

1. Implantar A59 apenas depois dos portões de
   `ferramentas/seguranca/ROTACAO_TOKEN_APPLE.md`, com secret, schema, funções,
   testes reais e backfill auditado; não declarar cifragem completa antes de
   zerar as linhas legadas.
2. Reavaliar revisão obrigatória/admin quando houver outra pessoa mantenedora,
   sem criar um bloqueio que o único responsável não possa satisfazer.
3. Avaliar App Attest/DeviceCheck para o endpoint visual antes da versão 2.0.
4. Conferir headers externos de Carrd e Supabase na auditoria final da versão
   2.0, junto com política e ficha da App Store.
