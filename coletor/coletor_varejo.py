"""Coletor de varejo (§17), modo amplo (A2), gravacao por delta (B3).

Fluxo por marca aprovada (VTEX ou Shopify), EM SERIE (nunca em paralelo):
  1. descobre as categorias femininas (classificador provisorio, A2);
  2. pagina os produtos dessas categorias, sem teto de tamanho (condicao 2.3);
  3. faz upsert de cada produto;
  4. grava snapshot SO se algo mudou vs. o ultimo, mais batimento semanal (B3);
  5. acumula saude: visitados vs gravados, e total declarado vs coletado.

Ritmo: 1 requisicao por segundo GLOBAL (regra 7 emendada em 24/07), garantido
pelo throttle de teste_30s.buscar somado a um teto global neste modulo. Coleta
de madrugada via cron 0 6 * * * UTC.

O matching titulo->termo NAO acontece aqui: a taxonomia ainda nao esta aprovada
(regra 4 / B2) e o casamento e retroativo. Este coletor so guarda o cru.
"""

import json
import os
import sys
import threading
import time
from datetime import date, datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import teste_30s  # noqa: E402
from teste_30s import buscar, robots_permite  # noqa: E402
from mapa_categorias import classificar  # noqa: E402
import supabase_rest  # noqa: E402
import materializar_anexos  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAUDE_MD = os.path.join(RAIZ, "SAUDE.md")

PAGINA = 50            # VTEX: janela do header Range
LIMITE_GLOBAL = 1.0   # regra 7 emendada: 1 req/s GLOBAL, nao por dominio

_trava_global = threading.Lock()
_ultima_req = [0.0]


def _ritmo_global():
    with _trava_global:
        espera = LIMITE_GLOBAL - (time.monotonic() - _ultima_req[0])
        if espera > 0:
            time.sleep(espera)
        _ultima_req[0] = time.monotonic()


def buscar_lento(url, dominio):
    """buscar() com o teto GLOBAL por cima do teto por dominio."""
    _ritmo_global()
    return buscar(url, dominio)


# ---------------------------------------------------------------------------
# VTEX
# ---------------------------------------------------------------------------

def vtex_categorias_femininas(dominio):
    """Arvore de categorias -> ids que o classificador marca como femininos (A2)."""
    caminho = "/api/catalog_system/pub/category/tree/3"
    if not robots_permite(dominio, caminho)[0]:
        return [], "robots proibe a arvore"
    codigo, corpo, _, _ = buscar_lento("https://{}{}".format(dominio, caminho), dominio)
    if codigo not in (200, 206) or not corpo:
        return [], "arvore http {}".format(codigo)
    try:
        arvore = json.loads(corpo)
    except ValueError:
        return [], "arvore nao-json"

    ids = []

    def andar(nos, caminho_pai):
        for no in nos or []:
            nome = no.get("name") or ""
            caminho_cat = "{} > {}".format(caminho_pai, nome) if caminho_pai else nome
            incluir, _, _ = classificar(caminho_cat)
            if incluir == "sim" and no.get("id"):
                ids.append((no["id"], caminho_cat))
            andar(no.get("children"), caminho_cat)

    andar(arvore, "")
    return ids, ""


def vtex_paginar(dominio, categoria_id):
    """Pagina os produtos de uma categoria via fq=C e header Range (sem teto)."""
    de = 0
    while True:
        ate = de + PAGINA - 1
        url = ("https://{}/api/catalog_system/pub/products/search"
               "?fq=C:{}&_from={}&_to={}".format(dominio, categoria_id, de, ate))
        if not robots_permite(dominio, "/api/catalog_system/pub/products/search")[0]:
            return
        codigo, corpo, _, cab = buscar_lento(url, dominio)
        if codigo == 429:
            time.sleep(30)
            continue
        if codigo not in (200, 206) or not corpo:
            return
        try:
            produtos = json.loads(corpo)
        except ValueError:
            return
        if not produtos:
            return
        total = None
        recurso = cab.get("resources") or cab.get("Resources") or ""
        if "/" in recurso:
            try:
                total = int(recurso.split("/")[-1])
            except ValueError:
                total = None
        for p in produtos:
            yield p, total
        de += PAGINA
        # A VTEX limita offset em 2500 por consulta; a categoria raramente
        # passa disso, mas se passar, paramos honestamente nesta categoria.
        if de > 2500 or len(produtos) < PAGINA:
            return


