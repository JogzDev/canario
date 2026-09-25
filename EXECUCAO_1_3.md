# Execução da 1.3 — estado verificável por pacote

**Atualizado em 05/09/2026.** A `BLUEPRINT_DATADROBE_1_3.md` declara este
arquivo como o lugar onde o estado de cada pacote é conferível. Ele não existia
até hoje; a blueprint apontava para o vazio, e "o estado está no EXECUCAO" era,
na prática, "o estado não está em lugar nenhum".

A regra deste arquivo é a regra do `ESTADO.md`: **nada entra sem o comando que
prova**. Uma linha aqui é um fato reproduzível ou não é uma linha.

## Como ler em 30 segundos

| Pacote | Estado | O que sustenta |
|---|---|---|
| P0 — recuperação e contrato | **fechado** | worktree `Canario-1.3-blueprint`, branch `codex/1.3-blueprint`, baseline `6f6eac2` |
| **P1 — uma passagem inteira** | **parte transacional validada**; a cadeia extração→admissão, não | laboratório executado em PostgreSQL 17.10 real, 17 checagens, 3 execuções seguidas |
| P2 — dados duráveis | não começou | — |
| **F1 — fontes utilizáveis** | **não começou, e é o gargalo** | nenhuma fonte externa admitida; só `datadrobe_curadoria_interna` está `green` |
| P3 — afirmações e edição | não começou | depende de P2 e F1 |
| P4 — Luna avaliada | não começou | depende de P3 e de teto de custo autorizado |
| P5 — experiência privada | não começou | depende de P3 |
| P6 — piloto real | não começou | depende de F1 + P4/P5 |
| P7 — liberação | não começou | produção permanece congelada |

**O que a 1.3 é hoje, dito sem eufemismo:** uma fundação de evidências provada
em laboratório, com **zero fonte externa admitida** e **zero leitura
publicável**. É "Etiqueta interna em laboratório", exatamente o rótulo que a
própria blueprint manda usar enquanto a F1 não responder. Não é um radar.

---

## P1 — a passagem completa, executada

### O que estava pronto e o que faltava

O Codex deixou o laboratório montado e **nunca executado**. O
`README_RUNTIME.md` documentava uma interface de quatro entradas e duas não
existiam:

| Arquivo | Estado em 02/09 | Estado em 05/09 |
|---|---|---|
| `executar.mjs` | pronto (274 linhas) | inalterado |
| `schema_admissao.sql` | pronto (411 linhas) | inalterado |
| `teste_admissao.sql` | pronto (252 linhas) | dois casos corrigidos, ver abaixo |
| `gerar_fixture.py` | **não existia** | escrito |
| `teste_concorrencia.mjs` | **não existia** | escrito |

Sem a fixture, o `teste_admissao.sql` não rodava: a última linha dele chama
`preparar_fixture_de_teste_v1(current_setting('lab.fixture'))`, e ninguém
fornecia esse valor.

### Como rodar

```bash
cd ferramentas/laboratorio_radar && npm ci --no-audit --no-fund && cd -
node ferramentas/laboratorio_radar/executar.mjs \
  --fixture ferramentas/laboratorio_radar/gerar_fixture.py \
  --sql ferramentas/laboratorio_radar/schema_admissao.sql \
  --sql ferramentas/laboratorio_radar/teste_admissao.sql \
  --harness ferramentas/laboratorio_radar/teste_concorrencia.mjs
```

### Resultado medido em 05/09

```
state            passed
server_version   17.10
network          private_unix_socket_only
elapsed_ms       658 a 677
```

Três execuções seguidas passaram, nenhum processo PostgreSQL sobrou e nenhum
diretório de diagnóstico ficou para trás. As 17 checagens:

**Concorrência real, entre duas conexões `datadrobe_lab_writer`** — a parte que
uma sessão só não alcança, e que a lacuna 8 da blueprint aponta:

1. escrita concorrente serializa na trava consultiva
2. transação abortada não reserva identidade lógica
3. duas transações abortadas deixam o banco intacto
4. escalada por `SET ROLE` negada
5. reexecução concorrente devolve o recibo existente, sem duplicar nada
6. conexão derrubada no meio da transação não deixa linha
7. nenhuma leitura saiu de `draft`

**Suíte SQL** — `restricted_writer`, `privilege_escalation_denied_in_session`,
`anchored_manifest`, `destination_binding`, `cardinality_one`, `idempotency`,
`logical_identity_conflicts`, `source_and_concept_drift`,
`late_failure_atomicity`, `public_drafts_invisible`.

### Dois defeitos encontrados ao executar

Executar um teste que nunca rodou é o que encontra estas coisas.

**1. Uma asserção de segurança que não podia falhar.** O
`teste_admissao.sql` afirmava que o escritor restrito não consegue virar
`service_role` nem `datadrobe_lab_owner`, e testava isso com
`set local role datadrobe_lab_writer` dentro de uma função chamada pelo
administrador. O PostgreSQL decide `SET ROLE` pelo **`session_user`**, não pelo
papel corrente: a sessão era a do superusuário do cluster, e
`set role service_role` respondia **sucesso**.

