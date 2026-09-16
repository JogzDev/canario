# Canário

Mede o mercado de moda brasileiro e entrega evidência organizada, rastreável e
imediata para quem decide coleção, compra e reposição. **Informa a decisão;
nunca decide, nunca prevê.**

**Como está o projeto hoje:** [`ESTADO.md`](ESTADO.md). É o único documento de
estado — se outro arquivo discordar dele, o outro está velho.

Evolução pós-Challenge: [`ROADMAP_PRODUTO.md`](ROADMAP_PRODUTO.md) organiza as
entregas por dificuldade, urgência, dependência e critério de aceite.
Recuperação operacional: [`RUNBOOK_CAPACIDADE.md`](RUNBOOK_CAPACIDADE.md).

A especificação completa está em [`CANARIO.md`](CANARIO.md) e é a fonte da
verdade do projeto. As regras invioláveis da seção 1 vencem qualquer outra
instrução. Antes de mexer em qualquer coisa aqui, leia pelo menos a Parte 0.

## Como funciona

**Servidor calcula séries; app consulta, analisa peças e mantém um Closet privado.**

```
GitHub Actions (cron)  →  coletores Python  →  Supabase (Postgres)  →  app SwiftUI
```

O app nunca coleta nem computa índice: ele lê séries prontas. Originais da câmera
permanecem locais. A análise remota envia uma imagem reduzida à Edge Function e
à Luna; com conta, miniaturas e dados do Closet sincronizam sob RLS. Sem conta,
o Closet permanece local. Não confundir análise remota com armazenamento do
original, nem prometer que nenhuma imagem sai do aparelho.

## Estrutura

| Pasta | O que é |
|---|---|
| `anexos/` | Taxonomia, painel de marcas e veículos editoriais. Contratos do sistema, versionados. |
| `coletor/` | Coletores em Python. Varejo, editorial e busca. |
| `app/` | App iOS em SwiftUI. |
| `.github/workflows/` | Agendamento dos coletores. Cron sempre em UTC. |
| `supabase/` | Migrations e Edge Functions; produção não é ambiente de laboratório. |
| `ferramentas/laboratorio_radar/` | PostgreSQL descartável, sem acesso à produção. |

## Documentos de processo

- [`historico/AUDITORIA_INICIAL.md`](historico/AUDITORIA_INICIAL.md) — auditoria histórica da tarefa zero; não comprova aceite atual da F1 do radar.
- `SAUDE.md` — relatório gerado pelos coletores e preservado nos artefatos do Actions; conferir a data, não presumir atualização do arquivo versionado.
- `DADOS_FICTICIOS.md` — todo dado fictício usado em desenvolvimento. Checagem obrigatória antes de qualquer apresentação.

## Rodando os coletores localmente

```bash
python3 coletor/teste_30s.py
```

Os coletores rodam em Python 3.11 no GitHub Actions. O código evita sintaxe de
3.10+ para continuar executável no Python 3.9 que vem com o macOS, de modo que
dá para testar localmente sem instalar nada.

Os runners macOS self-hosted são legado em retirada, não parte da arquitetura
alvo. A preservação do i7, a substituição gerenciada dos coletores e a migração
do CI Apple estão em
[`TRANSICAO_INFRAESTRUTURA.md`](TRANSICAO_INFRAESTRUTURA.md).

## Configuração do app

O app lê o Supabase com a chave **publishable**, que é pública por design e vai
embutida no binário. A segurança do banco depende inteiramente das políticas
RLS, nunca do sigilo da chave.

Copie `Config.xcconfig.example`, na raiz, para `Config.xcconfig` e preencha o
arquivo local ignorado pelo Git. Não inclua chaves de serviço ou de IA no binário; credenciais privilegiadas
pertencem somente aos serviços e ambientes de execução autorizados.

## Laboratório local do Radar

Com Node 24 e Python 3.9+, sem credenciais remotas:

```sh
cd ferramentas/laboratorio_radar
npm ci --no-audit --no-fund
npm test
```

O teste usa PostgreSQL real descartável e dados sintéticos. Instruções e limites
da prova em [`README_RUNTIME.md`](ferramentas/laboratorio_radar/README_RUNTIME.md).

## Etiqueta de coleta (regra inviolável 7)

Máximo 1 requisição por segundo globalmente no fluxo de coleta, agendamento de
madrugada (horário de Brasília; início efetivo pode atrasar no Actions), cache
agressivo, só páginas públicas, `robots.txt` respeitado e
User-Agent identificável:

```
CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)
```

Nunca burlar autenticação ou proteção anti-bot. Marca que responde 403 fica de
fora do painel — não se procura outro caminho.
