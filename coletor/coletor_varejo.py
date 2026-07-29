"""Coletor de varejo (§17), modo amplo (A2), gravacao em lote por delta (B3).

Decisoes do JP (24/07):
  * SEM teto de produtos por marca: a ordem da loja e ordem de vitrine, cortar
    coletaria so o promovido e perderia a cauda de encalhe/remarcacao. Catalogo
    feminino inteiro de cada marca.
  * Chave de conflito do upsert de produto = (marca_id, id_externo), nunca so o
    id_externo.
  * A primeira coleta e backfill: pode passar da janela de 5,5h, roda uma vez,
    disparada a mao. So as coletas diarias (deltas pequenos) precisam caber. Se
    a primeira exceder o teto de uma execucao, particionar por marca (env
    COLETA_MARCA).
  * SAUDE.md reporta total declarado (header VTEX) vs gravado, por marca.

Ritmo: 1 req/s GLOBAL (regra 7 emendada), nao por dominio. Escrita no Supabase
em lote (~500 por bloco) para nao estourar a janela com round-trips.

O matching titulo->termo NAO acontece aqui (taxonomia ainda proposta; regra 4 /
B2). Este coletor so guarda o cru; o casamento e retroativo.
"""

import json
import os
import sys
import threading
import time
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar, robots_permite  # noqa: E402
from mapa_categorias import classificar  # noqa: E402
import supabase_rest  # noqa: E402
import materializar_anexos  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAUDE_MD = os.path.join(RAIZ, "SAUDE.md")
CACHE_DEPS = os.path.join(RAIZ, "anexos", "departamentos_vtex.json")

# A arvore de categorias e o endpoint mais limitado da VTEX: em 29/07 devolveu
# 429 enquanto a busca de produtos respondia 206 no mesmo dominio, minutos
# antes. Como e UMA requisicao por marca e sem ela a marca inteira fica de
# fora, vale esperar muito mais do que numa pagina qualquer.
ESPERAS_ARVORE = [0, 45, 120, 240]

PAGINA = 50             # janela do header Range da VTEX
TETO_OFFSET = 2500      # a VTEX corta o offset em 2500 por consulta
BLOCO_ESCRITA = 500     # linhas por upsert em lote
BLOCO_LEITURA = 120     # id_externos por filtro in.()
LIMITE_GLOBAL = 1.0     # regra 7 emendada: 1 req/s GLOBAL
BACKOFF_429 = 60        # um unico retry longo (decisao do JP)
PRECO_TETO = 200000     # teto de preco para o particionamento (R$)

_trava = threading.Lock()
_ultima = [0.0]


def _ritmo():
    with _trava:
        espera = LIMITE_GLOBAL - (time.monotonic() - _ultima[0])
        if espera > 0:
            time.sleep(espera)
        _ultima[0] = time.monotonic()


def buscar_varejo(url, dominio):
    """buscar() com teto GLOBAL e um unico retry longo diante de 429."""
    _ritmo()
    codigo, corpo, final, cab = buscar(url, dominio)
    if codigo == 429:
        time.sleep(BACKOFF_429)
        _ritmo()
        codigo, corpo, final, cab = buscar(url, dominio)
    return codigo, corpo, final, cab


def _total_do_header(cab):
    recurso = cab.get("resources") or cab.get("Resources") or ""
    if "/" in recurso:
        try:
            return int(recurso.split("/")[-1])
        except ValueError:
            return None
    return None


# ---------------------------------------------------------------------------
# VTEX: departamentos femininos + paginacao completa por particao de preco
# ---------------------------------------------------------------------------

def _carregar_cache_departamentos():
    if os.path.exists(CACHE_DEPS):
        try:
            return json.load(open(CACHE_DEPS, encoding="utf-8"))
        except ValueError:
            return {}
    return {}


