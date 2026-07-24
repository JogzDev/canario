"""Descoberta de feed por veiculo editorial (secao 18, passos 1 a 4).

So diagnostico: descobre por onde cada veiculo publica feed e ate onde o arquivo
default alcanca. Nao faz backfill (isso e fase posterior). Preenche em
`veiculos.csv` o metodo que funcionou e a data do item mais antigo acessivel.

Ordem de tentativa (secao 18):
  1. caminhos comuns: /feed, /rss, /feed.xml, /rss.xml, /atom.xml, /index.xml
  2. baixar a home e procurar <link rel="alternate" type="application/rss+xml">
  3. /wp-json/wp/v2/posts?per_page=10 (WordPress) -- tambem sinaliza backfill
  4. validar que cada item tem titulo, link e data (sem data, item inutil)

Etiqueta da regra 7 (1 req/s por dominio) herdada de teste_30s.buscar. Infra
editorial e diferente da VTEX, sem penalidade compartilhada.
"""

import csv
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urljoin, urlparse
from xml.etree import ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar, robots_permite  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VEICULOS = os.path.join(RAIZ, "anexos", "veiculos.csv")

CAMINHOS = ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml",
            "/feed/"]
WPJSON = "/wp-json/wp/v2/posts?per_page=10"


def dominio_de(url):
    return urlparse(url).netloc


def parse_data(texto):
    """Aceita RFC822 (RSS) e ISO8601 (Atom, wp-json). Devolve datetime UTC ou None."""
    if not texto:
        return None
    texto = texto.strip()
    try:
        d = parsedate_to_datetime(texto)
        if d:
            return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError, IndexError):
        pass
    try:
        limpo = texto.replace("Z", "+00:00")
        d = datetime.fromisoformat(limpo)
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _tag(elem):
    return elem.tag.split("}")[-1].lower()


def analisar_xml(corpo):
    """Extrai (n_itens, itens_validos, data_mais_antiga) de um feed RSS ou Atom."""
    try:
        raiz = ET.fromstring(corpo.encode("utf-8"))
    except ET.ParseError:
        return None

    itens, validos, datas = 0, 0, []
    for elem in raiz.iter():
        if _tag(elem) not in ("item", "entry"):
            continue
        itens += 1
        titulo = link = data = None
        for filho in elem:
            t = _tag(filho)
            if t == "title":
                titulo = (filho.text or "").strip()
            elif t == "link":
                link = (filho.text or filho.get("href") or "").strip()
            elif t in ("pubdate", "published", "updated", "date"):
                data = data or parse_data(filho.text)
        if titulo and link and data:
            validos += 1
            datas.append(data)
    if itens == 0:
        return None
    return itens, validos, (min(datas) if datas else None)


def tentar_feed_url(url, dominio):
    codigo, corpo, _, cab = buscar(url, dominio)
    if codigo not in (200, 206) or not corpo:
        return None
    ctype = (cab.get("Content-Type") or cab.get("content-type") or "").lower()
    if "html" in ctype and "xml" not in ctype:
        return None  # veio a home, nao um feed
    return analisar_xml(corpo)


def achar_link_no_html(corpo, base):
    """Passo 2: <link rel="alternate" type="application/rss+xml" href="...">."""
    achados = []
    for m in re.finditer(r"<link\b[^>]*>", corpo, re.IGNORECASE):
        tag = m.group(0)
        if "alternate" not in tag.lower():
            continue
        if "rss+xml" not in tag.lower() and "atom+xml" not in tag.lower():
            continue
        href = re.search(r'href\s*=\s*["\']([^"\']+)["\']', tag, re.IGNORECASE)
        if href:
            achados.append(urljoin(base, href.group(1)))
    return achados


