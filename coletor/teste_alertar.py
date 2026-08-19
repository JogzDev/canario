#!/usr/bin/env python3
"""O alerta do pipeline não pode virar ruído — regressões da decisão."""

import os
import sys

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ferramentas"))

from alertar import corpo_da_falha, decidir  # noqa: E402


def main():
    # Primeira noite ruim: abre.
    if decidir("vermelho", None) != "abrir":
        print("FALHOU: falha sem incidente aberto nao abriu alerta")
        return 1

    # Segunda, terceira, quarta noite: COMENTA na mesma issue. Cinco noites
    # vermelhas geram uma issue com cinco comentarios, nao cinco issues --
    # alarme que dispara todo dia deixa de ser lido em uma semana.
    if decidir("vermelho", {"number": 7}) != "comentar":
        print("FALHOU: segunda falha abriria issue nova e viraria ruido")
        return 1

    # Voltou o verde com incidente aberto: fecha. E isto que faz "issue aberta"
    # significar "esta quebrado agora"; sem fechar, vira lixo.
    if decidir("verde", {"number": 7}) != "fechar":
        print("FALHOU: verde nao fechou o incidente e a issue vira lixo")
        return 1

    # Dia bom sem incidente aberto: silencio absoluto.
    if decidir("verde", None) != "nada":
        print("FALHOU: dia bom gerou notificacao")
        return 1

    # Estado que nao e nem um nem outro e erro, nao "provavelmente verde":
    # tratar desconhecido como saudavel e como os quatro dias passaram.
    for ruim in ("", "amarelo", "success", None):
        try:
            decidir(ruim, None)
        except ValueError:
            continue
        except TypeError:
            continue
        print("FALHOU: estado {!r} passou como valido".format(ruim))
        return 1

    corpo = corpo_da_falha("https://exemplo/run/1", "Pipeline diario", "motor")
    for esperado in ("Pipeline diario", "motor", "SAUDE.md",
                     "fecha sozinha", "verificar_capacidade_banco"):
        if esperado not in corpo:
            print("FALHOU: corpo do alerta sem {!r}".format(esperado))
            return 1

    print("Alerta do pipeline: abre, agrupa, fecha sozinho e cala em dia bom")
    return 0


if __name__ == "__main__":
    sys.exit(main())
