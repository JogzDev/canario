"""Impede que uma coleta empurre o projeto Free para read-only.

O limite é o do plano, em bytes decimais. A faixa de aviso dá visibilidade no
Actions; a faixa crítica preserva 4% para operação/índices e bloqueia novas
escritas até haver limpeza medida ou mudança consciente de plano.
"""

import sys

import supabase_rest


LIMITE_FREE = 500_000_000
AVISO = 0.85
CRITICO = 0.96


def avaliar_capacidade(bytes_usados, limite=LIMITE_FREE):
    if not isinstance(bytes_usados, int) or bytes_usados < 0:
        raise ValueError("tamanho do banco invalido")
    if not isinstance(limite, int) or limite <= 0:
        raise ValueError("limite do banco invalido")
    fracao = bytes_usados / limite
    if fracao >= CRITICO:
        estado = "critico"
    elif fracao >= AVISO:
        estado = "aviso"
    else:
        estado = "ok"
    return estado, fracao, limite - bytes_usados


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    try:
        leitura = supabase_rest.rpc("uso_do_banco") or {}
        usados = int(leitura["bytes"])
        limite = int(leitura.get("limite_bytes") or LIMITE_FREE)
        estado, fracao, livres = avaliar_capacidade(usados, limite)
    except (KeyError, TypeError, ValueError, supabase_rest.SupabaseErro) as erro:
        print("ERRO: nao foi possivel medir a capacidade: {}".format(erro),
              file=sys.stderr)
        return 1

    mensagem = ("Banco: {:.1f}% ({:,} de {:,} bytes; {:,} livres).".format(
        fracao * 100, usados, limite, max(0, livres)))
    if estado == "critico":
        print("::error title=Capacidade critica::" + mensagem)
        print("Coleta bloqueada antes de novas escritas.", file=sys.stderr)
        return 1
    if estado == "aviso":
        print("::warning title=Capacidade do banco::" + mensagem)
    else:
        print(mensagem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
