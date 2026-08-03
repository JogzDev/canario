"""Regressões do portão operacional de saúde."""

import sys
from datetime import date, timedelta

from coletor_varejo import alertas_criticos, metricas_varejo_ativas


HOJE = date(2026, 8, 2)
MARCAS = [{"id": 1, "nome": "Marca A"}]


def linha(fonte, valor, dias=0, marca_id=None):
    return {
        "id": dias + 1,
        "data": (HOJE - timedelta(days=dias)).isoformat(),
        "fonte": fonte,
        "marca_id": marca_id,
        "visitados": valor if fonte == "varejo" else 1,
        "gravados": valor,
        "itens": None if fonte == "varejo" else valor,
        "criado_em": "2026-08-02T10:00:00Z",
    }


def main():
    saudavel = [linha("varejo", 100, marca_id=1),
                linha("editorial", 80), linha("busca", 40)]
    if alertas_criticos(saudavel, MARCAS, HOJE):
        print("FALHOU: fontes saudaveis foram bloqueadas")
        return 1

    sem_busca = [linha("varejo", 100, marca_id=1), linha("editorial", 80)]
    if not any("busca sem observacao" in x
               for x in alertas_criticos(sem_busca, MARCAS, HOJE)):
        print("FALHOU: ausencia de busca nao bloqueou")
        return 1

    queda = [linha("varejo", 20, marca_id=1),
             linha("editorial", 80), linha("busca", 40)]
    queda.extend(linha("varejo", 100, dias=d, marca_id=1)
                 for d in range(1, 8))
    if not any("caiu 80%" in x
               for x in alertas_criticos(queda, MARCAS, HOJE)):
        print("FALHOU: queda maior que 70% nao bloqueou")
        return 1

    metricas = metricas_varejo_ativas(
        {("varejo", 1): linha("varejo", 100, marca_id=1),
         ("varejo", 2): linha("varejo", 0, marca_id=2)},
        {1: ("Marca A", "vtex"), 2: ("Marca inativa", "vtex")}, MARCAS)
    if len(metricas) != 1 or metricas[0]["marca_id"] != 1:
        print("FALHOU: relatorio incluiu observacao de marca fora do escopo ativo")
        return 1

    print("Saude: ausencia, zero e queda >70% bloqueiam; escopo ativo filtra metricas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
