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
import re
import sys
import threading
import time
import urllib.parse
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar, robots_permite  # noqa: E402
from mapa_categorias import (classificar, classificar_populacao,  # noqa: E402
                             loja_so_feminina)
import supabase_rest  # noqa: E402
import materializar_anexos  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAUDE_MD = os.path.join(RAIZ, "SAUDE.md")
CACHE_DEPS = os.path.join(RAIZ, "anexos", "departamentos_vtex.json")

# A arvore de categorias e o endpoint mais limitado da VTEX: em 29/07 devolveu
# 429 em 4 tentativas ao longo de 408s enquanto a busca de produtos respondia
# 206 no mesmo dominio. Paciencia nao resolve; por isso duas tentativas curtas
# e, falhando, o caminho alternativo por produtos.
ESPERAS_ARVORE = [0, 45]

# Termos de sonda para descobrir departamentos pela BUSCA (nao pela arvore).
# Cobrem as categorias da taxonomia, para nenhum departamento feminino ficar
# invisivel so porque a marca nao vende aquela peca.
TERMOS_SONDA = ["vestido", "blusa", "calca", "saia", "camisa", "short",
                "casaco", "macacao"]

PAGINA = 50             # janela do header Range da VTEX
TETO_OFFSET = 2500      # a VTEX corta o offset em 2500 por consulta
BLOCO_ESCRITA = 500     # linhas por upsert em lote
BLOCO_LEITURA = 120     # id_externos por filtro in.()
LIMITE_GLOBAL = 1.0     # regra 7 emendada: 1 req/s GLOBAL
BACKOFF_429 = 60        # um unico retry longo (decisao do JP)
BACKOFF_5XX = 5         # recusa transitoria do backend, uma unica repeticao
PRECO_TETO = 200000     # teto de preco para o particionamento (R$)
NIVEL_MAXIMO = 4        # profundidade maxima da arvore de categorias da VTEX
FUSO_OPERACIONAL = ZoneInfo("America/Sao_Paulo")

_trava = threading.Lock()
_ultima = [0.0]


def data_operacional(agora=None):
    """Data de negocio em Sao Paulo, independente do fuso do runner."""
    agora = agora or datetime.now(FUSO_OPERACIONAL)
    return agora.astimezone(FUSO_OPERACIONAL).date()


def _ritmo():
    with _trava:
        espera = LIMITE_GLOBAL - (time.monotonic() - _ultima[0])
        if espera > 0:
            time.sleep(espera)
        _ultima[0] = time.monotonic()


def buscar_varejo(url, dominio):
    """buscar() com teto GLOBAL e uma unica repeticao de falha transitoria."""
    _ritmo()
    codigo, corpo, final, cab = buscar(url, dominio)
    if codigo == 429:
        time.sleep(BACKOFF_429)
        _ritmo()
        codigo, corpo, final, cab = buscar(url, dominio)
    elif codigo is not None and 500 <= codigo <= 599:
        time.sleep(BACKOFF_5XX)
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
    codigo = corpo = None
    for espera in ESPERAS_ARVORE:
        if espera:
            time.sleep(espera)
        _ritmo()
        codigo, corpo, _, _ = buscar(url, dominio)
        if codigo in (200, 206) and corpo:
            break

    brutos, origem = [], ""
    if codigo in (200, 206) and corpo:
        try:
            brutos = [(no["id"], no.get("name") or "")
                      for no in json.loads(corpo) if no.get("id")]
            origem = "arvore"
        except ValueError:
            brutos = []
    if not brutos:
        brutos = _departamentos_por_produtos(dominio)
        origem = "busca"
    if not brutos:
        return None, "arvore http {} e a busca nao revelou departamentos".format(codigo)

    # Numa loja so de moda feminina, vitrine de topo ("Bazar") e segura e
    # carrega o sinal de encalhe da §23. Numa loja multi-publico, a mesma
    # vitrine misturaria masculino e infantil: fica fora.
    so_feminina = loja_so_feminina([n for _, n in brutos])
    regra = classificar_populacao if so_feminina else classificar
    deps = [(i, n) for i, n in brutos if regra(n)[0] == "sim"]
    if deps:
        cache[marca_nome] = [{"id": i, "nome": n, "origem": origem,
                              "loja_so_feminina": so_feminina} for i, n in deps]
    return deps, ""


def _departamentos_por_produtos(dominio):
    """Descobre departamentos de nivel 1 pela BUSCA, sem tocar na arvore.

    Cada produto da VTEX traz `categories` e `categoriesIds` pareados, do mais
    especifico ao mais geral:
        categories    ['/Vestidos/Longos/', '/Vestidos/', '/Bazar/']
        categoriesIds ['/65/67/',           '/65/',       '/141/']
    O nivel 1 e o caminho de um segmento so. Como a busca de produtos responde
    206 quando a arvore devolve 429, este e o caminho que sobrevive ao
    rate-limit -- e usa exatamente o endpoint que o coletor ja usaria depois.
    """
    vistos = {}
    for termo in TERMOS_SONDA:
        url = ("https://{}/api/catalog_system/pub/products/search/{}"
               "?_from=0&_to=9".format(dominio, termo))
        codigo, corpo, _, _ = buscar_varejo(url, dominio)
        if codigo not in (200, 206) or not corpo:
            continue
        try:
            produtos = json.loads(corpo)
        except ValueError:
            continue
        for p in produtos:
            caminhos = p.get("categories") or []
            ids = p.get("categoriesIds") or []
            for caminho, id_caminho in zip(caminhos, ids):
                nomes = [x for x in caminho.strip("/").split("/") if x]
                numeros = [x for x in id_caminho.strip("/").split("/") if x]
                if len(nomes) == 1 and len(numeros) == 1:
                    try:
                        vistos[int(numeros[0])] = nomes[0]
                    except ValueError:
                        pass
    return sorted(vistos.items())


def _fq_preco(pmin, pmax):
    """Filtro de faixa de preco da VTEX, com a URL codificada.

    O espaco cru em `P:[0 TO 200000]` invalida a URL e a requisicao nem chega a
    sair (urlopen levanta antes da rede). O sintoma era silencioso e caro: toda
    marca com mais de 2500 produtos -- que e justamente quando a particao por
    preco entra -- coletava ZERO, com o total declarado correto ao lado.
    """
    if pmin is None:
        return ""
    return "&fq=" + urllib.parse.quote("P:[{} TO {}]".format(pmin, pmax))


