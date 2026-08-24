"""Testes unitários do verificador operacional de segmentos."""

import os

import verificar_isolamento_segmento as alvo


def executar(fora):
    selecionar_original = alvo.supabase_rest.selecionar
    contar_original = alvo.supabase_rest.contar
    configurado_original = alvo.supabase_rest.configurado
    ambiente_original = os.environ.get("SEGMENTO_VERIFICADO")
    try:
        os.environ["SEGMENTO_VERIFICADO"] = "direcao_intl"
        alvo.supabase_rest.configurado = lambda: True
        alvo.supabase_rest.selecionar = lambda *_args: [
            {"id": 7, "nome": "Marca Teste", "segmento": "direcao_intl"}]

        def contar(_tabela, params=""):
            if "marca_id" not in params:
                return 12
            return fora if "segmento=neq" in params else 12

        alvo.supabase_rest.contar = contar
        return alvo.main()
    finally:
        alvo.supabase_rest.selecionar = selecionar_original
        alvo.supabase_rest.contar = contar_original
        alvo.supabase_rest.configurado = configurado_original
        if ambiente_original is None:
            os.environ.pop("SEGMENTO_VERIFICADO", None)
        else:
            os.environ["SEGMENTO_VERIFICADO"] = ambiente_original


assert executar(0) == 0
assert executar(3) == 1
print("OK: isolamento de segmentos")