def _salvar_cache_departamentos(cache):
    cache["_nota"] = ("Departamentos femininos por marca, descobertos uma vez. "
                      "A arvore de categorias da VTEX e o endpoint mais limitado "
                      "(429 mesmo quando a busca de produtos responde 206), e ela "
                      "quase nao muda -- buscar toda noite era desperdicio e ponto "
                      "unico de falha. Apagar uma marca daqui forca a redescoberta.")
    with open(CACHE_DEPS, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, indent=1, sort_keys=True)


def vtex_departamentos_femininos(dominio, marca_nome, cache):
    """Departamentos de nivel 1 que o classificador marca como femininos (A2).

    fq=C:{id} traz o departamento E suas subcategorias, entao paginar os
    departamentos de topo cobre o catalogo feminino inteiro. Departamentos de
    topo sao disjuntos, o que torna o total declarado somavel.

    Le do cache quando existe. So bate na arvore na primeira vez -- e ai com
    paciencia extra, porque e UMA requisicao por marca e sem ela a marca
    inteira fica de fora.
    """
    if marca_nome in cache:
        return [(d["id"], d["nome"]) for d in cache[marca_nome]], ""

    caminho = "/api/catalog_system/pub/category/tree/1"
    if not robots_permite(dominio, caminho)[0]:
        return None, "robots proibe a arvore"

    url = "https://{}{}".format(dominio, caminho)
    codigo = None
    for espera in ESPERAS_ARVORE:
        if espera:
            time.sleep(espera)
        _ritmo()
        codigo, corpo, _, _ = buscar(url, dominio)
        if codigo in (200, 206) and corpo:
            break
    if codigo not in (200, 206) or not corpo:
        return None, "arvore http {} (apos {} tentativas)".format(
            codigo, len(ESPERAS_ARVORE))
    try:
        arvore = json.loads(corpo)
    except ValueError:
        return None, "arvore nao-json"

    deps = [(no["id"], no.get("name") or "")
            for no in arvore
            if no.get("id") and classificar(no.get("name") or "")[0] == "sim"]
    if deps:
        cache[marca_nome] = [{"id": i, "nome": n} for i, n in deps]
    return deps, ""


def _fq_preco(pmin, pmax):
    return "&fq=P:[{} TO {}]".format(pmin, pmax) if pmin is not None else ""


def _contar(dominio, cat_id, pmin=None, pmax=None):
    url = ("https://{}/api/catalog_system/pub/products/search"
           "?fq=C:{}{}&_from=0&_to=0".format(dominio, cat_id, _fq_preco(pmin, pmax)))
    codigo, _, _, cab = buscar_varejo(url, dominio)
    if codigo not in (200, 206):
        return None
    return _total_do_header(cab) or 0


def _paginar(dominio, cat_id, limite, pmin=None, pmax=None):
    de = 0
    while de < min(limite, TETO_OFFSET):
        ate = de + PAGINA - 1
        url = ("https://{}/api/catalog_system/pub/products/search"
               "?fq=C:{}{}&_from={}&_to={}".format(
                   dominio, cat_id, _fq_preco(pmin, pmax), de, ate))
        codigo, corpo, _, _ = buscar_varejo(url, dominio)
        if codigo not in (200, 206) or not corpo:
            return
        try:
            produtos = json.loads(corpo)
        except ValueError:
            return
        if not produtos:
            return
        for p in produtos:
            yield p
        de += PAGINA
        if len(produtos) < PAGINA:
            return


def vtex_departamento(dominio, cat_id, estado):
    """Todos os produtos de um departamento (inclui subcategorias via fq=C).

    Caso comum (departamento <= 2500): pagina so por categoria, sem depender do
    facet de preco. So quando passa de 2500 e que parte por preco para furar o
    teto de offset da VTEX; prefere sobreposicao a lacuna (o dedup remove a borda).
    """
    total = _contar(dominio, cat_id)
    if not total:
        return
    estado["declarado"] += total
    if total <= TETO_OFFSET:
        yield from _paginar(dominio, cat_id, total)
        return

    def particao(pmin, pmax):
        t = _contar(dominio, cat_id, pmin, pmax)
        if not t:
            return
        if t <= TETO_OFFSET:
            yield from _paginar(dominio, cat_id, t, pmin, pmax)
        elif pmax - pmin > 1:
            mid = (pmin + pmax) // 2
            yield from particao(pmin, mid)
            yield from particao(mid, pmax)
        else:
            estado["truncou"] = True  # faixa indivisivel ainda acima do teto
            yield from _paginar(dominio, cat_id, TETO_OFFSET, pmin, pmax)

    yield from particao(0, PRECO_TETO)