def _fq_disponibilidade(somente_ofertaveis):
    """Filtro nativo da VTEX para SKUs compraveis no sales channel publico.

    A busca Legacy indexa produto indisponivel com preco zero. Na C&A isso
    concentra dezenas de milhares de itens antigos em ``P:[0 TO 1]``, embora
    o payload ainda carregue o ultimo preco comercial. Eles nao sao ofertas e
    nao podem obrigar o coletor a truncar justamente os itens compraveis.
    """
    return "&fq=isAvailablePerSalesChannel_1:1" if somente_ofertaveis else ""


def _registrar_erro_vtex(estado, mensagem):
    """Preserva o primeiro diagnóstico que explica uma coleta VTEX vazia.

    Uma falha de contagem encerrava o gerador sem lançar exceção. O resultado
    chegava à saúde como zero com ``alertas=None`` e o portão, corretamente,
    bloqueava por não saber o motivo. Guardar o primeiro erro mantém a causa
    original mesmo que tentativas de reparo posteriores também falhem.
    """
    if estado is not None and not estado.get("erro"):
        estado["erro"] = mensagem


def _contar(dominio, cat_id, pmin=None, pmax=None, estado=None,
            somente_ofertaveis=False):
    """Conta produtos de uma categoria. `cat_id` pode ser um id ou um CAMINHO
    de ids ("1000003/1004161") -- ver a nota em `_paginar`."""
    url = ("https://{}/api/catalog_system/pub/products/search"
           "?fq=C:{}{}{}&_from=0&_to=0".format(
               dominio, cat_id, _fq_preco(pmin, pmax),
               _fq_disponibilidade(somente_ofertaveis)))
    codigo, _, _, cab = buscar_varejo(url, dominio)
    if codigo not in (200, 206):
        _registrar_erro_vtex(
            estado, "http {} ao contar categoria VTEX {}".format(
                codigo, cat_id))
        return None
    total = _total_do_header(cab)
    if total is None:
        _registrar_erro_vtex(
            estado, "resposta VTEX sem header Resources na categoria {}".format(
                cat_id))
        return None
    return total


def _paginar(dominio, cat_id, limite, pmin=None, pmax=None, estado=None,
             somente_ofertaveis=False):
    """Pagina uma categoria.

    `cat_id` e id de departamento OU caminho completo de ids para subcategoria.
    A VTEX exige o caminho: na C&A, `fq=C:1004161` devolve 0 e
    `fq=C:1000003/1004161` devolve 89.354 para a mesma categoria "Roupas".
    """
    alvo = min(limite, TETO_OFFSET)
    vistos = set()

    # A ordenacao por PRECO parecia deterministica, mas nao define desempate.
    # Numa pagina de 50 produtos com o mesmo preco, a VTEX mudava a ordem entre
    # requisicoes e repetia produtos nas paginas seguintes. Em 11/08 isso fez
    # Farm declarar 2.829 produtos e entregar apenas 766 ids unicos; a NV caiu
    # de 903 para 416 pela mesma causa. Nome tem cardinalidade muito maior e e
    # uma ordem oficial da Search API. DESC e uma segunda passagem de reparo:
    # so roda se ASC nao recuperar 98% do que o header declarou.
    for ordem in ("OrderByNameASC", "OrderByNameDESC"):
        de = 0
        while de < alvo and len(vistos) < alvo:
            ate = min(de + PAGINA - 1, alvo - 1)
            url = ("https://{}/api/catalog_system/pub/products/search"
                   "?fq=C:{}{}{}&O={}&_from={}&_to={}".format(
                       dominio, cat_id, _fq_preco(pmin, pmax),
                       _fq_disponibilidade(somente_ofertaveis), ordem, de, ate))
            codigo, corpo, _, _ = buscar_varejo(url, dominio)
            if codigo not in (200, 206):
                _registrar_erro_vtex(
                    estado,
                    "http {} ao paginar categoria VTEX {} ({}-{}, {})".format(
                        codigo, cat_id, de, ate, ordem))
                break
            if not corpo:
                _registrar_erro_vtex(
                    estado,
                    "resposta vazia ao paginar categoria VTEX {} "
                    "({}-{}, {})".format(cat_id, de, ate, ordem))
                break
            try:
                produtos = json.loads(corpo)
            except ValueError:
                _registrar_erro_vtex(
                    estado,
                    "resposta nao-json ao paginar categoria VTEX {} "
                    "({}-{}, {})".format(cat_id, de, ate, ordem))
                break
            if not produtos:
                if de < alvo:
                    _registrar_erro_vtex(
                        estado,
                        "pagina vazia antes do total declarado na categoria "
                        "VTEX {} ({}-{}, {})".format(
                            cat_id, de, ate, ordem))
                break
            for p in produtos:
                produto_id = str(p.get("productId") or "")
                if not produto_id or produto_id in vistos:
                    continue
                vistos.add(produto_id)
                yield p
                if len(vistos) >= alvo:
                    break
            de += PAGINA
            if len(produtos) < PAGINA:
                break
        if len(vistos) >= alvo * 0.98:
            break
    if len(vistos) < alvo * 0.98:
        _registrar_erro_vtex(
            estado,
            "paginacao VTEX incompleta na categoria {}: {} de {} ids unicos"
            .format(cat_id, len(vistos), alvo))


def _filhos(dominio, caminho):
    """Filhos diretos de um caminho de categoria, descobertos pela busca.

    Funciona em qualquer nivel: `categoriesIds` de um produto e o caminho
    completo ('/1000003/1004161/1004164/'), entao um caminho com um segmento
    a mais que o pai revela o filho. Amostra paginas espalhadas porque a
    primeira pagina traz so o que a vitrine promove.
    """
    partes = [x for x in caminho.split("/") if x]
    n = len(partes)
    vistos = {}
    for de in (0, 400, 900, 1500, 2200):
        # O mesmo desempate instavel por preco que duplicava produtos tambem
        # fazia o conjunto de filhos variar por noite. Nome fixa a amostra.
        url = ("https://{}/api/catalog_system/pub/products/search"
               "?fq=C:{}&O=OrderByNameASC&_from={}&_to={}".format(
                   dominio, caminho, de, de + PAGINA - 1))
        codigo, corpo, _, _ = buscar_varejo(url, dominio)
        if codigo not in (200, 206) or not corpo:
            continue
        try:
            produtos = json.loads(corpo)
        except ValueError:
            continue
        if not produtos:
            break
        for p in produtos:
            for cam, id_cam in zip(p.get("categories") or [],
                                   p.get("categoriesIds") or []):
                nomes = [x for x in cam.strip("/").split("/") if x]
                nums = [x for x in id_cam.strip("/").split("/") if x]
                if len(nums) == n + 1 and nums[:n] == partes:
                    vistos["/".join(nums)] = nomes[n] if len(nomes) > n else ""
    return sorted(vistos.items())


