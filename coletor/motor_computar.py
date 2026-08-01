"""Motor, passos 2 e 3: dispara o calculo que vive no Postgres.

O calculo pesado fica no banco de proposito (§33: "servidor calcula, app
consulta"). Trazer 65 mil produtos e 190 mil ligacoes pela rede para somar em
Python seria lento e fragil; a agregacao e window function, que e o que o
Postgres faz melhor.

Este script so orquestra: chama as funcoes na ordem certa e relata.
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
    ("computar_z",
     "z-score em janela movel de 12 semanas (§21)"),
    ("computar_indice",
     "indice e estado por termo/semana (§22)"),
    ("computar_curva_tamanhos",
     "onde a grade quebra, por posicao na grade (§24, marco de demo 1)"),
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
# O que repetir faz e desperdicar, e mascarar o tempo real de cada passo.
ESPERA_DO_LOTE = 600
TENTATIVAS_DO_LOTE = 1


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    for funcao, descricao in PASSOS:
        inicio = time.monotonic()
        _, resultado = supabase_rest._requisicao(
            "POST", "rpc/" + funcao, corpo={},
            tentativas=TENTATIVAS_DO_LOTE, timeout=ESPERA_DO_LOTE)
        # O tempo de cada passo vai para o log: e o que teria mostrado, sem
        # precisar de investigacao, que a curva de tamanhos era a lenta.
        print("  {:26} -> {:>6} linhas em {:5.1f}s   ({})".format(
            funcao, resultado, time.monotonic() - inicio, descricao),
            file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