def vtex_extrair(p):
    itens = p.get("items") or []
    grade = {}
    preco_atual = preco_orig = None
    for it in itens:
        tamanho = None
        for v in (it.get("variations") or []):
            if isinstance(v, str) and "tam" in v.lower():
                vals = it.get(v) or []
                tamanho = vals[0] if vals else None
        sellers = it.get("sellers") or []
        disponivel = False
        if sellers:
            oferta = sellers[0].get("commertialOffer") or {}
            disponivel = bool(oferta.get("IsAvailable")) and (oferta.get("AvailableQuantity", 0) or 0) > 0
            if preco_atual is None and oferta.get("Price"):
                preco_atual = oferta.get("Price")
                preco_orig = oferta.get("ListPrice") or oferta.get("Price")
        if tamanho:
            chave = str(tamanho)
            grade[chave] = grade.get(chave, False) or disponivel
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
        "url": p.get("link") or None,
        "titulo": p.get("productName"),
        "descricao": p.get("description") or None,
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

def shopify_todos(dominio, estado):
    pagina = 1
    while True:
        url = "https://{}/products.json?limit=250&page={}".format(dominio, pagina)
        if not robots_permite(dominio, "/products.json")[0]:
            estado["erro"] = "robots proibe products.json"
            return
        codigo, corpo, _, _ = buscar_varejo(url, dominio)
        if codigo in (403, 429):
            estado["erro"] = "http {} (persistiu apos backoff longo)".format(codigo)
            return
        if codigo not in (200, 206) or not corpo:
            estado["erro"] = "http {}".format(codigo)
            return
        try:
            produtos = (json.loads(corpo) or {}).get("products") or []
        except ValueError:
            estado["erro"] = "resposta nao-json"
            return
        if not produtos:
            return
        for p in produtos:
            p["_dominio"] = dominio
            yield p
        pagina += 1
        if len(produtos) < 250:
            return


def shopify_extrair(p):
    grade = {}
    preco_atual = preco_orig = None
    for v in (p.get("variants") or []):
        tamanho = v.get("option1")
        if tamanho:
            chave = str(tamanho)
            grade[chave] = grade.get(chave, False) or bool(v.get("available"))
        if preco_atual is None and v.get("price"):
            try:
                preco_atual = float(v.get("price"))
                preco_orig = float(v.get("compare_at_price") or v.get("price"))
            except (TypeError, ValueError):
                pass
    imagem = p["images"][0].get("src") if p.get("images") else None
    handle = p.get("handle")
    return {
        "id_externo": str(p.get("id") or ""),
        "url": ("https://{}/products/{}".format(p.get("_dominio", ""), handle) if handle else None),
        "titulo": p.get("title"),
        "descricao": None,
        "categoria_site": p.get("product_type"),
        "imagem_url": imagem,
        "preco_original": preco_orig,
        "preco_atual": preco_atual,
        "composicao": None,
        "grade_por_tamanho": grade or None,
    }


# ---------------------------------------------------------------------------
# Persistencia em lote com delta O(1) (estado na propria linha de produtos)
# ---------------------------------------------------------------------------

def _pedacos(lista, n):
    for i in range(0, len(lista), n):
        yield lista[i:i + n]


