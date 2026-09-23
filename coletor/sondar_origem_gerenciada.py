#!/usr/bin/env python3
"""Sonda mínima e somente-leitura para um executor gerenciado.

Ela responde uma pergunta limitada antes de mover a coleta: as origens públicas
aceitam, com suas estruturas esperadas, uma chamada educada de um datacenter
gerenciado? Não coleta catálogo, não chama Supabase, não segue redirects e não
persiste corpos, cabeçalhos, cookies ou tokens. Os corpos são validados apenas
em memória e sob limites explícitos.

Uma resposta 403, 429, timeout ou robots.txt ausente é diagnóstico, não falha
do processo. Resultado positivo tampouco autoriza migração: ele apenas libera
a próxima prova, que continua separada e sem escrita.
"""

import argparse
import datetime as dt
import http.client
import http.cookiejar
import json
import math
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from xml.etree import ElementTree


UA = "CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)"
INTERVALO_GLOBAL_SEGUNDOS = 1.0
MAX_INTERVALO_ROBOTS_SEGUNDOS = 15.0
TIMEOUT_SEGUNDOS = 12
MAX_BYTES_ROBOTS = 1024 * 1024
MAX_BYTES_ENDPOINT = 2 * 1024 * 1024
MAX_BYTES_TOKEN_TRENDS = 2048
MAX_BYTES_REQUEST_TRENDS = 64 * 1024

# Uma fonte por classe de risco conhecida. A lista é fechada de propósito:
# adicionar uma origem exige revisar robots, direito de uso e motivo da sonda.
ALVOS = (
    {
        "id": "vtex_cantao",
        "classe": "catalogo_vtex",
        "url": "https://www.cantao.com.br/api/catalog_system/pub/products/search/vestido?_from=0&_to=0",
        "validacao": "vtex",
    },
    {
        # A Amaro, sonda original desta classe, saiu da Shopify em 23/09/2026.
        "id": "shopify_patbo",
        "classe": "catalogo_shopify",
        "url": "https://www.patbo.com.br/products.json?limit=1",
        "validacao": "shopify",
    },
    {
        "id": "nuvemshop_amaro",
        "classe": "catalogo_nuvemshop",
        "url": "https://amaro.com/sitemap.xml",
        "validacao": "sitemap",
    },
    {
        "id": "editorial_ffw",
        "classe": "feed_editorial_wp_json",
        "url": "https://ffw.com.br/wp-json/wp/v2/posts?per_page=1&_fields=id,link,date,title",
        "validacao": "wp_json",
    },
    {
        "id": "editorial_bof",
        "classe": "feed_editorial_rss",
        "url": "https://www.businessoffashion.com/arc/outboundfeeds/rss/?outputType=xml",
        "validacao": "xml",
    },
    {
        "id": "google_trends",
        "classe": "busca_trends",
        "url": "https://trends.google.com/trends/?geo=BR",
        "validacao": "trends",
    },
)

VALIDACOES = frozenset({"vtex", "shopify", "wp_json", "xml", "sitemap", "trends"})


