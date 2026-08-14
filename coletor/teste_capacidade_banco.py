"""Regressões do portão que protege o limite Free do PostgreSQL."""

from verificar_capacidade_banco import avaliar_capacidade


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
    print("Capacidade: ok < 85%, aviso em 85%, bloqueio em 96%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
