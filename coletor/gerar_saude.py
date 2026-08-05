"""Renderiza o relatório único de saúde e aplica o portão operacional."""

import sys
from datetime import datetime
from zoneinfo import ZoneInfo

import supabase_rest
from coletor_varejo import renderizar_saude

FUSO_OPERACIONAL = ZoneInfo("America/Sao_Paulo")


def data_operacional(agora=None):
    """Data de negocio, independente do fuso do runner que aplica o portao."""
    agora = agora or datetime.now(FUSO_OPERACIONAL)
    return agora.astimezone(FUSO_OPERACIONAL).date()


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    criticos = renderizar_saude(data_operacional())
    if criticos:
        print("Portao operacional bloqueado:", file=sys.stderr)
        for alerta in criticos:
            print("- {}".format(alerta), file=sys.stderr)
        return 1
    print("Saude consolidada: nenhuma fonte obrigatoria bloqueada.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
