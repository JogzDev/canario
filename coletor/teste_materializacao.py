"""Regressoes sobre a fronteira entre configuracao e estado medido.

O CSV governa a taxonomia aprovada. O coletor de Trends governa o resultado
das verificacoes de busca. Misturar os dois donos fez verificacoes reais
voltarem para `pendente` a cada materializacao diaria.
"""

import csv
import sys

from materializar_anexos import PAINEL, registro_da_marca, registro_do_termo


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

    fabula = next((l for l in csv.DictReader(open(PAINEL, encoding="utf-8"))
                   if l["marca"] == "Fabula"), None)
    if fabula is None:
        print("FALHOU: Fábula sumiu do painel competitivo")
        return 1
    marca = registro_da_marca(fabula)
    if (marca["status_teste"] != "nao_se_aplica" or marca["plataforma"] is not None
            or marca["ativa"]):
        print("FALHOU: Fábula infantil continuou ativa na coleta adulta")
        return 1

    coletavel = registro_da_marca({"marca": "Marca VTEX", "status_teste": "vtex"})
    if coletavel["plataforma"] != "vtex" or not coletavel["ativa"]:
        print("FALHOU: marca VTEX comprovada deixou de ser coletavel")
        return 1

    print("Materializacao: configuracao preservada, escopo adulto ativo e estado medido intocado")
    return 0


if __name__ == "__main__":
    sys.exit(main())
