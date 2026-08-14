# Capacidade do banco — medição de 14/08/2026

## Veredito

O alerta era real. O projeto Free entra em modo somente leitura ao cruzar
500.000.000 bytes de dados PostgreSQL. O painel mostrava 100% e a consulta
direta mediu **482.864.275 bytes** antes da intervenção.

Não era o disco físico de 2 GB cheio. Era a cota lógica do plano Free, que
conta dados, índices e materializações.

## O que foi feito sem apagar história

As tabelas `motor_termos_stage` e `motor_produtos_stage` estavam com zero linha,
nenhuma execução do motor estava `queued` ou `running`, mas seus índices ainda
ocupavam 16,8 MB. A RPC existente `preparar_stage_motor()` confirmou a guarda e
truncou somente esse estágio reconstruível.

| Medida | Antes | Depois |
|---|---:|---:|
| Banco | 482.864.275 bytes | **466.078.867 bytes** |
| Exibição PostgreSQL | 460 MiB | **444 MiB** |
| Estágio do motor | 16,8 MB | **96 kB** |
| Margem até 500 MB | 17,1 MB | **33,9 MB** |

O painel do Supabase pode levar até uma hora para refletir a redução.

## Maiores objetos medidos

| Objeto | Total aproximado | Papel |
|---|---:|---|
| `produtos` | 194 MB | catálogo e estado atual |
| `artigos` | 61 MB | evidência editorial deduplicada |
| `series_semanais` | 55 MB | séries do motor |
| `produto_termos` | 52 MB | ligações taxonômicas |
| `snapshots` | 43 MB | deltas de varejo |

Essas cinco estruturas sustentam o produto. Nenhuma foi apagada para “fazer o
verde aparecer”. Retenção só entra depois de medir crescimento e provar que a
janela removida já está materializada e não é necessária para reprocessamento.

## Proteção adicionada

- `uso_do_banco()` expõe apenas o total agregado ao `service_role`.
- Toda coleta mede a capacidade antes de escrever.
- A partir de 85% o Actions mostra aviso.
- A partir de 96% a coleta bloqueia antes de criar dados novos.
- O app e as chaves públicas não recebem acesso a essa função.

## Próxima decisão de capacidade

O alívio atual é operacional, não definitivo. Antes de atingir novamente 96%,
há duas rotas honestas:

1. desenhar retenção por tabela, com contagens e impacto metodológico; ou
2. migrar para o plano Pro para obter margem sem empobrecer o histórico.

Não usar `VACUUM FULL`, apagar artigos ou reduzir séries durante o pipeline:
essas ações exigem janela de manutenção e uma decisão de método registrada.

## Compactação de 14/08/2026, à noite — decisão de método registrada

A cota do plano não estava sendo consumida por história: estava sendo consumida
por espaço morto. Medido linha a linha, com `pg_column_size` sobre a linha
inteira contra `pg_relation_size`:

| Tabela | Dados vivos | Heap ocupado | Morto |
|---|---:|---:|---:|
| `produtos` | 84,7 MiB | 178,2 MiB | 93,5 MiB |
| `series_semanais` | 16,8 MiB | 48,9 MiB | 32,1 MiB |
| `artigos` | 24,8 MiB | 34,9 MiB | 10,1 MiB |
| `snapshots` | 30,8 MiB | 32,2 MiB | saudável |

`VACUUM FULL (analyze)` foi aplicado em `artigos`, `series_semanais`,
`produto_termos`, `indices_semanais` e `produtos`, nessa ordem — da menor para a
maior, porque a operação escreve uma cópia nova antes de liberar a antiga e o
pico de cada passo precisava caber na cota.

| Medida | Antes | Depois |
|---|---:|---:|
| Banco | 448,8 MiB | **266,7 MiB** |
| Em bytes decimais | ~470,6 MB | **~279,6 MB** |
| Percentual do plano de 500 MB | ~94% | **~56%** |
| `produtos` (total) | 194,3 MiB | **98,1 MiB** |

Nenhum registro foi apagado. As contagens antes e depois batem exatamente:
snapshots 233.315, produto_termos 206.598, artigos 120.191, produtos 82.332,
series_semanais 25.554, eventos 18.271, indices_semanais 9.257.

Por que a janela era segura: o pipeline diário estava parado pelo bloqueio de
cobrança do GitHub Actions, nenhuma execução do motor estava pendente e o
estágio reconstruível continuava vazio. Fora dessa condição, a regra acima
continua valendo — `VACUUM FULL` toma lock exclusivo e não deve rodar com
coleta ou motor em curso.

O alívio agora é estrutural, não cosmético, mas também não é infinito: o espaço
morto volta a crescer com `UPDATE`. Vale reavaliar `autovacuum_vacuum_scale_factor`
em `produtos` antes de discutir retenção ou plano Pro.
