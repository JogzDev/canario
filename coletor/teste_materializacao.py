"""Regressoes sobre a fronteira entre configuracao e estado medido.

O CSV governa a taxonomia aprovada. O coletor de Trends governa o resultado
das verificacoes de busca. Misturar os dois donos fez verificacoes reais
voltarem para `pendente` a cada materializacao diaria.
"""

import sys

from materializar_anexos import registro_do_termo


def main():
    linha = {
        "id": "preto",
        "rotulo": "Preto",
        "dimensao": "cor",
        "exclusiva": "sim",
        "status": "aprovado",
        "sem_perna_busca": "pendente",
        "volume_verificado_em": "2026-08-01",
        "volume_detalhe": "medido",
    }
    registro = registro_do_termo(linha)

    esperados_ausentes = {
        "sem_perna_busca", "volume_verificado_em", "volume_detalhe"
    }
    presentes = esperados_ausentes.intersection(registro)
    if presentes:
        print("FALHOU: materializador tentou possuir estado medido: {}".format(
            ", ".join(sorted(presentes))))
        return 1
    if registro["id"] != "preto" or registro["exclusiva"] is not True:
        print("FALHOU: campos de configuracao deixaram de ser materializados")
        return 1

    print("Materializacao: configuracao preservada, estado medido intocado")
    return 0


if __name__ == "__main__":
    sys.exit(main())