def tentar_wpjson(base, dominio):
    """Passo 3: WordPress REST. Sinaliza backfill possivel."""
    url = urljoin(base, WPJSON)
    codigo, corpo, _, _ = buscar(url, dominio)
    if codigo not in (200, 206) or not corpo:
        return None
    try:
        posts = json.loads(corpo)
    except ValueError:
        return None
    if not isinstance(posts, list) or not posts:
        return None
    validos, datas = 0, []
    for p in posts:
        if not isinstance(p, dict):
            continue
        titulo = (p.get("title") or {}).get("rendered") if isinstance(p.get("title"), dict) else p.get("title")
        link = p.get("link")
        data = parse_data(p.get("date_gmt") or p.get("date"))
        if titulo and link and data:
            validos += 1
            datas.append(data)
    if validos == 0:
        return None
    return len(posts), validos, (min(datas) if datas else None)


def descobrir(veiculo):
    url_base = veiculo["url"]
    dominio = dominio_de(url_base)

    # Passo 1: caminhos comuns.
    for caminho in CAMINHOS:
        if not robots_permite(dominio, caminho)[0]:
            continue
        r = tentar_feed_url(urljoin(url_base, caminho), dominio)
        if r:
            return _resultado(caminho, urljoin(url_base, caminho), r, backfill="nao")

    # Passo 2: link declarado na home.
    codigo, corpo, _, _ = buscar(url_base if url_base.endswith("/") else url_base + "/", dominio)
    if codigo in (200, 206) and corpo:
        for href in achar_link_no_html(corpo, url_base):
            r = tentar_feed_url(href, dominio)
            if r:
                return _resultado("link-alternate", href, r, backfill="nao")

    # Passo 3: wp-json (tambem habilita backfill profundo depois).
    if robots_permite(dominio, "/wp-json/wp/v2/posts")[0]:
        r = tentar_wpjson(url_base, dominio)
        if r:
            return _resultado("wp-json", urljoin(url_base, WPJSON), r, backfill="sim")

    return {"metodo": "falhou", "url_feed": "", "itens": "", "validos": "",
            "data_mais_antiga": "", "backfill_wpjson": "nao",
            "detalhe": "nenhum feed encontrado nos passos 1 a 3"}


def _resultado(metodo, url_feed, r, backfill):
    itens, validos, data_antiga = r
    return {
        "metodo": metodo, "url_feed": url_feed, "itens": itens, "validos": validos,
        "data_mais_antiga": data_antiga.date().isoformat() if data_antiga else "",
        "backfill_wpjson": backfill,
        "detalhe": "{}/{} itens com titulo+link+data".format(validos, itens),
    }


def main():
    veiculos = list(csv.DictReader(open(VEICULOS, encoding="utf-8")))
    print("Veiculos a descobrir: {}".format(len(veiculos)), file=sys.stderr)

    with ThreadPoolExecutor(max_workers=4) as pool:
        resultados = list(pool.map(descobrir, veiculos))

    hoje = datetime.now(timezone.utc).date().isoformat()
    for v, r in zip(veiculos, resultados):
        v["status_feed"] = r["metodo"]
        v["url_feed"] = r["url_feed"]
        v["itens_no_feed"] = r["itens"]
        v["data_item_mais_antigo"] = r["data_mais_antiga"]
        v["backfill_wpjson"] = r["backfill_wpjson"]
        v["data_descoberta"] = hoje
        v["detalhe_feed"] = r["detalhe"]
        print("  {:26} {:14} {}".format(v["veiculo"], r["metodo"], r["detalhe"]),
              file=sys.stderr)

    campos = ["veiculo", "pais", "url", "tipo", "prioridade", "status_feed",
              "url_feed", "itens_no_feed", "data_item_mais_antigo",
              "backfill_wpjson", "data_descoberta", "detalhe_feed"]
    with open(VEICULOS, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos, extrasaction="ignore")
        w.writeheader()
        w.writerows(veiculos)

    ok = sum(1 for r in resultados if r["metodo"] != "falhou")
    wp = sum(1 for r in resultados if r["backfill_wpjson"] == "sim")
    print("\n{} de {} com feed; {} com wp-json (backfill profundo possivel)".format(
        ok, len(veiculos), wp), file=sys.stderr)


if __name__ == "__main__":
    main()
