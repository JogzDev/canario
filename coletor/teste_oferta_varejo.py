"""Regressoes da fronteira entre avistamento, delta e oferta compravel."""

from datetime import date
import sys

import coletor_varejo as varejo


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def main():
    # Seller[0] nao e contrato de disponibilidade na VTEX. Uma oferta
    # secundaria compravel torna o item ofertavel e deve fornecer o preco.
    produto_vtex = {
        "productId": "v1",
        "productName": "Blusa",
        "items": [{
            "variations": ["Tamanho"],
            "Tamanho": ["M"],
            "sellers": [
                {"commertialOffer": {
                    "IsAvailable": False, "AvailableQuantity": 0,
                    "Price": 99.0, "ListPrice": 129.0,
                }},
                {"commertialOffer": {
                    "IsAvailable": True, "AvailableQuantity": 2,
                    "Price": 109.0, "ListPrice": 139.0,
                }},
            ],
        }],
    }
    vtex = varejo.vtex_extrair(produto_vtex, "loja.test")
    if (vtex["ofertavel"] is not True or vtex["preco_atual"] != 109.0
            or vtex["grade_por_tamanho"] != {"M": True}):
        return falhar("VTEX nao reconheceu a oferta compravel entre sellers")

    produto_morto = {
        "productId": "v2",
        "productName": "Blusa antiga",
        "items": [{
            "variations": ["Tamanho"],
            "Tamanho": ["P"],
            "sellers": [{"commertialOffer": {
                "IsAvailable": False, "AvailableQuantity": 0,
                "Price": 119.0, "ListPrice": 159.0,
            }}],
        }],
    }
    morto = varejo.vtex_extrair(produto_morto, "loja.test")
    if (morto["ofertavel"] is not False or morto["preco_atual"] != 119.0
            or morto["grade_por_tamanho"] != {"P": False}):
        return falhar("preco cadastrado sem estoque ainda virou oferta VTEX")

    # Tamanho unico pode nao ter grade, mas a variante ainda declara oferta.
    shopify = varejo.shopify_extrair({
        "id": 3,
        "handle": "lenco",
        "_dominio": "loja.test",
        "options": [{"name": "Cor", "position": 1}],
        "variants": [
            {"option1": "Azul", "available": False, "price": "40.00"},
            {"option1": "Verde", "available": True, "price": "45.00",
             "compare_at_price": "50.00"},
        ],
    })
    if (shopify["ofertavel"] is not True or shopify["preco_atual"] != 45.0
            or shopify["grade_por_tamanho"] is not None):
        return falhar("Shopify confundiu grade ausente com indisponibilidade")

    # Avistamento anda diariamente; snapshot continua esparso.
    original_selecionar = varejo.supabase_rest.selecionar
    original_upsert = varejo.supabase_rest.upsert
    produtos_gravados = []
    snapshots_gravados = []

    def selecionar_falso(_tabela, _params):
        return [{
            "id": 7, "id_externo": "x1",
            "ultimo_preco_atual": 100.0,
            "ultimo_preco_original": 120.0,
            "ultima_grade": {"M": True},
            "ultimo_snapshot_em": "2026-08-19",
            "primeiro_avistamento": "2026-08-01",
            "ultimo_avistamento_em": "2026-08-19",
            "ofertavel": True,
        }]

    def upsert_falso(tabela, linhas, on_conflict, retornar=False):
        if tabela == "produtos":
            produtos_gravados.extend(linhas)
            return [{"id": 7, "id_externo": "x1"}] if retornar else []
        if tabela == "snapshots":
            snapshots_gravados.extend(linhas)
        return []

    varejo.supabase_rest.selecionar = selecionar_falso
    varejo.supabase_rest.upsert = upsert_falso
    try:
        gravados, _ = varejo.gravar_lote(1, [{
            "id_externo": "x1", "url": "https://loja.test/x1",
            "titulo": "Blusa", "categoria_site": "Blusas",
            "imagem_url": None, "preco_original": 120.0,
            "preco_atual": 100.0, "composicao": None,
            "grade_por_tamanho": {"M": True}, "ofertavel": True,
        }], date(2026, 8, 20))
    finally:
        varejo.supabase_rest.selecionar = original_selecionar
        varejo.supabase_rest.upsert = original_upsert

    if gravados != 0 or snapshots_gravados:
        return falhar("produto sem delta ganhou snapshot diario")
    if (len(produtos_gravados) != 1
            or produtos_gravados[0].get("ultimo_avistamento_em") != "2026-08-20"
            or produtos_gravados[0].get("ofertavel") is not True):
        return falhar("visita diaria nao atualizou avistamento e oferta")

    if not varejo._mudou(
            {"preco_atual": 100, "preco_original": 120,
             "grade_por_tamanho": None, "ofertavel": False},
            {"ultimo_preco_atual": 100, "ultimo_preco_original": 120,
             "ultima_grade": None, "ofertavel": True}):
        return falhar("mudanca de oferta sem grade nao abriu delta")

    if not varejo._mudou(
            {"preco_atual": None, "preco_original": None,
             "grade_por_tamanho": None, "ofertavel": False},
            {"ultimo_preco_atual": None, "ultimo_preco_original": None,
             "ultima_grade": None, "ofertavel": None}):
        return falhar("primeira conclusao sobre legado desconhecido nao abriu delta")

    print("Varejo: avistamento, delta e oferta compravel permanecem separados")
    return 0


if __name__ == "__main__":
    sys.exit(main())
