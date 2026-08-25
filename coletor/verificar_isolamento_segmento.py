"""Prova que um painel adicional não contaminou os demais segmentos.

Roda apenas no ambiente operacional com service_role. O app não recebe essa
credencial e nenhuma política RLS é relaxada para viabilizar o diagnóstico.
"""

import os
import sys
import urllib.parse

import supabase_rest


def main():
    segmento = os.environ.get("SEGMENTO_VERIFICADO", "").strip()
    if not segmento:
        print("ERRO: SEGMENTO_VERIFICADO ausente.", file=sys.stderr)
        return 1
    if not supabase_rest.configurado():
        print("ERRO: credenciais operacionais ausentes.", file=sys.stderr)
        return 1

    segmento_q = urllib.parse.quote(segmento, safe="")
    marcas = supabase_rest.selecionar(
        "marcas", "?select=id,nome,segmento&segmento=eq.{}&order=nome".format(
            segmento_q))
    if not marcas:
        print("ERRO: nenhuma marca no segmento {}.".format(segmento),
              file=sys.stderr)
        return 1

    total = supabase_rest.contar(
        "produtos", "segmento=eq.{}".format(segmento_q))
    contaminados_total = 0
    excluidos_total = 0
    print("Segmento {}: {} produtos em {} marcas.".format(
        segmento, total, len(marcas)))
    for marca in marcas:
        marca_q = urllib.parse.quote(str(marca["id"]), safe="")
        dentro = supabase_rest.contar(
            "produtos", "marca_id=eq.{}&segmento=eq.{}".format(
                marca_q, segmento_q))
        excluidos = supabase_rest.contar(
            "produtos", "marca_id=eq.{}&segmento=is.null".format(marca_q))
        contaminados = supabase_rest.contar(
            "produtos", "marca_id=eq.{}&segmento=not.is.null&segmento=neq.{}".format(
                marca_q, segmento_q))
        excluidos_total += excluidos or 0
        contaminados_total += contaminados or 0
        print("- {}: {} no segmento; {} excluidos pelo recorte; {} contaminados".format(
            marca["nome"], dentro, excluidos, contaminados))

    if contaminados_total:
        print("ERRO: {} produtos das marcas do painel vazaram para outro segmento."
              .format(contaminados_total), file=sys.stderr)
        return 1
    print("Isolamento confirmado; {} produtos fora do recorte permaneceram sem segmento."
          .format(excluidos_total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