def _mudou(d, ex):
    if float(d.get("preco_atual") or 0) != float(ex.get("ultimo_preco_atual") or 0):
        return True
    if float(d.get("preco_original") or 0) != float(ex.get("ultimo_preco_original") or 0):
        return True
    if (d.get("grade_por_tamanho") or {}) != (ex.get("ultima_grade") or {}):
        return True
    return False


def _precisa_snapshot(d, ex, hoje):
    if ex is None:
        return True
    if _mudou(d, ex):
        return True
    ultimo = ex.get("ultimo_snapshot_em")
    if not ultimo:
        return True
    try:
        return (hoje - date.fromisoformat(ultimo)).days >= 7  # batimento semanal (B3)
    except (TypeError, ValueError):
        return True


def gravar_lote(marca_id, coletados, hoje):
    """Grava um bloco de produtos coletados. Devolve (gravados, campos_ok)."""
    if not coletados:
        return 0, 0

    existentes = {}
    ids = [d["id_externo"] for d in coletados]
    for sub in _pedacos(ids, BLOCO_LEITURA):
        lista = ",".join('"{}"'.format(i) for i in sub)
        params = ("?marca_id=eq.{}&id_externo=in.({})"
                  "&select=id,id_externo,ultimo_preco_atual,ultimo_preco_original,"
                  "ultima_grade,ultimo_snapshot_em,primeiro_avistamento".format(marca_id, lista))
        for r in supabase_rest.selecionar("produtos", params):
            existentes[r["id_externo"]] = r

    prod_rows, snap_alvo = [], []
    campos_ok = 0
    for d in coletados:
        ex = existentes.get(d["id_externo"])
        escreve = _precisa_snapshot(d, ex, hoje)
        campos_ok += 1 if (d["preco_atual"] is not None and d["grade_por_tamanho"] and d["titulo"]) else 0
        prod_rows.append({
            "marca_id": marca_id,
            "id_externo": d["id_externo"],
            "url": d["url"],
            "titulo": d["titulo"],
            "descricao": d["descricao"],
            "categoria_site": d["categoria_site"],
            "imagem_url": d["imagem_url"],
            "primeiro_avistamento": (ex.get("primeiro_avistamento") if ex else hoje.isoformat()) or hoje.isoformat(),
            "ultimo_preco_atual": d["preco_atual"],
            "ultimo_preco_original": d["preco_original"],
            "ultima_grade": d["grade_por_tamanho"],
            "ultimo_snapshot_em": hoje.isoformat() if escreve else (ex.get("ultimo_snapshot_em") if ex else hoje.isoformat()),
        })
        if escreve:
            snap_alvo.append(d)

    id_por_externo = {}
    for bloco in _pedacos(prod_rows, BLOCO_ESCRITA):
        ret = supabase_rest.upsert("produtos", bloco,
                                   on_conflict="marca_id,id_externo", retornar=True)
        for r in ret:
            id_por_externo[r["id_externo"]] = r["id"]

    snap_rows = []
    for d in snap_alvo:
        pid = id_por_externo.get(d["id_externo"])
        if pid is None:
            continue
        snap_rows.append({
            "produto_id": pid, "data": hoje.isoformat(),
            "preco_original": d["preco_original"], "preco_atual": d["preco_atual"],
            "composicao": d["composicao"], "grade_por_tamanho": d["grade_por_tamanho"],
        })
    for bloco in _pedacos(snap_rows, BLOCO_ESCRITA):
        supabase_rest.upsert("snapshots", bloco, on_conflict="produto_id,data")

    return len(snap_rows), campos_ok


