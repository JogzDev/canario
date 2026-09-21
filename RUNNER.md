# Runner residencial — o Mac i7 como servidor de coleta

> **Documento histórico, não instalar.** Em 21/09/2026 o caminho regular foi
> movido para executores gerenciados pela PR #36. O supervisor temporário só
> permanece até o primeiro ciclo hospedado publicar e medir capacidade; depois
> será desligado. O estado vigente está em `ESTADO.md`.

**Resposta curta: dá, e resolve o problema sem gastar um centavo.**

O coletor não é pesado de processador: ele passa quase todo o tempo *esperando*
a resposta do site, no ritmo de 1 requisição por segundo que a regra 7 exige. Um
i7, mesmo antigo, fica ocioso durante a coleta inteira. O que importa nessa
máquina não é a CPU — é o **endereço de IP residencial**, que é justamente o que
a VTEX aceita e o datacenter do GitHub não.

O que ele resolve:

| Problema | Estado hoje | Com o Mac |
|---|---|---|
| 12 marcas VTEX em 429 | Bloqueadas | Devem voltar a responder |
| Amaro em 429 | Perdido na v1 | Volta a ser possível |
| Regra 13 (nada pago) | Ameaçada | Intacta |

E não é gambiarra: é o modo que o próprio GitHub documenta para rodar Actions em
máquina própria. O workflow já está preparado — ele lê a variável
`RUNNER_COLETA` e usa o Mac quando ela existir, ou o datacenter quando não.

---

## Medido em 26/08/2026: a premissa do IP residencial não vale mais

O texto acima diz que o valor da máquina é o **endereço residencial**. Medindo:

* o i7 é `10.46.53.103` e o Mac do JP é `10.46.83.76` — mesma rede privada
  `10.46.x.x`, ou seja, **os dois runners estão atrás da mesma infraestrutura**;
* a saída pública dessa rede é `139.82.91.130`, um endereço institucional fixo,
  **não residencial**.

Consequência prática: trocar a coleta de um runner para o outro **não muda o IP
de saída**, e portanto não é remédio para recusa de origem. O quadro de
comparação acima descreve uma situação que não é mais a atual.

O que continua verdadeiro: as 13 marcas VTEX coletam bem dessa rede.

### O que isso NÃO explica

Em 25 e 26/08 Amaro e PatBô voltaram zero do i7 (`429` persistente e `500`),
enquanto as 13 VTEX coletavam normalmente na mesma execução. Testado da mesma
rede, no mesmo dia, com o User-Agent do CanarioBot e o ritmo de 1 req/s:

```
robots.txt          200   (amaro.com e www.patbo.com.br)
products.json       200   com produto real nas duas
10 páginas seguidas 200   em todas, sem 429
```

Ou seja: **não era o IP e não era o ritmo.**

### E também não era a máquina

O experimento rodou às 13:37 de 26/08, no i7, com o mesmo workflow que falhara
duas vezes: **Amaro 256 visitados em 10 s e PatBô 7.470 em 134 s, sem erro** —
volumes normais. Portanto a máquina está sã, e as três hipóteses caíram:

| Hipótese | Como caiu |
|---|---|
| IP do runner recusado | a mesma rede responde 200 nos dois domínios |
| limite de ritmo/volume | 10 páginas seguidas a 1 req/s, todas 200 |
| máquina degradada | a mesma máquina coletou tudo, sem erro |

O que restou é **recusa transitória do lado da Shopify**, atravessando as
janelas de 25 e 26/08. Não há conserto a fazer: o remédio, se repetir, é uma
execução manual de `coleta-shopify.yml`, que grava o dado do próprio dia e zera
o contador de dias seguidos antes de ele chegar em três.

O que travou a fila naquela tarde foi outra coisa, sem relação: o grupo de
concorrência `canario-dados`, preso por um run que o GitHub listava como
`queued` e recusava cancelar. Destravou sozinho.

## Passo a passo

### 1. Registrar o runner (no Mac, ~5 minutos)

No navegador do Mac: **repositório → Settings → Actions → Runners → New
self-hosted runner → macOS**.

O GitHub mostra uma sequência de comandos já com um token embutido. **Rode os
comandos que ele mostrar**, na ordem. Não me mande esse token nem cole ele aqui:
ele é de uso único, tem validade curta e é seu.

Ao chegar nas perguntas do `./config.sh`:

- *runner group* → Enter (default)
- *name of runner* → Enter, ou `mac-canario`
- *additional labels* → Enter
- *work folder* → Enter

### 2. Deixar rodando como serviço

Ainda no `Terminal`, dentro da pasta `actions-runner`:

```bash
./svc.sh install && ./svc.sh start
```

Isso faz o runner subir sozinho quando o Mac liga. Sem isso, você teria que
abrir o terminal e rodar `./run.sh` toda vez.

### 3. Apontar o workflow para o Mac

No GitHub: **Settings → Secrets and variables → Actions → aba Variables → New
repository variable**.

- Nome: `RUNNER_COLETA`
- Valor: `self-hosted`

Pronto. A partir daí toda coleta roda no Mac. Para voltar ao datacenter, apague
a variável.

### 4. Garantir que o Mac esteja acordado às 03:00

O cron dispara 03:00 BRT. Se o Mac estiver dormindo, o job fica na fila e só roda
quando alguém acorda a máquina — coleta fora de hora, e a regra 7 pede madrugada.

Este comando pede sua senha, então **rode você** (eu não executo comando com
`sudo`):

```bash
sudo pmset repeat wakeorpoweron MTWRFSU 02:45:00
```

Ele acorda o Mac às 02:45 todos os dias, 15 minutos antes da coleta. Confira com
`pmset -g sched`. Em **Ajustes → Bateria/Economizador**, vale também marcar para
não dormir com a tela desligada.

---

## Duas coisas que você precisa saber antes

**Segurança:** runner self-hosted em repositório **público** é perigoso — qualquer
pessoa abre um PR e roda código na sua máquina. O `JogzDev/canario` é **privado**,
então isso não se aplica. Se um dia o repositório virar público, **desligue o
runner antes**.

**O segredo do Supabase passa pela máquina.** Durante a coleta, a
`SUPABASE_SECRET_KEY` fica na memória do processo no Mac. É sua máquina e seu
segredo, então não há vazamento para terceiro — mas é a razão de o Mac precisar
ser uma máquina em que você confia, não uma emprestada.

---

## Se der problema

**O job fica "Queued" para sempre** → o runner não está de pé. No Mac:
`cd actions-runner && ./svc.sh status`.

**`setup-python` falha** → não é bloqueador. O código dos coletores foi escrito
para rodar também no Python 3.9 que vem com o macOS, exatamente para não depender
de instalar nada nessa máquina. O passo está marcado como `continue-on-error` e a
coleta segue com o `python3` do sistema.

**A VTEX continua em 429 mesmo no Mac** → aí o problema não era o datacenter, e
o disjuntor vai parar a coleta em vez de insistir. Me avise: a próxima hipótese
seria janela de penalidade mais longa, e a resposta continua sendo esperar, não
forçar.
