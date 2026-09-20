# Runner residencial durável

Este pacote substitui o supervisor temporário da observação depois de 26/09.
Ele não hospeda um runner permanentemente: às 02h50 BRT o `launchd` cria uma
credencial efêmera, espera o pipeline agendado pelo GitHub, acompanha a run
exata, mede capacidade e remove credencial e diretório de trabalho ao terminar.

## O que ele faz

- nunca dispara o pipeline diário nem o catálogo candidato;
- aceita apenas runs de evento `schedule` e caminhos conhecidos;
- mantém o Mac acordado durante a janela;
- depois do pipeline, dispara somente a verificação de produção read-only;
- nas segundas e quintas, espera também o catálogo candidato agendado;
- acima de 85%, falha de pipeline ou medida inconclusiva, desativa as duas
  agendas e abre/atualiza uma issue de incidente;
- verifica o SHA-256 do GitHub Actions Runner antes de extrair;
- recupera lock e registro remoto órfãos somente quando não existe processo
  local correspondente, sem apagar uma janela ainda ativa;
- não grava senha de banco nem token de registro em disco.

O job `publicacao` do próprio pipeline é a prova diária do painel. Este runner
não repete a sonda manual das três RPCs: a busca editorial não carrega o marco
diário e um timeout transitório dela não pode interromper as coletas.

## Limites físicos

`caffeinate` impede suspensão ociosa, mas não fornece energia e não mantém um
MacBook operante se ele for desligado. O computador precisa permanecer ligado,
conectado à tomada e com rede. Fechar a tampa pode suspender o Mac dependendo
da configuração e dos periféricos.

## Troca depois da observação

Não instalar enquanto `br.com.canario.observacao-runner` estiver ativo. O
instalador recusa essa sobreposição. Depois de encerrar e remover o temporário:

```bash
bash ferramentas/runner_residencial/instalar.sh
```

O `--check` final valida ferramentas, autenticação e pacote assinado, sem
registrar runner e sem disparar workflow. Para remover:

```bash
bash ferramentas/runner_residencial/desinstalar.sh
```

A remoção não reativa nem desativa workflows; esse estado fica explícito no
GitHub e precisa ser tratado conforme o incidente que motivou a remoção.