O sintoma foi teste vermelho, o que é sorte. O perigo é o inverso: bastava
alguém ter escrito a expectativa como "sucesso" e a suíte ficaria verde
afirmando uma proteção que nunca exercitou. O caso mudou para
`teste_concorrencia.mjs`, onde a conexão é do escritor de verdade — e ali a
escalada é negada para os três papéis, inclusive o bootstrap.

**2. Uma falha que não dizia o que quebrou.** `_test_writer_error_v1` levantava
`lab_test_expected_error:permission denied;actual:success`, e essa frase servia
para sete casos diferentes do mesmo arquivo. A mensagem agora carrega o SQL
recusado.

### Por que isto NÃO é "P1 fechado"

A blueprint pede, nos itens 5 a 7 do checklist do P1, que as etiquetas
sintéticas passem **pelo materializador e pelo parser existentes**, que as
submissões sejam consolidadas **pelo código de revisão real**, e que a cadeia
original seja reaberta e comparada. A fixture não faz nada disso: ela monta o
manifesto direto e deriva os hashes de rótulos.

Isso é suficiente para o que ela se propõe — provar persistência, permissões,
concorrência, atomicidade e idempotência —, e é insuficiente para a parte do P1
que liga **uma extração revisada** à **sua admissão no banco**. Essa ligação
continua sem demonstração.

O rótulo honesto, e o que a revisão externa de 05/09 apontou corretamente, é
**"parte transacional do P1 validada"**. Fechar o P1 exige uma segunda fixture,
que nasça do `materializar_etiqueta_radar.py` e passe pelo
`consolidar_revisao_etiqueta_radar.py` antes de chegar ao manifesto.

### O que o P1 prova, e o que não prova

**Prova:** a fundação A51 aceita exatamente uma passagem válida (coleta →
extração → evidência `draft` → leitura `draft` → recibo), rejeita manifesto não
ancorado, destino trocado, contrato de fonte adulterado, conceito alterado,
observação no futuro e conflito de identidade lógica; que a falha tardia desfaz
tudo; que `anon` e `authenticated` não veem rascunho; e que reexecução — inclusive
concorrente — devolve o recibo existente em vez de duplicar evidência.

**Não prova:** a passagem pelo parser e pelo materializador reais, nem a
reconsolidação da revisão — ver a seção acima; que o parser real da Etiqueta
funciona sobre catálogo real; que a
revisão cega dupla foi feita por duas pessoas; que existe alguma fonte externa
admissível; nem equivalência com a versão do PostgreSQL da produção, que este
runner não consulta. Também não prova PostgREST, GoTrue nem Edge Functions.

### Por que isto não está no CI

O laboratório precisa de `npm ci` baixando ~134 MB de binários do PostgreSQL. O
CI do projeto roda no Mac do JP e paga esse download a cada execução limpa.
Ficou fora do portão de push por isso, e a consequência é honesta: **é uma prova
de checkpoint, não uma prova contínua.** Ela precisa ser repetida antes de
fechar o P2, e quem mexer na A51 sem rodá-la não vai ser avisado por nada.

---

## F1 — o gargalo, e ele não começou

O registro executável (`anexos/fontes_radar.csv` + `fontes_de_sinal`) tem
**uma** fonte `green`, e ela é interna: `datadrobe_curadoria_interna`, conteúdo
próprio. Todas as outras estão `yellow` ou `red` aguardando autorização:

| Fonte | Status | Falta |
|---|---|---|
| Google Trends API alpha | `yellow` | concessão de acesso e revisão de escopo |
| Guardian Open Platform Commercial | `yellow` | chave e licença com escopo de IA |
| YouTube Data API (canais curados) | `yellow` | allowlist humana de canais |
| Guardian RSS | `yellow` | RSS público não substitui a licença |
| Pinterest (API e web) | `red` | autorização escrita; scraping proibido |
| YouTube web | `red` | scraping proibido por política |

**Consequência para o plano:** a blueprint marca F1 como "paralelo a P1/P2", e
na prática ela não começou enquanto P1 e P2 consomem o esforço. Se a F1 voltar
"nada admissível", boa parte de P2/P3 terá sido construída para um corpus de um
sensor interno. Esta é a decisão estrutural mais barata de tomar agora e a mais
cara de adiar.

---

## Onde procurar cada coisa

| Arquivo | Para quê |
|---|---|
| `BLUEPRINT_DATADROBE_1_3.md` | a decisão de produto e a ordem dos pacotes |
| `MARKET_INTELLIGENCE_1_3.md` | o contrato do que a versão entrega |
| `GOVERNANCA_FONTES_MARKET_INTELLIGENCE_1_3.md` | direitos, métodos e retenção por fonte |
| `REVISAO_HUMANA_ETIQUETA_1_3.md` | o passo a passo da revisão cega dupla |
| `ferramentas/laboratorio_radar/README_RUNTIME.md` | como o laboratório isola o banco |
| **este arquivo** | o que está de pé, com o comando que prova |