def vtex_departamento(dominio, cat_id, estado):
    """Todos os produtos de um departamento, descendo a arvore ate caber."""
    total = _contar(dominio, str(cat_id), estado=estado)
    if total is None:
        return
    if total == 0:
        # Arvores VTEX antigas continuam publicadas no cadastro mesmo depois
        # de a vitrine migrar para outro departamento. Dress To, por exemplo,
        # ainda declara ``Lovedress`` (28), hoje vazio, ao lado de ``dress to``
        # (58), com todo o catalogo vivo. Um ramo vazio isolado nao e perda.
        # A decisao so pode ser tomada depois de visitar TODOS os ramos: se
        # nenhum devolver produto, `coletar_marca` transforma o conjunto em
        # erro critico e a saude continua bloqueando um catalogo realmente
        # zerado.
        estado.setdefault("categorias_vazias", []).append(str(cat_id))
        return
    yield from _por_categoria(dominio, str(cat_id), estado, total)


def _por_categoria(dominio, caminho, estado, total=None, nivel=1):
    """Pagina uma categoria; se estoura o teto de offset, desce nos filhos.

    Subcategoria e o eixo natural do catalogo. A particao por preco ficou como
    ultimo recurso porque tem limite estrutural: preco de moda se concentra em
    pontos exatos (R$ 199,90), e a faixa [199 TO 200] sozinha estoura o teto
    sem ter como dividir mais -- foi o que truncou o Dress To em 4540 de 7178.
    """
    if total is None:
        total = _contar(dominio, caminho, estado=estado)
    if not total:
        return
    if total <= TETO_OFFSET:
        # `declarado` soma so o que e REALMENTE paginavel e incluido pelo
        # classificador. Somar o total do departamento inflava o denominador
        # com Calcados, Moda Intima e Moda Praia, e o alerta de divergencia
        # acusava perda onde havia exclusao correta.
        estado["declarado"] += total
        yield from _paginar(dominio, caminho, total, estado=estado)
        return

    if nivel < NIVEL_MAXIMO:
        filhos = _filhos(dominio, caminho)
        if filhos:
            for cam, nome in filhos:
                # Dentro de um departamento ja aprovado, exclui-se so por
                # POPULACAO (calcado, moda intima, praia, masculino), nunca por
                # recorte comercial. Excluir "Bazar" aqui derrubou o Dress To de
                # 4540 para 326: 6852 dos 7178 produtos dele vivem no Bazar, e a
                # §23 trata remarcada-com-grade-cheia como o sinal de encalhe.
                if nome and classificar_populacao(nome)[0] != "sim":
                    continue
                yield from _por_categoria(dominio, cam, estado, None, nivel + 1)
            return

    yield from _por_preco(dominio, caminho, estado)


def _por_preco(dominio, cat_id, estado):
    """Ultimo recurso: parte a faixa de preco ao meio ate caber no teto."""
    def particao(pmin, pmax):
        t = _contar(dominio, cat_id, pmin, pmax, estado=estado)
        if not t:
            return
        if t <= TETO_OFFSET:
            estado["declarado"] += t
            yield from _paginar(
                dominio, cat_id, t, pmin, pmax, estado=estado)
        elif pmax - pmin > 1:
            mid = (pmin + pmax) // 2
            yield from particao(pmin, mid)
            yield from particao(mid, pmax)
        else:
            yield from _faixa_indivisivel(
                dominio, cat_id, estado, pmin, pmax, t)

    yield from particao(0, PRECO_TETO)


def _faixa_indivisivel(dominio, cat_id, estado, pmin, pmax, total):
    """Resolve concentração de preço sem sacrificar ofertas observáveis.

    O índice Legacy põe produto sem estoque na faixa zero. Antes, a C&A tinha
    66 mil registros nessa faixa e o coletor guardava só os primeiros 2.500,
    misturando indisponíveis antigos e deixando ofertas compráveis fora por
    ordem alfabética. O filtro oficial de disponibilidade reduz o universo ao
    que a P17 chama de oferta. Ausentes envelhecem em sete dias; não precisam
    de um falso snapshot inventado.
    """
    ofertaveis = _contar(
        dominio, cat_id, pmin, pmax, estado=estado,
        somente_ofertaveis=True)
    if ofertaveis is None:
        return
    if ofertaveis <= TETO_OFFSET:
        estado["declarado"] += ofertaveis
        estado["indisponiveis_fora_do_universo"] = (
            estado.get("indisponiveis_fora_do_universo", 0)
            + max(total - ofertaveis, 0))
        if ofertaveis:
            yield from _paginar(
                dominio, cat_id, ofertaveis, pmin, pmax, estado=estado,
                somente_ofertaveis=True)
        return

    # Se ate as ofertas reais excederem o teto, a perda volta a ser material e
    # precisa continuar visivel na saude. Nao existe outro eixo publico seguro.
    estado["truncou"] = True
    estado["declarado"] += TETO_OFFSET
    estado.setdefault("faixas_truncadas", []).append(
        {"faixa": "{}-{}".format(pmin, pmax), "existem": ofertaveis,
         "coletados": TETO_OFFSET, "somente_ofertaveis": True})
    yield from _paginar(
        dominio, cat_id, TETO_OFFSET, pmin, pmax, estado=estado,
        somente_ofertaveis=True)


DOMINIOS_PUBLICOS_VTEX = {
    # A Search API da Maria Filó vive no host administrativo legado. O campo
    # `link` devolvido por ele aponta para esse mesmo host e termina numa tela
    # de login, embora a rota pública exista no domínio da loja.
    "mariafilo.vtexcommercestable.com.br": "www.mariafilo.com.br",
}


