#!/usr/bin/env python3
from filtro_genero_editorial import classificar_genero


def main():
    casos = [
        ("The best men's jackets for fall", "misto", "masculino"),
        ("Women's rugby shirts are everywhere", "misto", "feminino"),
        ("The runway trends defining fall", "misto", "neutro"),
        ("Women's tailoring borrows from menswear", "misto", "neutro"),
        ("The runway trends defining fall", "masculino", "masculino"),
        ("Women's tailoring defines fall", "masculino", "neutro"),
        ("Moda feminina: os vestidos da estação", "misto", "feminino"),
        ("Moda masculina: as camisas da estação", "misto", "masculino"),
    ]
    for titulo, foco, esperado in casos:
        obtido = classificar_genero(titulo, foco)
        assert obtido["publico"] == esperado, (titulo, obtido)
        if esperado == "masculino":
            assert obtido["inclinacao_masculina"] > 0.5, obtido
        else:
            assert obtido["inclinacao_masculina"] <= 0.5, obtido
    print("OK: filtro editorial de gênero")


if __name__ == "__main__":
    main()
