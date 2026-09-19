"""Motor, passos 2 e 3: publica o calculo transacional do Postgres.

O calculo pesado fica no banco de proposito (§33: "servidor calcula, app
consulta"). Trazer 65 mil produtos e 190 mil ligacoes pela rede para somar em
Python seria lento e fragil; a agregacao e window function, que e o que o
Postgres faz melhor.

Este script chama uma unica RPC. A ordem continua definida no banco, mas todas
as escritas pertencem a mesma transacao: falha tardia preserva a leitura antiga.
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import supabase_rest  # noqa: E402

PASSOS = [
    # Eventos primeiro, e de proposito: dependem so de `snapshots` e `saude`,
    # entao um erro no calculo de indice nao pode impedir que a §23 do dia seja
    # registrada.
    #
    # Este passo FALTAVA. A funcao foi criada no banco em 30/07 e nunca entrou
    # aqui: a tabela `eventos` congelou naquele dia enquanto as coletas seguiam
    # gravando snapshot todo dia, e a tela mostrava "Remarcacoes da semana" com
    # o dado de anteontem. Ao ser ligada, a primeira chamada gerou 894 eventos
    # atrasados de uma vez -- todos reais, nenhum novo.
    ("computar_eventos",
     "reposicao, remarcacao e saida de linha (§23, K1, K4)"),
    ("computar_serie_varejo",
     "serie semanal de varejo (share do sortimento, §15/§21)"),
    # ANTES do z, e nao depois: ela materializa os zeros e normaliza o
    # editorial. Rodar na ordem errada faria o z ler a serie crua e produzir o
    # mesmo vies que existia ate 02/08 -- editorial_br com z medio negativo em
    # 13 de 13 semanas, e `em alta` impossivel.
    ("computar_serie_editorial",
     "zeros materializados + share of voice de verdade (§18/§21)"),
    ("computar_z",
     "z-score em janela movel de 12 semanas (§21)"),
    ("computar_indice",
     "indice e estado por termo/semana (§22)"),
    ("computar_curva_tamanhos",
     "onde a grade quebra, por posicao na grade (§24, marco de demo 1)"),
    # Raridade DEPOIS dos atributos e ANTES de qualquer leitura de cluster: ela
    # conta `produto_termos`, entao so faz sentido depois que o dia de coleta ja
    # entrou. E precisa estar no motor, nao so no banco -- foi exatamente esse o
    # erro do `computar_eventos` em 30/07: funcao criada nao e funcao chamada.
    ("computar_raridade",
     "peso de raridade por (categoria, termo) para o indice do cluster (§22, K5)"),
    # ULTIMO, e logo antes da poda: reconstroi dos snapshots o sortimento
    # ofertavel do dia, que e o denominador das comparacoes entre marcas
    # (DAT-04). `podar_snapshots(21)` roda em seguida, na mesma transacao --
    # dia podado e dia irreconstruivel, entao a ordem nao e preferencia.
    ("computar_sortimento_diario",
     "sortimento ofertavel por marca no dia observado (denominador, DAT-04)"),
]


# Espera longa e UMA tentativa so.
#
# Medido em 01/08/2026: `computar_curva_tamanhos()` leva 61 segundos, e o
# cliente desistia aos 30. Pior que a falha era o retry: a cada tentativa o
# Postgres refazia o trabalho inteiro, entao uma execucao que ja era longa
# virava tres. Funcao de lote nao se repete por impaciencia do cliente -- ou
# ela termina, ou o problema e outro e repetir nao resolve.
#
# As funcoes sao idempotentes (upsert na chave), entao repetir nao corrompe.
# Agora elas tambem sao atomicas, mas um retry ainda pode refazer minutos de
# trabalho depois de uma resposta perdida. A confirmacao deve ser explicita.
ESPERA_DO_LOTE = 900
TENTATIVAS_DO_LOTE = 1


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    inicio = time.monotonic()
    _, resultados = supabase_rest._requisicao(
        "POST", "rpc/computar_motor", corpo={},
        tentativas=TENTATIVAS_DO_LOTE, timeout=ESPERA_DO_LOTE)
    duracao = time.monotonic() - inicio
    for funcao, descricao in PASSOS:
        print("  {:26} -> {:>6} linhas   ({})".format(
            funcao, (resultados or {}).get(funcao, "?"), descricao),
            file=sys.stderr)
    print("Motor publicado atomicamente em {:.1f}s.".format(duracao),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