def coletar_marca(marca, hoje, cache_deps):
    nome, dominio, plataforma = marca["nome"], marca["dominio"], marca["plataforma"]
    estado = {"declarado": 0, "truncou": False, "erro": None}
    vistos = set()
    buffer = []
    visitados = gravados = campos_ok = 0

    def descarregar():
        nonlocal gravados, campos_ok, buffer
        if buffer:
            g, c = gravar_lote(marca["id"], buffer, hoje)
            gravados += g
            campos_ok += c
            buffer = []

    if plataforma == "vtex":
        if not robots_permite(dominio, "/api/catalog_system/pub/products/search")[0]:
            return {"marca_id": marca["id"], "nome": nome, "plataforma": plataforma,
                    "visitados": 0, "gravados": 0, "declarado": None,
                    "pct_campos_ok": None, "alertas": {"erro": "robots proibe a busca"}}
        deps, erro = vtex_departamentos_femininos(dominio, nome, cache_deps)
        if erro:
            estado["erro"] = erro
            deps = []
        for cat_id, _nome in deps:
            for p in vtex_departamento(dominio, cat_id, estado):
                d = vtex_extrair(p)
                if not d["id_externo"] or d["id_externo"] in vistos:
                    continue
                vistos.add(d["id_externo"])
                visitados += 1
                buffer.append(d)
                if len(buffer) >= BLOCO_ESCRITA:
                    descarregar()
    elif plataforma == "shopify":
        for p in shopify_todos(dominio, estado):
            d = shopify_extrair(p)
            if not d["id_externo"] or d["id_externo"] in vistos:
                continue
            vistos.add(d["id_externo"])
            visitados += 1
            buffer.append(d)
            if len(buffer) >= BLOCO_ESCRITA:
                descarregar()
    else:
        return None
    descarregar()

    alertas = {}
    if estado["erro"]:
        alertas["erro"] = estado["erro"]
    if estado["truncou"]:
        alertas["truncou"] = "faixa de preco indivisivel acima de 2500; parte do catalogo pode ter sido cortada"
    declarado = estado["declarado"] or None
    if plataforma == "vtex" and declarado and visitados < declarado * 0.98:
        alertas["divergencia"] = {"declarado": declarado, "coletado": visitados,
                                  "obs": "coletado < declarado; ver truncamento ou multi-categoria"}
    pct = round(campos_ok / visitados, 3) if visitados else None
    return {"marca_id": marca["id"], "nome": nome, "plataforma": plataforma,
            "visitados": visitados, "gravados": gravados, "declarado": declarado,
            "pct_campos_ok": pct, "alertas": alertas or None}


# ---------------------------------------------------------------------------
# Saude (§20 + K9)
# ---------------------------------------------------------------------------