def _normalizar_caminho_robots(texto, padrao=False):
    """Preserva escapes reservados; decodifica somente ASCII não reservado."""
    nao_reservados = frozenset(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    partes = []
    indice = 0
    while indice < len(texto):
        caractere = texto[indice]
        if caractere == "%" and indice + 2 < len(texto):
            try:
                byte = int(texto[indice + 1:indice + 3], 16)
            except ValueError:
                pass
            else:
                partes.append(chr(byte) if chr(byte) in nao_reservados else
                              "%{:02X}".format(byte))
                indice += 3
                continue
        if caractere in "*$" and not padrao:
            partes.append("%{:02X}".format(ord(caractere)))
        elif ord(caractere) > 127 or caractere in " %":
            partes.extend("%{:02X}".format(byte)
                          for byte in caractere.encode("utf-8"))
        else:
            partes.append(caractere)
        indice += 1
    return "".join(partes)


def _combina_padrao_robots(padrao, caminho):
    """Glob ancorado no início, sem regex com backtracking exponencial."""
    padrao = padrao[:-1] if padrao.endswith("$") else padrao + "*"
    i = j = 0
    estrela = -1
    retomada = 0
    while i < len(caminho):
        if j < len(padrao) and padrao[j] == "*":
            estrela = j
            j += 1
            retomada = i
        elif j < len(padrao) and padrao[j] == caminho[i]:
            i += 1
            j += 1
        elif estrela >= 0:
            retomada += 1
            i = retomada
            j = estrela + 1
        else:
            return False
    return all(caractere == "*" for caractere in padrao[j:])


class PoliticaRobots:
    """Regras RFC 9309 para o produto CanarioBot, mais cadência conservadora.

    Combina grupos do mesmo agente, usa o caminho mais específico, desempata
    com Allow e suporta * e $. Diretivas de cadência inválidas fazem a sonda
    parar, em vez de assumir permissão para uma frequência maior.
    """

    def __init__(self, linhas):
        grupos = []
        grupo = None
        corpo_iniciado = False
        for linha in linhas:
            linha = linha.split("#", 1)[0].strip()
            if ":" not in linha:
                continue
            chave, valor = (parte.strip() for parte in linha.split(":", 1))
            chave = chave.lower()
            if chave == "user-agent":
                if not valor:
                    raise ValueError("agente vazio")
                if grupo is None or corpo_iniciado:
                    grupo = {"agentes": [], "regras": [], "atrasos": [], "taxas": []}
                    grupos.append(grupo)
                    corpo_iniciado = False
                grupo["agentes"].append(valor.lower())
            elif grupo is not None and chave in {
                    "allow", "disallow", "crawl-delay", "request-rate"}:
                corpo_iniciado = True
                if chave in {"allow", "disallow"}:
                    if valor:
                        if not valor.startswith(("/", "*")):
                            raise ValueError("padrão robots não suportado")
                        grupo["regras"].append(
                            (chave == "allow", _normalizar_caminho_robots(valor, True)))
                elif chave == "crawl-delay":
                    grupo["atrasos"].append(valor)
                else:
                    grupo["taxas"].append(valor)
        if not grupos:
            raise ValueError("robots sem grupo")
        produto = UA.split("/", 1)[0].lower()
        escolhidos = [g for g in grupos if produto in g["agentes"]]
        if not escolhidos:
            escolhidos = [g for g in grupos if "*" in g["agentes"]]
        self.regras = [r for g in escolhidos for r in g["regras"]]
        atrasos = [float(v) for g in escolhidos for v in g["atrasos"]]
        if any(not math.isfinite(v) or v < 0 for v in atrasos):
            raise ValueError("crawl-delay inválido")
        self.atraso = max(atrasos) if atrasos else None
        taxas = []
        for grupo in escolhidos:
            for valor in grupo["taxas"]:
                pedidos, segundos = (parte.strip() for parte in valor.split("/"))
                if not pedidos.isdigit() or not segundos.isdigit() or int(pedidos) <= 0:
                    raise ValueError("request-rate inválido")
                taxas.append(float(segundos) / int(pedidos))
        self.intervalo_taxa = max(taxas) if taxas else None

    def can_fetch(self, agente, url):
        if agente != UA:
            raise ValueError("política restrita ao agente configurado")
        partes = urllib.parse.urlsplit(url)
        caminho = _normalizar_caminho_robots(
            (partes.path or "/") + ("?" + partes.query if partes.query else ""))
        candidatas = [(len(padrao.rstrip("$").replace("*", "").encode("utf-8")), permitir)
                      for permitir, padrao in self.regras
                      if _combina_padrao_robots(padrao, caminho)]
        return max(candidatas)[1] if candidatas else True


class SemRedirecionamento(urllib.request.HTTPRedirectHandler):
    """Transforma 30x em resposta observável em vez de seguir outro host."""

    def redirect_request(self, req, fp, code, msg, headers, novo_url):
        return None


class CadenciaGlobal:
    """Garante uma cadência global e respeita o atraso maior por domínio."""

    def __init__(self, clock=None, sleep=None, intervalo=INTERVALO_GLOBAL_SEGUNDOS):
        self.clock = clock or time.monotonic
        self.sleep = sleep or time.sleep
        self.intervalo = float(intervalo)
        self.ultimo_global = None
        self.ultimo_por_dominio = {}

    def aguardar(self, dominio, minimo_por_dominio=0.0):
        agora = self.clock()
        esperas = []
        if self.ultimo_global is not None:
            esperas.append(self.intervalo - (agora - self.ultimo_global))
        anterior_dominio = self.ultimo_por_dominio.get(dominio)
        if anterior_dominio is not None:
            esperas.append(float(minimo_por_dominio) - (agora - anterior_dominio))
        espera = max([0.0] + esperas)
        if espera > 0:
            self.sleep(espera)
        marcado_em = self.clock()
        self.ultimo_global = marcado_em
        self.ultimo_por_dominio[dominio] = marcado_em
        return espera


def _tipo_de_erro(erro):
    """Classificação curta: mensagens remotas nunca entram no artefato."""
    if isinstance(erro, (socket.timeout, TimeoutError)):
        return "timeout"
    if isinstance(erro, urllib.error.URLError):
        motivo = getattr(erro, "reason", None)
        if isinstance(motivo, (socket.timeout, TimeoutError)):
            return "timeout"
        return "falha_de_rede"
    return "falha_de_rede"


def _abrir(url, dominio, cadencia, opener, clock, limite_bytes,
           minimo_por_dominio=0.0, referer=None):
    """Faz GET limitado; o corpo retornado só pode ser consumido em memória."""
    if limite_bytes <= 0:
        raise ValueError("limite de leitura deve ser positivo")
    cadencia.aguardar(dominio, minimo_por_dominio)
    inicio = clock()
    headers = {
        "User-Agent": UA,
        "Accept": "text/html, application/json, application/xml, text/xml, */*",
        "Accept-Language": "pt-BR,pt;q=0.9",
        "Accept-Encoding": "identity",
    }
    if referer:
        headers["Referer"] = referer
    requisicao = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with opener.open(requisicao, timeout=TIMEOUT_SEGUNDOS) as resposta:
            status = resposta.getcode()
            lido = resposta.read(limite_bytes + 1)
            truncado = len(lido) > limite_bytes
            return {
                "http": status,
                "erro": None,
                "duracao_ms": int((clock() - inicio) * 1000),
                "corpo": lido[:limite_bytes],
                "truncado": truncado,
            }
    except urllib.error.HTTPError as erro:
        codigo = erro.code
        if getattr(erro, "fp", None) is not None:
            erro.close()
        return {
            "http": codigo,
            "erro": "redirecionamento" if 300 <= codigo < 400 else None,
            "duracao_ms": int((clock() - inicio) * 1000),
            "corpo": b"",
            "truncado": False,
        }
    except (urllib.error.URLError, OSError, http.client.HTTPException) as erro:
        return {
            "http": None,
            "erro": _tipo_de_erro(erro),
            "duracao_ms": int((clock() - inicio) * 1000),
            "corpo": b"",
            "truncado": False,
        }


def _avaliar_robots(resposta, alvo_url):
    """Falha fechada e devolve o parser apenas para validações internas."""
    base = {
        "http": resposta["http"],
        "duracao_ms": resposta["duracao_ms"],
        "crawl_delay_segundos": None,
        "request_rate_intervalo_segundos": None,
        "intervalo_minimo_segundos": None,
    }
    if resposta["http"] != 200:
        base.update({"decisao": "nao_verificado", "motivo":
                     resposta["erro"] or "robots_indisponivel"})
        return base, None
    if resposta["erro"] or resposta["truncado"]:
        base.update({"decisao": "nao_verificado", "motivo":
                     resposta["erro"] or "robots_acima_do_limite"})
        return base, None
    try:
        texto = resposta["corpo"].decode("utf-8-sig")
    except UnicodeDecodeError:
        base.update({"decisao": "nao_verificado", "motivo": "robots_invalido"})
        return base, None
    linhas = texto.splitlines()
    try:
        parser = PoliticaRobots(linhas)
        permitido = parser.can_fetch(UA, alvo_url)
        atraso = parser.atraso
        intervalo_taxa = parser.intervalo_taxa
    except (ValueError, OverflowError):
        base.update({"decisao": "nao_verificado", "motivo": "robots_invalido"})
        return base, None

    intervalos = [INTERVALO_GLOBAL_SEGUNDOS]
    if isinstance(atraso, (int, float)) and atraso >= 0:
        base["crawl_delay_segundos"] = float(atraso)
        intervalos.append(float(atraso))
    if intervalo_taxa is not None:
        base["request_rate_intervalo_segundos"] = intervalo_taxa
        intervalos.append(intervalo_taxa)
    base["intervalo_minimo_segundos"] = max(intervalos)
    if not permitido:
        base.update({"decisao": "negado", "motivo": "robots_proibe"})
        return base, parser
    base.update({"decisao": "permitido", "motivo": None})
    return base, parser


def _situacao_http(resposta):
    if resposta["http"] is None:
        return resposta["erro"] or "falha_de_rede"
    if resposta["erro"]:
        return resposta["erro"]
    return "http_{}".format(resposta["http"])


def _carregar_json(corpo, xssi=False):
    texto = corpo.decode("utf-8-sig")
    if xssi and texto.startswith(")]}'"):
        if "\n" in texto:
            texto = texto.split("\n", 1)[1]
        else:
            texto = texto[4:].lstrip(", \t\r")
    return json.loads(texto)


def _validar_corpo_generico(tipo, resposta):
    # VTEX documenta 206 como página válida de produtos, não JSON cortado.
    # https://github.com/vtex/openapi-schemas/blob/master/VTEX%20-%20Search%20API.json
    codigos_validos = {200, 206} if tipo == "vtex" else {200}
    if resposta["http"] not in codigos_validos:
        return False, _situacao_http(resposta)
    if resposta["truncado"]:
        return False, "corpo_acima_do_limite"
    corpo = resposta["corpo"]
    if not corpo:
        return False, "resposta_incompativel"
    try:
        if tipo == "vtex":
            dados = _carregar_json(corpo)
            valido = (isinstance(dados, list) and bool(dados) and
                      isinstance(dados[0], dict) and
                      bool(dados[0].get("productId")) and
                      isinstance(dados[0].get("items"), list))
        elif tipo == "shopify":
            dados = _carregar_json(corpo)
            produtos = dados.get("products") if isinstance(dados, dict) else None
            valido = (isinstance(produtos, list) and bool(produtos) and
                      isinstance(produtos[0], dict) and
                      bool(produtos[0].get("id") or produtos[0].get("handle")))
        elif tipo == "wp_json":
            dados = _carregar_json(corpo)
            valido = (isinstance(dados, list) and bool(dados) and
                      isinstance(dados[0], dict) and
                      all(chave in dados[0] for chave in ("id", "link", "title")) and
                      isinstance(dados[0]["title"], dict))
        elif tipo == "xml":
            upper = corpo.upper()
            if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
                return False, "xml_nao_seguro"
            raiz = ElementTree.fromstring(corpo)
            nome_raiz = raiz.tag.rsplit("}", 1)[-1].lower()
            itens = [elemento for elemento in raiz.iter()
                     if elemento.tag.rsplit("}", 1)[-1].lower() in {"item", "entry"}]
            valido = nome_raiz in {"rss", "feed"} and bool(itens)
        elif tipo == "sitemap":
            upper = corpo.upper()
            if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
                return False, "xml_nao_seguro"
            raiz = ElementTree.fromstring(corpo)
            locs = [elemento for elemento in raiz.iter()
                    if elemento.tag.rsplit("}", 1)[-1].lower() == "loc"
                    and (elemento.text or "").strip()]
            valido = raiz.tag.rsplit("}", 1)[-1].lower() == "urlset" and bool(locs)
        else:
            raise ValueError("estratégia de validação desconhecida")
    except (UnicodeDecodeError, json.JSONDecodeError, ElementTree.ParseError,
            TypeError, ValueError):
        return False, "resposta_incompativel"
    return (True, "protocolo_valido") if valido else (False, "resposta_incompativel")


def _resultado_generico(resposta, validacao):
    valido, situacao = _validar_corpo_generico(validacao, resposta)
    return {
        "executado": True,
        "http": resposta["http"],
        "duracao_ms": resposta["duracao_ms"],
        "situacao": situacao,
        "protocolo_valido": valido,
    }


def _url_explore_trends():
    pedido = {
        "comparisonItem": [{
            "keyword": "vestido floral",
            "geo": "BR",
            "time": "today 3-m",
        }],
        "category": 0,
        "property": "",
    }
    query = urllib.parse.urlencode({
        "hl": "pt-BR",
        "tz": "180",
        "req": json.dumps(pedido, ensure_ascii=False, separators=(",", ":")),
    })
    return "https://trends.google.com/trends/api/explore?{}".format(query)


def _extrair_widget_timeseries(corpo):
    try:
        dados = _carregar_json(corpo, xssi=True)
        widgets = dados.get("widgets") if isinstance(dados, dict) else None
        if not isinstance(widgets, list):
            return None
        widget = next((item for item in widgets
                       if isinstance(item, dict) and item.get("id") == "TIMESERIES"),
                      None)
        if not widget:
            return None
        token = widget.get("token")
        pedido = widget.get("request")
        if not isinstance(token, str) or not token or not isinstance(pedido, dict):
            return None
        if len(token.encode("utf-8")) > MAX_BYTES_TOKEN_TRENDS:
            return None
        pedido_json = json.dumps(pedido, ensure_ascii=False, separators=(",", ":"))
        if len(pedido_json.encode("utf-8")) > MAX_BYTES_REQUEST_TRENDS:
            return None
        return token, pedido_json
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
        return None


def _url_multiline_trends(token, pedido_json):
    query = urllib.parse.urlencode({
        "hl": "pt-BR",
        "tz": "180",
        "req": pedido_json,
        "token": token,
    })
    return "https://trends.google.com/trends/api/widgetdata/multiline?{}".format(query)


def _timeline_valida(corpo):
    try:
        dados = _carregar_json(corpo, xssi=True)
        padrao = dados.get("default") if isinstance(dados, dict) else None
        pontos = padrao.get("timelineData") if isinstance(padrao, dict) else None
        if not isinstance(pontos, list) or not pontos:
            return False
        for ponto in pontos:
            if not isinstance(ponto, dict):
                return False
            instante, valores = ponto.get("time"), ponto.get("value")
            if (not isinstance(instante, str) or not instante.isascii() or
                    not instante.isdigit() or int(instante) <= 0 or
                    not isinstance(valores, list) or len(valores) != 1):
                return False
            valor = valores[0]
            if (isinstance(valor, bool) or not isinstance(valor, (int, float)) or
                    not math.isfinite(valor) or not 0 <= valor <= 100):
                return False
        return True
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
        return False


def _etapa_publica(identificador, resposta, situacao=None):
    return {
        "id": identificador,
        "http": resposta["http"],
        "duracao_ms": resposta["duracao_ms"],
        "situacao": situacao or _situacao_http(resposta),
    }


def _falha_trends(etapas, motivo):
    return {
        "executado": bool(etapas),
        "http": etapas[-1]["http"] if etapas else None,
        "duracao_ms": sum(etapa["duracao_ms"] for etapa in etapas),
        "situacao": motivo,
        "protocolo_valido": False,
        "etapas": etapas,
    }


def _sondar_trends(alvo, parser_robots, dominio, cadencia, opener, clock,
                   minimo_por_dominio):
    etapas = []
    url_explore = _url_explore_trends()
    if not parser_robots.can_fetch(UA, url_explore):
        return _falha_trends(etapas, "robots_proibe_explore")

    warmup = _abrir(
        alvo["url"], dominio, cadencia, opener, clock, MAX_BYTES_ENDPOINT,
        minimo_por_dominio=minimo_por_dominio)
    warmup_valido = (warmup["http"] == 200 and not warmup["truncado"] and
                     bool(warmup["corpo"]))
    etapas.append(_etapa_publica(
        "warmup", warmup,
        "respondeu" if warmup_valido else
        ("corpo_acima_do_limite" if warmup["truncado"] else
         _situacao_http(warmup) if warmup["http"] != 200 else
         "resposta_incompativel")))
    if not warmup_valido:
        return _falha_trends(etapas, etapas[-1]["situacao"])

    referer = "https://trends.google.com/trends/explore?geo=BR"
    explore = _abrir(
        url_explore, dominio, cadencia, opener, clock, MAX_BYTES_ENDPOINT,
        minimo_por_dominio=minimo_por_dominio, referer=referer)
    widget = None if explore["truncado"] or explore["http"] != 200 else \
        _extrair_widget_timeseries(explore["corpo"])
    explore_valido = widget is not None
    etapas.append(_etapa_publica(
        "explore", explore,
        "respondeu" if explore_valido else
        ("corpo_acima_do_limite" if explore["truncado"] else
         _situacao_http(explore) if explore["http"] != 200 else
         "resposta_incompativel")))
    if not explore_valido:
        return _falha_trends(etapas, etapas[-1]["situacao"])

    token, pedido_json = widget
    url_multiline = _url_multiline_trends(token, pedido_json)
    if not parser_robots.can_fetch(UA, url_multiline):
        return _falha_trends(etapas, "robots_proibe_multiline")
    multiline = _abrir(
        url_multiline, dominio, cadencia, opener, clock, MAX_BYTES_ENDPOINT,
        minimo_por_dominio=minimo_por_dominio, referer=referer)
    timeline_valida = (multiline["http"] == 200 and
                       not multiline["truncado"] and
                       _timeline_valida(multiline["corpo"]))
    etapas.append(_etapa_publica(
        "multiline", multiline,
        "protocolo_valido" if timeline_valida else
        ("corpo_acima_do_limite" if multiline["truncado"] else
         _situacao_http(multiline) if multiline["http"] != 200 else
         "resposta_incompativel")))
    if not timeline_valida:
        return _falha_trends(etapas, etapas[-1]["situacao"])
    return {
        "executado": True,
        "http": multiline["http"],
        "duracao_ms": sum(etapa["duracao_ms"] for etapa in etapas),
        "situacao": "protocolo_valido",
        "protocolo_valido": True,
        "etapas": etapas,
    }


def _validar_alvos(alvos):
    ids = set()
    for alvo in alvos:
        if set(alvo) != {"id", "classe", "url", "validacao"}:
            raise ValueError("alvo fora do schema fechado")
        if alvo["id"] in ids:
            raise ValueError("IDs de alvo devem ser únicos")
        ids.add(alvo["id"])
        partes = urllib.parse.urlsplit(alvo["url"])
        if partes.scheme != "https" or not partes.hostname or partes.username:
            raise ValueError("alvo deve ter URL HTTPS pública sem credencial")
        if alvo["validacao"] not in VALIDACOES:
            raise ValueError("estratégia de validação desconhecida")


def sondar(alvos=ALVOS, opener=None, trends_opener=None, clock=None,
           sleep=None, agora=None):
    """Executa a sonda e devolve somente metadados permitidos no artefato."""
    alvos = tuple(alvos)
    _validar_alvos(alvos)
    clock = clock or time.monotonic
    agora = agora or (lambda: dt.datetime.now(dt.timezone.utc))
    opener_fornecido = opener is not None
    opener = opener or urllib.request.build_opener(SemRedirecionamento())
    cookie_jar = None
    if trends_opener is None:
        if opener_fornecido:
            trends_opener = opener
        else:
            cookie_jar = http.cookiejar.CookieJar()
            trends_opener = urllib.request.build_opener(
                SemRedirecionamento(), urllib.request.HTTPCookieProcessor(cookie_jar))
    cadencia = CadenciaGlobal(clock=clock, sleep=sleep)
    resultados = []

    try:
        for alvo in alvos:
            url = alvo["url"]
            dominio = urllib.parse.urlsplit(url).hostname
            opener_alvo = trends_opener if alvo["validacao"] == "trends" else opener
            resposta_robots = _abrir(
                "https://{}/robots.txt".format(dominio), dominio, cadencia,
                opener_alvo, clock, MAX_BYTES_ROBOTS)
            robots, parser_robots = _avaliar_robots(resposta_robots, url)
            registro = {
                "id": alvo["id"],
                "classe": alvo["classe"],
                "url": url,
                "robots": robots,
            }
            intervalo = robots["intervalo_minimo_segundos"] or 0.0
            if robots["decisao"] != "permitido":
                registro["endpoint"] = {
                    "executado": False,
                    "motivo": robots["motivo"],
                    "protocolo_valido": False,
                }
            elif intervalo > MAX_INTERVALO_ROBOTS_SEGUNDOS:
                registro["endpoint"] = {
                    "executado": False,
                    "motivo": "intervalo_robots_acima_do_limite_de_diagnostico",
                    "protocolo_valido": False,
                }
            elif alvo["validacao"] == "trends":
                registro["endpoint"] = _sondar_trends(
                    alvo, parser_robots, dominio, cadencia, opener_alvo, clock,
                    intervalo)
            else:
                resposta = _abrir(
                    url, dominio, cadencia, opener_alvo, clock, MAX_BYTES_ENDPOINT,
                    minimo_por_dominio=intervalo)
                registro["endpoint"] = _resultado_generico(
                    resposta, alvo["validacao"])
            resultados.append(registro)
    finally:
        if cookie_jar is not None:
            cookie_jar.clear()

    executados = [r for r in resultados if r["endpoint"]["executado"]]
    validos = [r for r in resultados if r["endpoint"]["protocolo_valido"]]
    todos_validos = bool(resultados) and len(validos) == len(resultados)
    return {
        "schema": "datadrobe_managed_origin_probe_v2",
        "executado_em": agora().astimezone(dt.timezone.utc).isoformat(),
        "veredito": ("apto_para_proxima_prova" if todos_validos else
                     "inconclusivo_ou_bloqueado"),
        "nao_autoriza_migracao": True,
        "politica": {
            "somente_leitura": True,
            "cadencia_global_segundos": INTERVALO_GLOBAL_SEGUNDOS,
            "segue_redirecionamentos": False,
            "corpos_persistidos": False,
            "cookies_persistidos": False,
            "cookies_transitorios_trends": True,
            "supabase_consultado": False,
        },
        "resumo": {
            "alvos": len(resultados),
            "endpoints_executados": len(executados),
            "protocolos_validos": len(validos),
        },
        "alvos": resultados,
    }


def _escrever_json(caminho, dados):
    pasta = os.path.dirname(os.path.abspath(caminho))
    if not os.path.isdir(pasta):
        raise ValueError("diretório de saída inexistente")
    with open(caminho, "w", encoding="utf-8") as arquivo:
        json.dump(dados, arquivo, ensure_ascii=False, indent=2, sort_keys=True)
        arquivo.write("\n")


def main(argv=None):
    argumentos = argparse.ArgumentParser(
        description="Sonda pública, manual e somente-leitura de origem gerenciada.")
    argumentos.add_argument("--saida", required=True,
                            help="JSON de diagnóstico, normalmente no RUNNER_TEMP")
    opcoes = argumentos.parse_args(argv)
    dados = sondar()
    _escrever_json(opcoes.saida, dados)
    print("Sonda concluída: {}/{} protocolos válidos; veredito {}.".format(
        dados["resumo"]["protocolos_validos"], dados["resumo"]["alvos"],
        dados["veredito"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
