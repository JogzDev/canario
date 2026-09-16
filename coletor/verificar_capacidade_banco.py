"""Bloqueia coleta antes de esgotar o limite configurado para o banco.

O limite vem da RPC (com fallback Free), nao de uma consulta ao billing, e e
expresso em bytes decimais. A faixa de aviso dá visibilidade no
Actions; a faixa crítica preserva 4% para operação/índices e bloqueia novas
escritas até haver limpeza medida ou mudança consciente de plano.
"""

import argparse
import json
import os
import re
import sys

import supabase_rest


LIMITE_FREE = 500_000_000
AVISO_PERCENTUAL = 85
CRITICO_PERCENTUAL = 96
AVISO = AVISO_PERCENTUAL / 100
CRITICO = CRITICO_PERCENTUAL / 100


def avaliar_capacidade(bytes_usados, limite=LIMITE_FREE):
    if type(bytes_usados) is not int or bytes_usados < 0:
        raise ValueError("tamanho do banco invalido")
    if type(limite) is not int or limite <= 0:
        raise ValueError("limite do banco invalido")
    fracao = bytes_usados / limite
    if bytes_usados * 100 >= limite * CRITICO_PERCENTUAL:
        estado = "critico"
    elif bytes_usados * 100 >= limite * AVISO_PERCENTUAL:
        estado = "aviso"
    else:
        estado = "ok"
    return estado, fracao, limite - bytes_usados


def diagnosticar_capacidade(bytes_usados, limite=LIMITE_FREE):
    """A folga nao e permissao de poda; apenas descreve a leitura atual.

    Limiares sao inclusivos. Sair de 96% exige ficar pelo menos um byte
    abaixo dele; a mesma regra vale para voltar a menos de 85%.
    """
    estado, fracao, livres = avaliar_capacidade(bytes_usados, limite)
    aviso_bytes = (limite * AVISO_PERCENTUAL + 99) // 100
    critico_bytes = (limite * CRITICO_PERCENTUAL + 99) // 100
    return {
        "versao": 1,
        "estado": estado,
        "escrita_permitida": estado != "critico",
        "bytes_usados": bytes_usados,
        "limite_bytes": limite,
        "fracao_usada": fracao,
        "bytes_livres": max(0, livres),
        "bytes_excedentes": max(0, -livres),
        "aviso_fracao": AVISO,
        "critico_fracao": CRITICO,
        "aviso_bytes": aviso_bytes,
        "critico_bytes": critico_bytes,
        "folga_ate_critico_bytes": max(0, critico_bytes - bytes_usados),
        "liberar_para_abaixo_critico_bytes": max(
            0, bytes_usados - critico_bytes + 1),
        "liberar_para_abaixo_aviso_bytes": max(
            0, bytes_usados - aviso_bytes + 1),
    }


def inteiro_da_leitura(valor):
    # Nao truncar float nem aceitar bool/NULL como tamanho ou limite. O RPC
    # antigo pode enviar bigint como texto decimal, que continua aceito.
    if type(valor) is int:
        return valor
    if isinstance(valor, str) and re.fullmatch(r"[0-9]+", valor):
        return int(valor)
    raise ValueError("capacidade deve ser um inteiro")


def diagnosticar_leitura(leitura):
    if not isinstance(leitura, dict):
        raise ValueError("leitura de capacidade invalida")
    return diagnosticar_capacidade(
        inteiro_da_leitura(leitura["bytes"]),
        inteiro_da_leitura(leitura.get("limite_bytes", LIMITE_FREE)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true",
                        help="emite diagnostico JSON; preserva o exit code")
    parser.add_argument("--github-output", action="store_true",
                        help="expoe estado e permissao no GITHUB_OUTPUT")
    args = parser.parse_args(argv)
    erro = None
    diagnostico = None
    if not supabase_rest.configurado():
        erro = "configuracao_ausente"
    else:
        try:
            diagnostico = diagnosticar_leitura(supabase_rest.rpc("uso_do_banco"))
        except (KeyError, TypeError, ValueError):
            erro = "leitura_invalida"
        except supabase_rest.SupabaseErro:
            erro = "consulta_falhou"
    if erro:
        # Nenhum tamanho ficticio nem corpo de erro remoto (pode ser sensivel).
        diagnostico = {"versao": 1, "estado": "indisponivel",
                       "escrita_permitida": False, "erro": erro}

    if args.github_output:
        try:
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as saida:
                saida.write("estado={}\nescrita_permitida={}\n".format(
                    diagnostico["estado"],
                    str(diagnostico["escrita_permitida"]).lower()))
        except (KeyError, OSError):
            print("ERRO: nao foi possivel expor o portao ao Actions.", file=sys.stderr)
            return 1

    if args.json:
        print(json.dumps(diagnostico, ensure_ascii=False, sort_keys=True))
    if erro:
        print("ERRO: capacidade indisponivel ({}); escrita bloqueada.".format(erro),
              file=sys.stderr)
        return 1
    if args.json:
        return 0 if diagnostico["escrita_permitida"] else 1

    usados = diagnostico["bytes_usados"]
    limite = diagnostico["limite_bytes"]
    estado = diagnostico["estado"]
    fracao = diagnostico["fracao_usada"]
    livres = diagnostico["bytes_livres"]

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
