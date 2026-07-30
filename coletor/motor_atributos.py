"""Motor, passo 1: liga produto a termo da taxonomia (§11, §17).

Sem isto a perna de varejo nao alimenta indice nenhum: 65 mil produtos
coletados e nenhum sabendo o que e. O coletor guarda o cru de proposito (B2: o
casamento e retroativo, e a taxonomia so foi aprovada em 28/07); e aqui que o
cru vira atributo.

O que faz:
  * casa titulo + descricao contra `palavras_pt` e `palavras_en` dos termos
    APROVADOS (regra 4), com o `matcher` de correspondencia exata -- o mesmo que
    ja carrega a regressao `reta` nao casa `preta`;
  * grava em `produto_termos` com origem='titulo';
  * preenche `produtos.segmento` (B4).

Sobre o segmento: o coletor so desce departamentos que o classificador aprova
como vestuario feminino, em TODO nivel da arvore. Entao todo produto que ele
trouxe esta no segmento por construcao, e nao por suposicao -- e o que o B4
queria derivar do mapa de categorias ja esta garantido pelo caminho da coleta.

Idempotente: pode rodar todo dia. A chave de produto_termos e
(produto_id, termo_id, origem), entao recasar nao duplica.
"""

import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import compilar_lista, termos_que_casam  # noqa: E402
import supabase_rest  # noqa: E402

SEGMENTO = "feminino_casual_br"
PAGINA = 1000
BLOCO_ESCRITA = 500


def carregar_termos():
    """Termos aprovados -> {id: [regex]}, e o conjunto de ids de categoria."""
    aprovados = supabase_rest.selecionar(
        "termos",
        "?status=eq.aprovado&select=id,rotulo,dimensao,palavras_pt,palavras_en")
    categorias = {t["id"] for t in aprovados if t.get("dimensao") == "categoria"}
    compilados = {}
    for t in aprovados:
        padroes = []
        for campo in ("palavras_pt", "palavras_en"):
            valor = (t.get(campo) or "").strip()
            if valor:
                padroes.extend(p for p in valor.split("|") if p.strip())
        if t.get("rotulo"):
            padroes.append(t["rotulo"])
        regexes = compilar_lista(padroes)
        if regexes:
            compilados[t["id"]] = regexes
    return compilados, categorias


def produtos_em_paginas():
    """Percorre os produtos em paginas, pelo id, sem segurar tudo em memoria."""
    ultimo = 0
    while True:
        lote = supabase_rest.selecionar(
            "produtos",
            "?id=gt.{}&select=id,titulo,descricao,categoria_site,segmento"
            "&order=id.asc&limit={}".format(ultimo, PAGINA))
        if not lote:
            return
        yield lote
        ultimo = lote[-1]["id"]


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    termos, categorias = carregar_termos()
    if not termos:
        print("Nenhum termo aprovado com palavras.", file=sys.stderr)
        return 0
    print("Termos aprovados: {} ({} categorias)".format(
        len(termos), len(categorias)), file=sys.stderr)

    total = casados = ligacoes = 0
    sem_categoria = 0
    por_dimensao = {}
    buffer_pt, buffer_seg = [], []

    for lote in produtos_em_paginas():
        for p in lote:
            total += 1
            # §17: o titulo do e-commerce e a etiqueta quase pronta; a descricao
            # ajuda quando o titulo e curto demais.
            texto = " ".join(filter(None, [p.get("titulo"),
                                           p.get("descricao"),
                                           p.get("categoria_site")]))
            achados = termos_que_casam(texto, termos) if texto.strip() else set()
            if achados:
                casados += 1
                if not (achados & categorias):
                    # Vale registrar: produto com atributo e sem categoria fica
                    # invisivel na leitura do §11 ("categoria e filtro").
                    sem_categoria += 1
                for termo_id in achados:
                    buffer_pt.append({"produto_id": p["id"], "termo_id": termo_id,
                                      "origem": "titulo"})
                    ligacoes += 1
            if p.get("segmento") != SEGMENTO:
                buffer_seg.append(p["id"])

            if len(buffer_pt) >= BLOCO_ESCRITA:
                supabase_rest.upsert("produto_termos", buffer_pt,
                                     on_conflict="produto_id,termo_id,origem")
                buffer_pt = []
        # B4: segmento por construcao (so departamentos femininos foram descidos)
        for i in range(0, len(buffer_seg), 200):
            ids = ",".join(str(x) for x in buffer_seg[i:i + 200])
            supabase_rest.atualizar("produtos", "id=in.({})".format(ids),
                                    {"segmento": SEGMENTO})
        buffer_seg = []
        print("  {} produtos processados, {} com atributo, {} ligacoes".format(
            total, casados, ligacoes), file=sys.stderr)

    if buffer_pt:
        supabase_rest.upsert("produto_termos", buffer_pt,
                             on_conflict="produto_id,termo_id,origem")

    pct = (100.0 * casados / total) if total else 0
    print("\n{} produtos, {} com pelo menos um termo ({:.1f}%), {} ligacoes.".format(
        total, casados, pct, ligacoes), file=sys.stderr)
    print("Com atributo mas sem categoria: {} (ficam fora da leitura do §11)".format(
        sem_categoria), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
