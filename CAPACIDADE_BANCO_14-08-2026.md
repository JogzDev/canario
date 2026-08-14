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