def _url_publica_vtex(p, dominio):
    """Converte uma rota de catálogo VTEX numa URL que o cliente pode abrir."""
    host = DOMINIOS_PUBLICOS_VTEX.get(dominio, dominio)
    link_text = str(p.get("linkText") or "").strip("/")
    if link_text:
        return "https://{}/{}/p".format(host, link_text)
    url = p.get("link") or None
    if url and host != dominio:
        partes = urllib.parse.urlsplit(url)
        return urllib.parse.urlunsplit(("https", host, partes.path,
                                        partes.query, partes.fragment))
    return url


def vtex_extrair(p, dominio=None):
    itens = p.get("items") or []
    grade = {}
    preco_atual = preco_orig = None
    preco_fallback = preco_orig_fallback = None
    ofertavel = False
    for it in itens:
        tamanho = None
        for v in (it.get("variations") or []):
            if isinstance(v, str) and "tam" in v.lower():
                vals = it.get(v) or []
                tamanho = vals[0] if vals else None
        sellers = it.get("sellers") or []
        disponivel = False
        for seller in sellers:
            oferta = seller.get("commertialOffer") or {}
            esta_disponivel = (bool(oferta.get("IsAvailable"))
                               and (oferta.get("AvailableQuantity", 0) or 0) > 0)
            disponivel = disponivel or esta_disponivel
            ofertavel = ofertavel or esta_disponivel
            # O preco de seller indisponivel continua util como contexto de
            # historico e saude, mas NUNCA decide `ofertavel`. Havendo seller
            # compravel, seu preco prevalece sobre o fallback cadastrado.
            if preco_fallback is None and oferta.get("Price"):
                preco_fallback = oferta.get("Price")
                preco_orig_fallback = (oferta.get("ListPrice")
                                       or oferta.get("Price"))
            if esta_disponivel and preco_atual is None and oferta.get("Price"):
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
    if preco_atual is None:
        preco_atual, preco_orig = preco_fallback, preco_orig_fallback
    return {
        "id_externo": str(p.get("productId") or ""),
        "url": _url_publica_vtex(p, dominio) if dominio else (p.get("link") or None),
        "titulo": p.get("productName"),
        "categoria_site": (p.get("categories") or [None])[0],
        "imagem_url": imagem,
        "preco_original": preco_orig,
        "preco_atual": preco_atual,
        "composicao": composicao,
        "grade_por_tamanho": grade or None,
        "ofertavel": ofertavel,
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


def _posicao_do_tamanho(produto):
    """Qual das opcoes do produto e o TAMANHO.

    Shopify entrega `options: [{name, position}, ...]` e as variantes trazem
    `option1..3` alinhadas a essas posicoes. Nao ha garantia de que a primeira
    seja tamanho.

    Isto existe porque o coletor pegava `option1` as cegas. Na Amaro a primeira
    opcao e COR, e 335 produtos entraram no banco com a grade preenchida de
    "PRETO", "MARROM", "BEGE" no lugar dos tamanhos. O caminho VTEX ja fazia
    certo -- procurava a variacao cujo nome contem "tam" -- e o Shopify nao.
    """
    for op in (produto.get("options") or []):
        nome = (op.get("name") or "").strip().lower()
        if "tam" in nome or nome in ("size", "talla"):
            pos = op.get("position")
            if isinstance(pos, int) and 1 <= pos <= 3:
                return pos
    # Sem opcao de tamanho declarada: produto de tamanho unico, ou loja que nao
    # nomeia as opcoes. Melhor nao ter grade do que ter grade de cor.
    return None


def shopify_extrair(p):
    grade = {}
    preco_atual = preco_orig = None
    preco_fallback = preco_orig_fallback = None
    ofertavel = False
    posicao = _posicao_do_tamanho(p)
    for v in (p.get("variants") or []):
        disponivel = bool(v.get("available"))
        ofertavel = ofertavel or disponivel
        tamanho = v.get("option{}".format(posicao)) if posicao else None
        if tamanho:
            chave = str(tamanho)
            grade[chave] = grade.get(chave, False) or disponivel
        if preco_fallback is None and v.get("price"):
            try:
                preco_fallback = float(v.get("price"))
                preco_orig_fallback = float(
                    v.get("compare_at_price") or v.get("price"))
            except (TypeError, ValueError):
                pass
        if disponivel and preco_atual is None and v.get("price"):
            try:
                preco_atual = float(v.get("price"))
                preco_orig = float(v.get("compare_at_price") or v.get("price"))
            except (TypeError, ValueError):
                pass
    if preco_atual is None:
        preco_atual, preco_orig = preco_fallback, preco_orig_fallback
    imagem = p["images"][0].get("src") if p.get("images") else None
    handle = p.get("handle")
    return {
        "id_externo": str(p.get("id") or ""),
        "url": ("https://{}/products/{}".format(p.get("_dominio", ""), handle) if handle else None),
        "titulo": p.get("title"),
        "categoria_site": p.get("product_type"),
        "imagem_url": imagem,
        "preco_original": preco_orig,
        "preco_atual": preco_atual,
        "composicao": None,
        "grade_por_tamanho": grade or None,
        "ofertavel": ofertavel,
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
    # NULL legado significa desconhecido, nao indisponivel. A primeira coleta
    # depois da P17 precisa abrir um snapshot mesmo quando concluir false.
    if d.get("ofertavel") != ex.get("ofertavel"):
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


def _produto_mudou(d, ex):
    """Só regrava a linha larga quando algum estado durável mudou."""
    if ex is None:
        return True
    pares = (
        ("url", "url"), ("titulo", "titulo"),
        ("categoria_site", "categoria_site"), ("imagem_url", "imagem_url"),
        ("preco_atual", "ultimo_preco_atual"),
        ("preco_original", "ultimo_preco_original"),
        ("grade_por_tamanho", "ultima_grade"),
    )
    for novo, antigo in pares:
        if (d.get(novo) or None) != (ex.get(antigo) or None):
            return True
    return False


def gravar_lote(marca_id, coletados, hoje):
    """Grava um bloco de produtos coletados. Devolve (gravados, campos_ok)."""
    if not coletados:
        return 0, 0

    existentes = {}
    ids = [d["id_externo"] for d in coletados]
    for sub in _pedacos(ids, BLOCO_LEITURA):
        lista = ",".join('"{}"'.format(i) for i in sub)
        params = ("?marca_id=eq.{}&id_externo=in.({})"
                  "&select=id,id_externo,url,titulo,categoria_site,imagem_url,"
                  "ultimo_preco_atual,ultimo_preco_original,ultima_grade,"
                  "primeiro_avistamento".format(marca_id, lista))
        for r in supabase_rest.selecionar("produtos", params):
            existentes[r["id_externo"]] = r

    ids_produto = [r["id"] for r in existentes.values()]
    existente_por_id = {r["id"]: r for r in existentes.values()}
    for sub in _pedacos(ids_produto, BLOCO_LEITURA):
        lista = ",".join(str(i) for i in sub)
        params = ("?produto_id=in.({})&select=produto_id,ultimo_snapshot_em,"
                  "ultimo_avistamento_em,ofertavel".format(lista))
        for estado in supabase_rest.selecionar("estado_dos_produtos", params):
            ex = existente_por_id.get(estado["produto_id"])
            if ex is not None:
                ex.update(estado)

    prod_rows, estado_alvo, snap_alvo = [], [], []
    campos_ok = 0
    for d in coletados:
        ex = existentes.get(d["id_externo"])
        escreve = _precisa_snapshot(d, ex, hoje)
        campos_ok += 1 if (d["preco_atual"] is not None and d["grade_por_tamanho"] and d["titulo"]) else 0
        produto = {
            "marca_id": marca_id,
            "id_externo": d["id_externo"],
            "url": d["url"],
            "titulo": d["titulo"],
            "categoria_site": d["categoria_site"],
            "imagem_url": d["imagem_url"],
            "primeiro_avistamento": (ex.get("primeiro_avistamento") if ex else hoje.isoformat()) or hoje.isoformat(),
            "ultimo_preco_atual": d["preco_atual"],
            "ultimo_preco_original": d["preco_original"],
            "ultima_grade": d["grade_por_tamanho"],
        }
        if _produto_mudou(d, ex):
            prod_rows.append(produto)
        estado_alvo.append((d, escreve, ex))
        if escreve:
            snap_alvo.append(d)

    id_por_externo = {chave: valor["id"] for chave, valor in existentes.items()}
    for bloco in _pedacos(prod_rows, BLOCO_ESCRITA):
        ret = supabase_rest.upsert("produtos", bloco,
                                   on_conflict="marca_id,id_externo", retornar=True)
        for r in ret:
            id_por_externo[r["id_externo"]] = r["id"]

    estado_rows = []
    for d, escreve, ex in estado_alvo:
        pid = id_por_externo.get(d["id_externo"])
        if pid is None:
            continue
        estado_rows.append({
            "produto_id": pid,
            "ultimo_avistamento_em": hoje.isoformat(),
            "ofertavel": bool(d.get("ofertavel")),
            "ultimo_snapshot_em": (hoje.isoformat() if escreve else
                                    (ex.get("ultimo_snapshot_em") if ex else hoje.isoformat())),
        })
    for bloco in _pedacos(estado_rows, BLOCO_ESCRITA):
        supabase_rest.upsert("estado_dos_produtos", bloco,
                             on_conflict="produto_id")

    snap_rows = []
    for d in snap_alvo:
        pid = id_por_externo.get(d["id_externo"])
        if pid is None:
            continue
        snap_rows.append({
            "produto_id": pid, "data": hoje.isoformat(),
            "preco_original": d["preco_original"], "preco_atual": d["preco_atual"],
            "composicao": d["composicao"], "grade_por_tamanho": d["grade_por_tamanho"],
            "ofertavel": bool(d.get("ofertavel")),
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
                d = vtex_extrair(p, dominio)
                if not d["id_externo"] or d["id_externo"] in vistos:
                    continue
                vistos.add(d["id_externo"])
                visitados += 1
                buffer.append(d)
                if len(buffer) >= BLOCO_ESCRITA:
                    descarregar()
        if not visitados and estado.get("categorias_vazias") and not estado["erro"]:
            _registrar_erro_vtex(
                estado,
                "catalogo VTEX declarou zero em todas as categorias {}".format(
                    ", ".join(estado["categorias_vazias"])))
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
    # Totais de departamentos nao sao somaveis: na NV, Roupas (415), New In
    # (563) e Linhas (351) sao vitrines sobrepostas cuja uniao tem 563 ids, nao
    # 1.329. Se todas as consultas terminaram, `vistos` e o total exato da
    # uniao; so preservamos a soma como limite diagnostico quando houve falha.
    if (plataforma == "vtex" and visitados and not estado["truncou"]
            and not estado["erro"]):
        estado["declarado"] = visitados
    declarado = estado["declarado"] or None
    if estado.get("indisponiveis_fora_do_universo"):
        alertas["indisponiveis_fora_do_universo"] = (
            estado["indisponiveis_fora_do_universo"])
    if estado.get("faixas_truncadas"):
        alertas["faixas_truncadas"] = estado["faixas_truncadas"][:5]
    if plataforma == "vtex" and declarado and visitados < declarado * 0.98:
        alertas["divergencia"] = {
            "paginavel": declarado, "coletado": visitados,
            "obs": "coletado < paginavel; o normal e dedup (produto em duas "
                   "categorias). Perda real aparece em faixas_truncadas."}
    pct = round(campos_ok / visitados, 3) if visitados else None
    return {"marca_id": marca["id"], "nome": nome, "plataforma": plataforma,
            "visitados": visitados, "gravados": gravados, "declarado": declarado,
            "pct_campos_ok": pct, "alertas": alertas or None}


# ---------------------------------------------------------------------------
# Saude (§20 + K9)
# ---------------------------------------------------------------------------

def escrever_saude(hoje, metricas):
    """Grava a saude no banco e RE-RENDERIZA o SAUDE.md a partir dele.

    Renderizar do banco, e nao das metricas em memoria, e o que permite duas
    coletas independentes no mesmo dia (VTEX no datacenter, Shopify no runner
    residencial) sem uma apagar o relatorio da outra.
    """
    for m in metricas:
        supabase_rest.upsert("saude", [{
            "data": hoje.isoformat(), "fonte": "varejo", "marca_id": m["marca_id"],
            "visitados": m["visitados"], "gravados": m["gravados"], "itens": m["visitados"],
            "total_declarado": m["declarado"], "pct_campos_ok": m["pct_campos_ok"],
            "alertas": m["alertas"],
        }], on_conflict="data,fonte,marca_id")
    renderizar_saude(hoje, metricas)


def _valor_de_saude(linha):
    """Métrica de volume comparável dentro de cada fonte.

    A métrica precisa ter UNIDADE ESTÁVEL, e não só ser um número grande.

    Em 06/08 o portão bloqueou o pipeline com "busca caiu 87% contra a média
    de 7 dias (462 vs 3626)". A coleta tinha funcionado: os mesmos 3 grupos
    responderam, os mesmos termos foram gravados. O que mudou foi a janela do
    Trends — de 5 anos semanais (261 pontos por termo) para 240 dias diários
    (34 pontos por termo). Mesmo trabalho, um oitavo dos pontos.

    O portão estava certo em existir e errado no que media: `itens` conta
    PONTOS, e ponto é unidade de janela, não de cobertura. Trocar a janela é
    decisão de método e não pode acender alarme de coleta quebrada — alarme
    que grita quando nada está errado é alarme que se aprende a ignorar.

    Para a busca a pergunta certa é quantos grupos responderam. Medido nos
    mesmos dias em que `itens` variou de 408 a 7308, `gravados` ficou em
    3, 3, 4, 2, 7 — sobe e desce com a rotação, não com o tamanho da janela.
    """
    if linha.get("fonte") == "varejo":
        return linha.get("visitados") or 0
    if linha.get("fonte") == "busca":
        return linha.get("gravados") or 0
    if linha.get("itens") is not None:
        return linha.get("itens") or 0
    return linha.get("gravados") or 0


#: A loja pode recusar hoje e voltar amanhã. Abaixo disto o zero é ruído
#: operacional e vira aviso; a partir daqui é achado e bloqueia.
DIAS_DE_ZERO_PARA_BLOQUEAR = 3


def _zeros_seguidos(historico, hoje_iso):
    """Há quantos dias seguidos, contando hoje, esta fonte está em zero."""
    seguidos = 0
    for data in sorted(historico, reverse=True):
        if data > hoje_iso or historico[data] > 0:
            break
        seguidos += 1
    return seguidos


def alertas_criticos(registros, marcas_ativas, hoje):
    """Detecta ausência, zero PERSISTENTE e queda >70% contra os 7 dias.

    O QUE MUDOU EM 10/08, E POR QUÊ
    ===============================

    O portão derrubava o pipeline inteiro porque UMA loja teve um dia ruim. Nos
    dias 09 e 10/08 o motivo foi `http 429 (persistiu apos backoff longo)` da
    Amaro — a loja nos pedindo para diminuir, que é o que a regra 7 manda
    respeitar, e não uma coleta quebrada.

    Medido em 9 dias: Amaro 8 dias bons e 2 zerados; PatBo 8 bons e 2 zerados,
    **e recuperou sozinha**. Zero de um dia é ruído; falhar a noite inteira por
    causa dele é gritar quando não há nada errado — e alarme assim é o que
    ensina a ignorar alarme.

    A distinção que passa a valer:

    * zero **com motivo HTTP registrado** e por menos de
      `DIAS_DE_ZERO_PARA_BLOQUEAR` dias seguidos → a fonte recusou. Vira aviso.
    * zero **sem motivo nenhum** → não sabemos o que houve, e não saber é pior
      que saber que foi recusa. Bloqueia na hora.
    * zero por 3 dias seguidos → não é mais um dia ruim. Bloqueia.

    Devolve `(criticos, avisos)`: só os críticos travam o pipeline.
    """
    hoje_iso = hoje.isoformat()
    atuais = {}
    anteriores = {}
    historico = {}
    for r in sorted(registros,
                    key=lambda x: (x.get("criado_em") or "", x.get("id") or 0)):
        chave = (r.get("fonte"), r.get("marca_id"))
        if r.get("data") == hoje_iso:
            atuais[chave] = r
        else:
            anteriores.setdefault(chave, []).append(_valor_de_saude(r))
        if r.get("data"):
            historico.setdefault(chave, {})[r["data"]] = _valor_de_saude(r)

    esperadas = {("editorial", None), ("busca", None)}
    esperadas.update(("varejo", m["id"]) for m in marcas_ativas)
    criticos, avisos = [], []
    for chave in sorted(esperadas, key=lambda x: (x[0], x[1] or 0)):
        fonte, marca_id = chave
        atual = atuais.get(chave)
        nome = next((m["nome"] for m in marcas_ativas
                     if m["id"] == marca_id), None)
        rotulo = "varejo/{}".format(nome) if nome else fonte
        if atual is None:
            criticos.append("{} sem observacao hoje".format(rotulo))
            continue
        valor = _valor_de_saude(atual)
        if valor <= 0:
            alertas_da_linha = (atual.get("alertas")
                                if isinstance(atual.get("alertas"), dict)
                                else {})
            if (fonte == "busca" and
                    alertas_da_linha.get("adiado_por_cadencia")):
                avisos.append(
                    "busca não consultada hoje: séries já estavam em dia")
                continue
            motivo = ((atual.get("alertas") or {}).get("erro")
                      if isinstance(atual.get("alertas"), dict) else None)
            seguidos = _zeros_seguidos(historico.get(chave, {}), hoje_iso)
            motivo_http = bool(re.search(
                r"\bhttp\s+(?:429|5\d\d)\b", str(motivo or ""),
                flags=re.IGNORECASE))
            if not motivo:
                criticos.append(
                    "{} retornou zero sem dizer por quê".format(rotulo))
            elif not motivo_http:
                criticos.append(
                    "{} retornou zero por erro nao HTTP ({})".format(
                        rotulo, motivo))
            elif seguidos >= DIAS_DE_ZERO_PARA_BLOQUEAR:
                criticos.append("{} em zero há {} dias seguidos ({})".format(
                    rotulo, seguidos, motivo))
            else:
                avisos.append("{} retornou zero hoje ({}); {}º dia".format(
                    rotulo, motivo, seguidos))
            continue
        base = [v for v in anteriores.get(chave, []) if v > 0]
        if base:
            media = sum(base) / float(len(base))
            if valor < media * 0.30:
                criticos.append(
                    "{} caiu {:.0f}% contra a media de 7 dias ({} vs {:.0f})".format(
                        rotulo, 100 * (1 - valor / media), valor, media))
    return criticos, avisos


# COBERTURA NAO E VOLUME, E ATE 18/08/2026 O RELATORIO SO MEDIA VOLUME
# ====================================================================
#
# Naquele dia a C&A entregou 16.489 produtos: volume normal, nenhuma queda
# contra os sete dias, portao verde, "sem alerta critico" impresso na mesma
# pagina em que quatro faixas de preco apareciam truncadas em 2.500. As duas
# frases estavam certas e juntas davam a impressao errada -- o pipeline rodou,
# mas o catalogo do dia nao veio inteiro, e quem lia concluia que o dado
# sustentava o que o app mostra.
#
# O estado abaixo NAO bloqueia o pipeline. Bloquear exige responder "quanto de
# catalogo faltando torna o dia inutil", e esse numero e decisao de metodo do
# JP. Medir nao e: sem a medida nao ha como decidir, e era por isso que o item
# estava parado. Quando o numero existir, vira criterio em `alertas_criticos`.

def cobertura_da_marca(alertas):
    """Diz se o catalogo do dia veio inteiro, separado de ter vindo volume.

    Devolve `(estado, detalhe)`:

    * `completa` -- nada no registro indica corte.
    * `parcial`  -- houve faixa truncada. Nao e suspeita: a propria paginacao
      avisou que parou antes do fim, entao sabemos que ficou produto de fora.
    * `incerta`  -- a contagem falhou (categoria que devolveu erro ou zero).
      Nao da para afirmar corte nem integridade, e chamar isso de `completa`
      seria afirmar mais do que se sabe.

    A perda vem como TETO, nunca como valor exato: as faixas sao contadas por
    categoria e o mesmo produto aparece em mais de uma, entao somar as sobras
    conta gente repetida. Um teto honesto e util; um numero exato inventado
    seria pior que nao ter numero.
    """
    if not isinstance(alertas, dict):
        return "completa", None
    faixas = [f for f in (alertas.get("faixas_truncadas") or [])
              if isinstance(f, dict)]
    erro = alertas.get("erro")
    if faixas:
        perdas = []
        for f in faixas:
            try:
                existem = int(f.get("existem") or 0)
                coletados = int(f.get("coletados") or 0)
            except (TypeError, ValueError):
                continue
            perdas.append(max(0, existem - coletados))
        detalhe = {"faixas": len(faixas),
                   "teto_de_perda": sum(perdas),
                   "pior_faixa": max(perdas) if perdas else 0}
        if erro:
            detalhe["erro"] = str(erro)
        return "parcial", detalhe
    if erro:
        return "incerta", {"erro": str(erro)}
    return "completa", None


def resumo_de_cobertura(metricas):
    """Agrega a cobertura do dia para caber na linha de estado do relatorio."""
    contagem = {"completa": 0, "parcial": 0, "incerta": 0}
    por_marca = []
    for m in metricas:
        estado, detalhe = cobertura_da_marca(m.get("alertas"))
        contagem[estado] += 1
        por_marca.append({"nome": m["nome"], "estado": estado,
                          "detalhe": detalhe})
    return contagem, por_marca


def frase_de_cobertura(contagem):
    """Uma linha que nao deixa 'verde' significar 'catalogo inteiro'."""
    total = sum(contagem.values())
    if not total:
        return "cobertura não medida"
    if contagem["parcial"] or contagem["incerta"]:
        partes = []
        if contagem["parcial"]:
            partes.append("{} com catálogo cortado".format(contagem["parcial"]))
        if contagem["incerta"]:
            partes.append("{} sem contagem confiável".format(
                contagem["incerta"]))
        return "cobertura parcial — {} de {} marcas ({})".format(
            contagem["parcial"] + contagem["incerta"], total,
            "; ".join(partes))
    return "cobertura completa nas {} marcas".format(total)


def metricas_varejo_ativas(atuais, nomes, marcas_ativas):
    """Mantem o relatorio do dia coerente com o escopo operacional atual."""
    ids_ativos = {m["id"] for m in marcas_ativas}
    metricas = []
    for (fonte, marca_id), r in atuais.items():
        if fonte != "varejo" or marca_id not in ids_ativos:
            continue
        nome, plataforma = nomes.get(
            marca_id, ("(id {})".format(marca_id), "?"))
        metricas.append({
            "marca_id": marca_id, "nome": nome, "plataforma": plataforma,
            "visitados": r.get("visitados") or 0,
            "gravados": r.get("gravados") or 0,
            "declarado": r.get("total_declarado"),
            "pct_campos_ok": r.get("pct_campos_ok"),
            "alertas": r.get("alertas"),
        })
    return metricas


def renderizar_saude(hoje, fallback_varejo=None):
    """Renderiza uma visão única depois de todas as pernas da coleta."""
    inicio = hoje - timedelta(days=7)
    marcas = supabase_rest.selecionar(
        "marcas", "?select=id,nome,plataforma,status_teste,ativa&order=nome")
    marcas_ativas = [m for m in marcas
                     if m.get("ativa")
                     and m.get("status_teste") in ("vtex", "shopify")]
    nomes = {m["id"]: (m["nome"], m.get("plataforma") or "?") for m in marcas}
    registros = supabase_rest.selecionar(
        "saude", "?data=gte.{}&data=lte.{}&select=id,data,fonte,marca_id,"
                 "visitados,gravados,itens,total_declarado,pct_campos_ok,"
                 "alertas,criado_em&order=criado_em.asc".format(
                     inicio.isoformat(), hoje.isoformat()))

    hoje_iso = hoje.isoformat()
    atuais = {}
    for r in registros:
        if r.get("data") == hoje_iso:
            atuais[(r.get("fonte"), r.get("marca_id"))] = r

    metricas = metricas_varejo_ativas(atuais, nomes, marcas_ativas)
    if not metricas and fallback_varejo:
        metricas = fallback_varejo

    criticos, avisos = alertas_criticos(registros, marcas_ativas, hoje)
    contagem_cobertura, cobertura_por_marca = resumo_de_cobertura(metricas)
    tot_vis = sum(m["visitados"] for m in metricas)
    tot_grav = sum(m["gravados"] for m in metricas)
    presentes = {m["marca_id"] for m in metricas}
    faltantes = [m["nome"] for m in marcas_ativas if m["id"] not in presentes]

    linhas = ["# SAÚDE — coletores do Canário\n",
              "**Gerado (UTC):** {}\n".format(
                  datetime.now(timezone.utc).isoformat()),
              "**Data observada:** {}\n".format(hoje_iso),
              "**Estado:** {} · {}\n".format(
                  "ATENÇÃO" if criticos else "sem alerta crítico",
                  frase_de_cobertura(contagem_cobertura)),
              "\n## Portão operacional\n"]
    if avisos:
        linhas.append(
            "\n**Avisos (não travam):** fonte que recusou hoje mas voltou "
            "antes de {} dias seguidos.\n\n".format(DIAS_DE_ZERO_PARA_BLOQUEAR))
        linhas += ["- {}\n".format(a) for a in avisos]
        linhas.append("\n")
    if criticos:
        linhas.extend("- ⚠️ {}\n".format(c) for c in criticos)
    else:
        linhas.append(
            "- Todas as fontes obrigatórias registraram volume sem queda superior a 70%.\n")

    linhas.extend(["\n## Varejo\n",
                   "- Produtos **visitados**: {}\n".format(tot_vis),
                   "- Snapshots **gravados** (delta, B3): {}\n".format(tot_grav),
                   "- Marcas coletando: {} de {}\n".format(
                       len(presentes), len(marcas_ativas))])
    if faltantes:
        linhas.append("\n> ⚠️ Sem observação hoje: {}\n".format(
            ", ".join(faltantes)))
    linhas.append(
        "\n| Marca | Plat. | Visitados | Gravados | Declarado (VTEX) | % campos ok | Alertas |")
    linhas.append("|---|---|---|---|---|---|---|")
    for m in sorted(metricas, key=lambda x: -x["visitados"]):
        alerta = (json.dumps(m["alertas"], ensure_ascii=False)
                  if m["alertas"] else "—").replace("|", "\\|")
        linhas.append("| {} | {} | {} | {} | {} | {} | {} |".format(
            m["nome"], m["plataforma"], m["visitados"], m["gravados"],
            m["declarado"] if m["declarado"] else "—",
            m["pct_campos_ok"] if m["pct_campos_ok"] is not None else "—",
            alerta))

    linhas.extend(["\n## Cobertura do catálogo\n",
                   "\nVolume e cobertura são perguntas diferentes: a tabela "
                   "acima diz **quanto veio**, esta diz **se veio inteiro**. "
                   "Marca com volume normal e faixa truncada passa verde no "
                   "portão e mesmo assim entregou catálogo cortado.\n",
                   "\n> A perda é **teto**, não valor exato: as faixas são "
                   "contadas por categoria e o mesmo produto aparece em mais "
                   "de uma, então a soma conta repetido.\n"])
    incompletas = [c for c in cobertura_por_marca if c["estado"] != "completa"]
    if incompletas:
        linhas.append(
            "\n| Marca | Cobertura | Faixas cortadas | Teto de perda | Motivo |")
        linhas.append("|---|---|---:|---:|---|")
        for c in sorted(incompletas,
                        key=lambda x: -((x["detalhe"] or {}).get(
                            "teto_de_perda") or 0)):
            d = c["detalhe"] or {}
            linhas.append("| {} | {} | {} | {} | {} |".format(
                c["nome"], c["estado"],
                d.get("faixas") if d.get("faixas") else "—",
                "{:,}".format(d["teto_de_perda"]).replace(",", ".")
                if d.get("teto_de_perda") else "—",
                str(d.get("erro") or "paginação parou antes do fim").replace(
                    "|", "\\|")))
    else:
        linhas.append(
            "\n- Nenhuma marca acusou corte de paginação ou falha de contagem.\n")

    linhas.extend(["\n## Outras fontes\n",
                   "| Fonte | Tentativas | Respostas | Itens/pontos | % ok | Alertas |",
                   "|---|---:|---:|---:|---:|---|"])
    for fonte in ("editorial", "busca"):
        r = atuais.get((fonte, None))
        if not r:
            linhas.append(
                "| {} | — | — | — | — | sem observação hoje |".format(fonte))
            continue
        alerta = (json.dumps(r.get("alertas"), ensure_ascii=False)
                  if r.get("alertas") else "—").replace("|", "\\|")
        linhas.append("| {} | {} | {} | {} | {} | {} |".format(
            fonte, r.get("visitados") or 0, r.get("gravados") or 0,
            r.get("itens") or 0,
            r.get("pct_campos_ok")
            if r.get("pct_campos_ok") is not None else "—",
            alerta))

    linhas.append("\n---\n")
    linhas.append(
        "Queda crítica = volume do dia abaixo de 30% da média das observações "
        "positivas dos sete dias anteriores. Ausência e zero também bloqueiam. "
        "O motor só deve publicar depois de todas as fontes obrigatórias.\n")
    with open(SAUDE_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))
    return criticos


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    print("Materializando anexos...", file=sys.stderr)
    materializar_anexos.materializar_marcas()
    materializar_anexos.materializar_termos()

    filtro = os.environ.get("COLETA_MARCA", "").strip()  # particionar por marca se preciso
    # COLETA_PLATAFORMA existe porque Amaro e PatBo (Shopify) devolvem 429 do
    # datacenter do GitHub e 200 do IP residencial. Assim o runner do Mac cuida
    # so delas, e o datacenter cuida das VTEX, que responde bem.
    plataforma = os.environ.get("COLETA_PLATAFORMA", "").strip().lower()
    marcas = supabase_rest.selecionar(
        "marcas",
        "?status_teste=in.(vtex,shopify)&ativa=eq.true&select=id,nome,dominio,plataforma&order=nome")
    if filtro:
        marcas = [m for m in marcas if m["nome"].lower() == filtro.lower()]
    if plataforma:
        marcas = [m for m in marcas if (m["plataforma"] or "").lower() == plataforma]
    print("Marcas a coletar: {}{}".format(
        len(marcas), " (filtro: {})".format(filtro) if filtro else ""), file=sys.stderr)

    hoje = data_operacional()
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
