"""Impede que uma coleta empurre o projeto Free para read-only.

O QUE E MEDIDO
==============

A cota do plano Free e a "Database size" da plataforma, que a documentacao do
Supabase define como a soma de `pg_database_size` sobre TODOS os bancos do
cluster -- nao so o banco `postgres`. Ate a P21 este portao lia apenas o banco
principal. Medido em 18/09/2026:

    postgres     485.952.659 bytes   o que o portao via       97,19%
    template0      7.520.783 bytes
    template1      7.752.851 bytes
    total        501.226.293 bytes   o que a cota ve         100,25%

A diferenca sao os bancos-modelo do cluster. Eles nao sao nossos e nao ha como
reduzi-los; o que da para fazer e medi-los e decidir pelo total.

A saida separa os tres numeros -- banco principal, overhead interno e total da
cota -- e o veredito usa sempre o total.

QUANDO O BANCO AINDA NAO TEM A P21
==================================

A RPC antiga devolve so `bytes` do banco principal. Nesse caso o portao soma um
overhead MINIMO medido (template0 + template1 em 18/09/2026) e diz na saida que
esta estimando. O numero pode estar abaixo do real se os bancos-modelo tiverem
crescido desde entao, nunca acima do que foi medido -- por isso e piso, e o
aviso aparece na saida em vez de ficar escondido aqui.

As faixas continuam as mesmas: aviso em 85%, bloqueio em 96%. A faixa critica
preserva 4% para operacao e indices.
"""

import sys

import supabase_rest


LIMITE_FREE = 500_000_000
AVISO = 0.85
CRITICO = 0.96

# template0 (7.520.783) + template1 (7.752.851), medidos em 18/09/2026 as
# 12:37 UTC com `pg_database_size`. So entra quando a RPC nao traz o numero.
OVERHEAD_MINIMO_MEDIDO = 15_273_634


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


def ler_uso(leitura):
    """Separa banco principal, overhead interno e total da cota.

    Devolve `(cota, principal, overhead, estimado)`. `estimado` e verdadeiro
    quando o overhead nao veio do banco e foi preenchido com o piso medido.
    """
    if "bytes_da_cota" in leitura:
        cota = int(leitura["bytes_da_cota"])
        principal = int(leitura["banco_principal_bytes"])
        overhead = int(leitura["overhead_interno_bytes"])
        if principal < 0 or overhead < 0 or principal + overhead != cota:
            raise ValueError("a cota nao fecha: {} + {} != {}".format(
                principal, overhead, cota))
        return cota, principal, overhead, False
    principal = int(leitura["bytes"])
    return principal + OVERHEAD_MINIMO_MEDIDO, principal, OVERHEAD_MINIMO_MEDIDO, True


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    try:
        leitura = supabase_rest.rpc("uso_do_banco") or {}
        cota, principal, overhead, estimado = ler_uso(leitura)
        limite = int(leitura.get("limite_bytes") or LIMITE_FREE)
        estado, fracao, livres = avaliar_capacidade(cota, limite)
    except (KeyError, TypeError, ValueError, supabase_rest.SupabaseErro) as erro:
        print("ERRO: nao foi possivel medir a capacidade: {}".format(erro),
              file=sys.stderr)
        return 1

    mensagem = ("Cota: {:.1f}% ({:,} de {:,} bytes; {:,} livres) = banco "
                "principal {:,} + overhead interno {:,}{}.".format(
                    fracao * 100, cota, limite, max(0, livres), principal,
                    overhead, " (overhead ESTIMADO pelo piso de 18/09: o banco "
                    "ainda nao tem a P21)" if estimado else ""))
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
