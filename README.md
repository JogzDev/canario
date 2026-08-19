# Canário

Mede o mercado de moda brasileiro e entrega evidência organizada, rastreável e
imediata para quem decide coleção, compra e reposição. **Informa a decisão;
nunca decide, nunca prevê.**

**Como está o projeto hoje:** [`ESTADO.md`](ESTADO.md). É o único documento de
estado — se outro arquivo discordar dele, o outro está velho.

A especificação completa está em [`CANARIO.md`](CANARIO.md) e é a fonte da
verdade do projeto. As regras invioláveis da seção 1 vencem qualquer outra
instrução. Antes de mexer em qualquer coisa aqui, leia pelo menos a Parte 0.

## Como funciona

**Servidor calcula, app consulta, câmera fica local.**

```
GitHub Actions (cron)  →  coletores Python  →  Supabase (Postgres)  →  app SwiftUI
```

O app nunca coleta nem computa índice: ele lê séries prontas.

## Estrutura

| Pasta | O que é |
|---|---|
| `anexos/` | Taxonomia, painel de marcas e veículos editoriais. Contratos do sistema, versionados. |
| `coletor/` | Coletores em Python. Varejo, editorial e busca. |
| `app/` | App iOS em SwiftUI. |
| `.github/workflows/` | Agendamento dos coletores. Cron sempre em UTC. |

## Documentos de processo

- [`AUDITORIA_INICIAL.md`](AUDITORIA_INICIAL.md) — auditoria da tarefa zero e as respostas que destravaram a F1.
- `SAUDE.md` — relatório de saúde diário dos coletores. É o alarme do sistema: coletor não quebra com erro na tela, quebra em silêncio.
- `DADOS_FICTICIOS.md` — todo dado fictício usado em desenvolvimento. Checagem obrigatória antes de qualquer apresentação.

## Rodando os coletores localmente

```bash
python3 coletor/teste_30s.py
```

Os coletores rodam em Python 3.11 no GitHub Actions. O código evita sintaxe de
3.10+ para continuar executável no Python 3.9 que vem com o macOS, de modo que
dá para testar localmente sem instalar nada.

## Configuração do app

O app lê o Supabase com a chave **publishable**, que é pública por design e vai
embutida no binário. A segurança do banco depende inteiramente das políticas
RLS, nunca do sigilo da chave.

Copie `Config.xcconfig.example` para `Config.xcconfig` e preencha com os valores
que o JP fornece localmente. O arquivo real está no `.gitignore` e nunca é
commitado.

## Etiqueta de coleta (regra inviolável 7)

Máximo 1 requisição por segundo por domínio, coleta de madrugada (horário de
Brasília), cache agressivo, só páginas públicas, `robots.txt` respeitado e
User-Agent identificável:

```
CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)
```

Nunca burlar autenticação ou proteção anti-bot. Marca que responde 403 fica de
fora do painel — não se procura outro caminho.