def vtex_extrair(p):
    """Normaliza um produto VTEX para o schema. Defensivo: campo ausente vira None."""
    itens = p.get("items") or []
    grade = {}
    preco_atual = preco_orig = None
    for it in itens:
        tamanho = None
        for v in (it.get("variations") or []):
            nome = v if isinstance(v, str) else ""
            if "tam" in nome.lower():
                vals = it.get(v) or []
                tamanho = vals[0] if vals else None
        if not tamanho:
            tamanho = it.get("Tamanho", [None])[0] if isinstance(it.get("Tamanho"), list) else None
        sellers = it.get("sellers") or []
        disponivel = False
        if sellers:
            oferta = (sellers[0].get("commertialOffer") or {})
            disponivel = bool(oferta.get("IsAvailable")) and (oferta.get("AvailableQuantity", 0) or 0) > 0
            if preco_atual is None and oferta.get("Price"):
                preco_atual = oferta.get("Price")
                preco_orig = oferta.get("ListPrice") or oferta.get("Price")
        if tamanho:
            grade[str(tamanho)] = grade.get(str(tamanho), False) or disponivel

    composicao = None
    for chave in ("Composição", "Composicao", "Material"):
        val = p.get(chave)
        if isinstance(val, list) and val:
            composicao = val[0]
            break

    imagem = None
    if itens and (itens[0].get("images") or []):
        imagem = itens[0]["images"][0].get("imageUrl")

    return {
        "id_externo": str(p.get("productId") or ""),
        "url": p.get("link") or (("https://" + p.get("linkText", "") + "/p") if p.get("linkText") else None),
        "titulo": p.get("productName"),
        "descricao": (p.get("description") or None),
        "categoria_site": (p.get("categories") or [None])[0],
        "imagem_url": imagem,
        "preco_original": preco_orig,
        "preco_atual": preco_atual,
        "composicao": composicao,
        "grade_por_tamanho": grade or None,
    }


# ---------------------------------------------------------------------------
# Shopify
# ---------------------------------------------------------------------------

def shopify_paginar(dominio):
    """Pagina /products.json (modo amplo: catalogo todo; segmento vem depois)."""
    pagina = 1
    while True:
        url = "https://{}/products.json?limit=250&page={}".format(dominio, pagina)
        if not robots_permite(dominio, "/products.json")[0]:
            return
        codigo, corpo, _, _ = buscar_lento(url, dominio)
        if codigo == 429:
            time.sleep(30)
            continue
        if codigo not in (200, 206) or not corpo:
            return
        try:
            produtos = (json.loads(corpo) or {}).get("products") or []
        except ValueError:
            return
        if not produtos:
            return
        for p in produtos:
            yield p, None
        pagina += 1
        if len(produtos) < 250:
            return


def shopify_extrair(p):
    variantes = p.get("variants") or []
    grade = {}
    preco_atual = preco_orig = None
    for v in variantes:
        tamanho = v.get("option1")
        disponivel = bool(v.get("available"))
        if tamanho:
            grade[str(tamanho)] = grade.get(str(tamanho), False) or disponivel
        if preco_atual is None and v.get("price"):
            try:
                preco_atual = float(v.get("price"))
                preco_orig = float(v.get("compare_at_price") or v.get("price"))
            except (TypeError, ValueError):
                pass
    imagem = None
    if p.get("images"):
        imagem = p["images"][0].get("src")
    handle = p.get("handle")
    return {
        "id_externo": str(p.get("id") or ""),
        "url": ("https://{}/products/{}".format(p.get("_dominio", ""), handle) if handle else None),
        "titulo": p.get("title"),
        "descricao": None,  # body_html e HTML pesado; nao guardamos cru
        "categoria_site": p.get("product_type"),
        "imagem_url": imagem,
        "preco_original": preco_orig,
        "preco_atual": preco_atual,
        "composicao": None,
        "grade_por_tamanho": grade or None,
    }