def escrever_saude(hoje, metricas):
    for m in metricas:
        supabase_rest.upsert("saude", [{
            "data": hoje.isoformat(), "fonte": "varejo", "marca_id": m["marca_id"],
            "visitados": m["visitados"], "gravados": m["gravados"], "itens": m["visitados"],
            "total_declarado": m["declarado"], "pct_campos_ok": m["pct_campos_ok"],
            "alertas": m["alertas"],
        }], on_conflict="data,fonte,marca_id")

    tot_vis = sum(m["visitados"] for m in metricas)
    tot_grav = sum(m["gravados"] for m in metricas)
    zero = [m for m in metricas if m["visitados"] == 0]

    linhas = ["# SAÚDE — coletores do Canário\n",
              "**Última coleta (UTC):** {}\n".format(datetime.now(timezone.utc).isoformat()),
              "\n## Varejo\n",
              "- Produtos **visitados**: {}\n".format(tot_vis),
              "- Snapshots **gravados** (delta, B3): {}\n".format(tot_grav),
              "- Marcas coletando: {} de {}\n".format(len(metricas) - len(zero), len(metricas))]
    if zero:
        linhas.append("\n> ⚠️ Zero itens (alerta imediato, §20): {}\n".format(
            ", ".join(m["nome"] for m in zero)))
    linhas.append("\n| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |")
    linhas.append("|---|---|---|---|---|---|---|")
    for m in sorted(metricas, key=lambda x: -x["visitados"]):
        linhas.append("| {} | {} | {} | {} | {} | {} | {} |".format(
            m["nome"], m["plataforma"], m["visitados"], m["gravados"],
            m["declarado"] if m["declarado"] else "—",
            m["pct_campos_ok"] if m["pct_campos_ok"] is not None else "—",
            json.dumps(m["alertas"], ensure_ascii=False) if m["alertas"] else "—"))
    linhas.append("\n---\n")
    linhas.append("*Declarado* é a soma dos totais de departamento no header `resources` da VTEX; "
                  "*visitados* são produtos distintos após dedup. Divergência acima de 2% vira alerta (condição 2.3). "
                  "Se *visitados* e *gravados* convergirem dia após dia, é bug no delta (B3).\n")
    with open(SAUDE_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    print("Materializando anexos...", file=sys.stderr)
    materializar_anexos.materializar_marcas()
    materializar_anexos.materializar_termos()

    filtro = os.environ.get("COLETA_MARCA", "").strip()  # particionar por marca se preciso
    marcas = supabase_rest.selecionar(
        "marcas",
        "?status_teste=in.(vtex,shopify)&ativa=eq.true&select=id,nome,dominio,plataforma&order=nome")
    if filtro:
        marcas = [m for m in marcas if m["nome"].lower() == filtro.lower()]
    print("Marcas a coletar: {}{}".format(
        len(marcas), " (filtro: {})".format(filtro) if filtro else ""), file=sys.stderr)

    hoje = date.today()
    metricas = []
    cache_deps = _carregar_cache_departamentos()
    conhecidas = sum(1 for k in cache_deps if not k.startswith("_"))
    print("Departamentos em cache: {} marcas".format(conhecidas), file=sys.stderr)
    # Disjuntor (regra 7): se a VTEX devolve 429 em marcas seguidas, é rate-limit
    # de range do IP; insistir nas 12 é justamente o que a regra 7 proíbe. Após
    # LIMITE_429 marcas VTEX seguidas com 429, aborta o resto do VTEX. Shopify
    # (outra infra) continua.
    LIMITE_429 = 3
    vtex_429_seguidos = 0
    vtex_abortado = False
    for marca in marcas:
        eh_vtex = marca.get("plataforma") == "vtex"
        if eh_vtex and vtex_abortado:
            metricas.append({"marca_id": marca["id"], "nome": marca["nome"],
                             "plataforma": "vtex", "visitados": 0, "gravados": 0,
                             "declarado": None, "pct_campos_ok": None,
                             "alertas": {"disjuntor": "pulada: VTEX em 429 (rate-limit de range); nao insistir (regra 7)"}})
            continue
        t0 = time.monotonic()
        try:
            m = coletar_marca(marca, hoje, cache_deps)
        except Exception as e:
            import traceback
            traceback.print_exc()
            m = {"marca_id": marca["id"], "nome": marca["nome"],
                 "plataforma": marca.get("plataforma"), "visitados": 0, "gravados": 0,
                 "declarado": None, "pct_campos_ok": None,
                 "alertas": {"excecao": "{}: {}".format(type(e).__name__, str(e)[:200])}}
        if m:
            metricas.append(m)
            print("  {:14} visit={} grav={} decl={} ({:.0f}s) {}".format(
                m["nome"], m["visitados"], m["gravados"], m["declarado"],
                time.monotonic() - t0, m["alertas"] or ""), file=sys.stderr)
            if eh_vtex:
                erro = (m.get("alertas") or {}).get("erro", "")
                if "429" in str(erro):
                    vtex_429_seguidos += 1
                    if vtex_429_seguidos >= LIMITE_429:
                        vtex_abortado = True
                        print("  DISJUNTOR: VTEX em 429 por {} marcas seguidas; "
                              "abortando o resto do VTEX (regra 7).".format(LIMITE_429),
                              file=sys.stderr)
                elif m["visitados"] > 0:
                    vtex_429_seguidos = 0

    # Salva antes da saude: uma arvore descoberta hoje e o que evita a
    # redescoberta amanha, e nao pode se perder se a saude falhar.
    _salvar_cache_departamentos(cache_deps)
    if metricas:
        escrever_saude(hoje, metricas)
    print("Coleta concluída.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
