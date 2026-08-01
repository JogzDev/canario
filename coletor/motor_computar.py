"""Motor, passos 2 e 3: dispara o calculo que vive no Postgres.

O calculo pesado fica no banco de proposito (§33: "servidor calcula, app
consulta"). Trazer 65 mil produtos e 190 mil ligacoes pela rede para somar em
Python seria lento e fragil; a agregacao e window function, que e o que o
Postgres faz melhor.

Este script so orquestra: chama as funcoes na ordem certa e relata.
"""

import os
import sys

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
]


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    for funcao, descricao in PASSOS:
        _, resultado = supabase_rest._requisicao("POST", "rpc/" + funcao, corpo={})
        print("  {:26} -> {} linhas   ({})".format(funcao, resultado, descricao),
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