# ---------------------------------------------------------------------------
# Delta + persistencia
# ---------------------------------------------------------------------------

def mudou(novo, ultimo):
    """B3: grava so quando preco, grade ou disponibilidade mudou."""
    if ultimo is None:
        return True
    if float(novo.get("preco_atual") or 0) != float(ultimo.get("preco_atual") or 0):
        return True
    if float(novo.get("preco_original") or 0) != float(ultimo.get("preco_original") or 0):
        return True
    if (novo.get("grade_por_tamanho") or {}) != (ultimo.get("grade_por_tamanho") or {}):
        return True
    return False


def coletar_marca(marca, hoje):
    """Coleta uma marca. Devolve metricas de saude."""
    nome, dominio, plataforma = marca["nome"], marca["dominio"], marca["plataforma"]
    visitados = gravados = campos_ok = 0
    total_declarado = 0

    if plataforma == "vtex":
        cats, erro = vtex_categorias_femininas(dominio)
        if erro:
            return {"marca_id": marca["id"], "fonte": "varejo", "visitados": 0,
                    "gravados": 0, "itens": 0, "total_declarado": None,
                    "pct_campos_ok": None, "alertas": {"erro": erro}}
        vistos_ids = set()
        for cat_id, _caminho in cats:
            for p, total in vtex_paginar(dominio, cat_id):
                if total:
                    total_declarado = max(total_declarado, total)
                dados = vtex_extrair(p)
                if not dados["id_externo"] or dados["id_externo"] in vistos_ids:
                    continue
                vistos_ids.add(dados["id_externo"])
                visitados += 1
                campos_ok += _campos_ok(dados)
                gravados += _persistir(marca["id"], dados, hoje)
    elif plataforma == "shopify":
        for p, _ in shopify_paginar(dominio):
            p["_dominio"] = dominio
            dados = shopify_extrair(p)
            if not dados["id_externo"]:
                continue
            visitados += 1
            campos_ok += _campos_ok(dados)
            gravados += _persistir(marca["id"], dados, hoje)
    else:
        return None

    pct = round(campos_ok / visitados, 3) if visitados else None
    alertas = {}
    # Condicao 2.3: divergencia >2% entre coletado e declarado vira alerta.
    if plataforma == "vtex" and total_declarado:
        div = abs(visitados - total_declarado) / total_declarado
        if div > 0.02:
            alertas["divergencia_total"] = {
                "coletado": visitados, "declarado_no_header": total_declarado,
                "obs": "esperado: o total do header conta so 'vestido'; o coletado cobre todas as categorias femininas"}
    return {"marca_id": marca["id"], "fonte": "varejo", "visitados": visitados,
            "gravados": gravados, "itens": visitados,
            "total_declarado": total_declarado or None, "pct_campos_ok": pct,
            "alertas": alertas or None}


def _campos_ok(d):
    """1 se os campos essenciais de varejo vieram (tamanho, preco, titulo)."""
    tem_preco = d.get("preco_atual") is not None
    tem_grade = bool(d.get("grade_por_tamanho"))
    tem_titulo = bool(d.get("titulo"))
    return 1 if (tem_preco and tem_grade and tem_titulo) else 0


