"""Renderiza o relatório único de saúde e aplica o portão operacional."""

import sys
from datetime import date

import supabase_rest
from coletor_varejo import renderizar_saude


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    criticos = renderizar_saude(date.today())
    if criticos:
        print("Portao operacional bloqueado:", file=sys.stderr)
        for alerta in criticos:
            print("- {}".format(alerta), file=sys.stderr)
        return 1
    print("Saude consolidada: nenhuma fonte obrigatoria bloqueada.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
