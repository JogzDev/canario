"""Regressões do portão que protege o limite Free do PostgreSQL."""

from verificar_capacidade_banco import (OVERHEAD_MINIMO_MEDIDO,
                                        avaliar_capacidade, ler_uso)


def main():
    casos = [
        (424_999_999, "ok"),
        (425_000_000, "aviso"),
        (479_999_999, "aviso"),
        (480_000_000, "critico"),
    ]
    for usados, esperado in casos:
        estado, fracao, livres = avaliar_capacidade(usados)
        if estado != esperado:
            print("FALHOU: {} bytes virou {}, esperado {}".format(
                usados, estado, esperado))
            return 1
        if fracao != usados / 500_000_000:
            print("FALHOU: fracao incorreta para {}".format(usados))
            return 1
        if livres != 500_000_000 - usados:
            print("FALHOU: margem incorreta para {}".format(usados))
            return 1

    for usados in (-1, "500"):
        try:
            avaliar_capacidade(usados)
        except ValueError:
            pass
        else:
            print("FALHOU: tamanho invalido foi aceito: {}".format(usados))
            return 1

    # P21: a medicao real de 18/09/2026. O portao antigo via 97,2% e o total
    # que a cota enxerga ja passava de 100%.
    medido = {"bytes": 501_226_293, "bytes_da_cota": 501_226_293,
              "banco_principal_bytes": 485_952_659,
              "overhead_interno_bytes": 15_273_634}
    cota, principal, overhead, estimado = ler_uso(medido)
    if (cota, principal, overhead, estimado) != (
            501_226_293, 485_952_659, 15_273_634, False):
        print("FALHOU: leitura da P21 incorreta: {}".format(
            (cota, principal, overhead, estimado)))
        return 1
    if avaliar_capacidade(cota)[0] != "critico":
        print("FALHOU: 100,25% da cota precisa ser critico")
        return 1

    # A decisao e pelo total: um banco principal que sozinho passaria no
    # portao pode reprovar quando o overhead entra na conta.
    abaixo = {"bytes_da_cota": 480_100_000, "banco_principal_bytes": 464_900_000,
              "overhead_interno_bytes": 15_200_000}
    if avaliar_capacidade(464_900_000)[0] != "aviso":
        print("FALHOU: o caso de controle deveria passar olhando so o principal")
        return 1
    if avaliar_capacidade(ler_uso(abaixo)[0])[0] != "critico":
        print("FALHOU: o overhead nao entrou na decisao")
        return 1

    # Banco sem a P21: o overhead vem do piso medido, e a leitura diz que e
    # estimativa. Nunca fica MENOS conservador que o total medido em 18/09.
    antigo = {"bytes": 485_952_659, "limite_bytes": 500_000_000}
    cota, principal, overhead, estimado = ler_uso(antigo)
    if not estimado or overhead != OVERHEAD_MINIMO_MEDIDO \
            or cota != 485_952_659 + OVERHEAD_MINIMO_MEDIDO:
        print("FALHOU: o fallback sem P21 precisa somar o piso e se declarar")
        return 1

    # Numero que nao fecha e erro, nao arredondamento.
    try:
        ler_uso({"bytes_da_cota": 10, "banco_principal_bytes": 4,
                 "overhead_interno_bytes": 5})
    except ValueError:
        pass
    else:
        print("FALHOU: cota que nao fecha foi aceita")
        return 1

    print("Capacidade: ok < 85%, aviso em 85%, bloqueio em 96%, decidido pela "
          "cota inteira (principal + overhead)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