def _persistir(marca_id, dados, hoje):
    """Upsert do produto e snapshot por delta. Devolve 1 se gravou snapshot."""
    prod = supabase_rest.upsert("produtos", [{
        "marca_id": marca_id,
        "id_externo": dados["id_externo"],
        "url": dados["url"],
        "titulo": dados["titulo"],
        "descricao": dados["descricao"],
        "categoria_site": dados["categoria_site"],
        "imagem_url": dados["imagem_url"],
        "primeiro_avistamento": hoje.isoformat(),
    }], on_conflict="marca_id,id_externo", retornar=True)
    if not prod:
        return 0
    produto_id = prod[0]["id"]

    ultimo = supabase_rest.selecionar(
        "snapshots",
        "?produto_id=eq.{}&order=data.desc&limit=1".format(produto_id))
    ultimo = ultimo[0] if ultimo else None

    novo = {"preco_atual": dados["preco_atual"], "preco_original": dados["preco_original"],
            "grade_por_tamanho": dados["grade_por_tamanho"]}
    if not mudou(novo, ultimo):
        return 0
    supabase_rest.upsert("snapshots", [{
        "produto_id": produto_id,
        "data": hoje.isoformat(),
        "preco_original": dados["preco_original"],
        "preco_atual": dados["preco_atual"],
        "composicao": dados["composicao"],
        "grade_por_tamanho": dados["grade_por_tamanho"],
    }], on_conflict="produto_id,data")
    return 1


# ---------------------------------------------------------------------------
# Saude (§20 + K9)
# ---------------------------------------------------------------------------

def escrever_saude(hoje, metricas):
    for m in metricas:
        supabase_rest.upsert("saude", [{
            "data": hoje.isoformat(), "fonte": "varejo", "marca_id": m["marca_id"],
            "visitados": m["visitados"], "gravados": m["gravados"],
            "itens": m["itens"], "total_declarado": m["total_declarado"],
            "pct_campos_ok": m["pct_campos_ok"], "alertas": m["alertas"],
        }], on_conflict="data,fonte,marca_id")

    tot_vis = sum(m["visitados"] for m in metricas)
    tot_grav = sum(m["gravados"] for m in metricas)
    marcas_zero = [m for m in metricas if m["visitados"] == 0]

    linhas = ["# SAÚDE — coletores do Canário\n",
              "**Última coleta (UTC):** {}\n".format(datetime.now(timezone.utc).isoformat()),
              "\n## Varejo\n",
              "- Produtos **visitados**: {}\n".format(tot_vis),
              "- Snapshots **gravados** (delta, B3): {}\n".format(tot_grav),
              "- Marcas coletando: {} de {}\n".format(len(metricas) - len(marcas_zero), len(metricas))]
    if marcas_zero:
        linhas.append("\n> ⚠️ Marcas com ZERO itens (alerta imediato, §20): {}\n".format(
            ", ".join(str(m["marca_id"]) for m in marcas_zero)))
    linhas.append("\n| Marca (id) | Visitados | Gravados | % campos ok | Total declarado | Alertas |")
    linhas.append("|---|---|---|---|---|---|")
    for m in sorted(metricas, key=lambda x: -x["visitados"]):
        linhas.append("| {} | {} | {} | {} | {} | {} |".format(
            m["marca_id"], m["visitados"], m["gravados"],
            m["pct_campos_ok"] if m["pct_campos_ok"] is not None else "—",
            m["total_declarado"] or "—",
            json.dumps(m["alertas"], ensure_ascii=False) if m["alertas"] else "—"))
    linhas.append("\n---\n")
    linhas.append("Se *visitados* e *gravados* convergirem dia após dia, é sinal de bug no delta (B3).\n")
    with open(SAUDE_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    print("Materializando anexos...", file=sys.stderr)
    materializar_anexos.materializar_marcas()
    materializar_anexos.materializar_termos()

    marcas = supabase_rest.selecionar(
        "marcas",
        "?status_teste=in.(vtex,shopify)&ativa=eq.true&select=id,nome,dominio,plataforma")
    print("Marcas aprovadas para coleta: {}".format(len(marcas)), file=sys.stderr)

    hoje = date.today()
    metricas = []
    for marca in marcas:
        t0 = time.monotonic()
        m = coletar_marca(marca, hoje)
        if m:
            metricas.append(m)
            print("  {:14} visitados={} gravados={} ({:.0f}s)".format(
                marca["nome"], m["visitados"], m["gravados"], time.monotonic() - t0),
                file=sys.stderr)

    escrever_saude(hoje, metricas)
    print("Coleta concluída. SAUDE.md atualizado.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
