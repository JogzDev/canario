"""Coletor da perna editorial (§18), share of voice por termo.

Le os feeds descobertos em `anexos/veiculos.csv`, casa titulo + resumo contra as
palavras da taxonomia aprovada e grava uma linha por (veiculo, artigo, termo).

Regras que este modulo cumpre:
  * §18 -- NAO armazena o texto integral do artigo (obra protegida e peso
    inutil). Processa em memoria e persiste so titulo, link, data, veiculo e as
    contagens.
  * §11 -- CONTAGEM UNICA por termo por artigo: "manga bufante" e "puff sleeve"
    no mesmo artigo contam 1. Garantido pelo `matcher`, que devolve conjunto de
    termos, nao de ocorrencias.
  * §18 -- a perna editorial trabalha em JANELA MOVEL DE 4 SEMANAS, porque
    volume editorial e baixo e semana crua e ruido. Mas o `pico` (C4) e
    calculado sobre a semana CRUA, entao as duas coisas sao gravadas:
    `editorial_br`/`editorial_intl` recebem a janela de 4 semanas, e a semana
    crua fica em `meta.contagem_semana_crua`.
  * ambiguidade 2 -- separa `editorial_br` de `editorial_intl`: 11 dos 19
    veiculos sao internacionais, e com peso igual a imprensa estrangeira
    decidiria um indice de mid-market brasileiro. A divergencia entre as duas
    series e justamente o sinal de antecipacao que interessa ao comercial.
  * C5 -- Lyst (`tipo=dado_agregado`) fica FORA da soma editorial.
  * K8 -- casa apenas titulo + resumo do feed: uniforme entre veiculos e imune a
    paywall (BoF, WWD e Vogue Business sao pagos).
  * regra 7 -- 1 req/s por dominio, User-Agent identificavel, robots.txt.
"""

import csv
import json
import os
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from descoberta_feeds import parse_data  # noqa: E402
from teste_30s import buscar, robots_permite  # noqa: E402
from matcher import compilar_lista, termos_que_casam  # noqa: E402
import supabase_rest  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VEICULOS = os.path.join(RAIZ, "anexos", "veiculos.csv")

JANELA_SEMANAS = 4          # §18: janela movel da perna editorial
SEGMENTO = "feminino_casual_br"


def semana_de(d):
    """Segunda-feira ISO da data."""
    return d - timedelta(days=d.weekday())


def limpar(texto, teto=600):
    """Tira marcacao HTML e limita o tamanho do resumo.

    Feed de veiculo grande vem com HTML no resumo; sem limpar, o matching casa
    em atributo de tag e em texto de navegacao.
    """
    import html as _html
    import re as _re
    if not texto:
        return ""
    t = _re.sub(r"<[^>]+>", " ", texto)
    t = _html.unescape(t)
    return _re.sub(r"\s+", " ", t).strip()[:teto]


def itens_do_feed(veiculo):
    """Baixa o feed e devolve [(titulo, link, data, resumo)].

    Reaproveita o parser da descoberta de feeds, mas aqui precisamos tambem do
    resumo (K8: titulo + resumo e a entrada do matching).
    """
    url = (veiculo.get("url_feed") or "").strip()
    if not url:
        return [], "sem url_feed (rodar a descoberta primeiro)"
    from urllib.parse import urlparse
    dominio = urlparse(url).netloc
    if not robots_permite(dominio, urlparse(url).path)[0]:
        return [], "robots proibe o feed"

    codigo, corpo, _, _ = buscar(url, dominio)
    if codigo not in (200, 206) or not corpo:
        return [], "feed http {}".format(codigo)

    metodo = (veiculo.get("status_feed") or "").strip()
    if metodo == "wp-json":
        try:
            posts = json.loads(corpo)
        except ValueError:
            return [], "wp-json nao-json"
        saida = []
        for p in posts if isinstance(posts, list) else []:
            titulo = p.get("title")
            titulo = titulo.get("rendered") if isinstance(titulo, dict) else titulo
            resumo = p.get("excerpt")
            resumo = resumo.get("rendered") if isinstance(resumo, dict) else (resumo or "")
            d = parse_data(p.get("date_gmt") or p.get("date"))
            if titulo and p.get("link") and d:
                saida.append((titulo, p["link"], d.date(), limpar(resumo)))
        return saida, ""

    return _itens_xml(corpo)


def _itens_xml(corpo):
    """RSS/Atom -> itens com titulo, link, data e resumo."""
    from xml.etree import ElementTree as ET
    try:
        raiz = ET.fromstring(corpo.encode("utf-8"))
    except ET.ParseError:
        return [], "feed nao e XML valido"

    def tag(e):
        return e.tag.split("}")[-1].lower()

    saida = []
    for elem in raiz.iter():
        if tag(elem) not in ("item", "entry"):
            continue
        titulo = link = resumo = None
        quando = None
        for filho in elem:
            t = tag(filho)
            if t == "title":
                titulo = (filho.text or "").strip()
            elif t == "link":
                link = (filho.text or filho.get("href") or "").strip()
            elif t in ("description", "summary"):
                # SO description/summary. `content:encoded` traz o artigo
                # inteiro em HTML, e usa-lo violaria o K8 (titulo + resumo) e
                # encheria o matching de navegacao e texto solto -- foi o que
                # fez 84% dos artigos da Vogue casarem com algum termo em
                # 30/07, ou seja, ruido no lugar de sinal.
                resumo = ((resumo or "") + " " + (filho.text or "")).strip()
            elif t in ("pubdate", "published", "updated", "date"):
                quando = quando or parse_data(filho.text)
        if titulo and link and quando:
            saida.append((titulo, link, quando.date(), resumo or ""))
    return saida, ""


def carregar_termos_compilados():
    """Termos aprovados -> ({termo: regexes}, conjunto de ids de categoria)."""
    aprovados = supabase_rest.selecionar(
        "termos", "?status=eq.aprovado&select=id,palavras_pt,palavras_en,rotulo,dimensao")
    categorias = {t["id"] for t in aprovados if t.get("dimensao") == "categoria"}
    compilados = {}
    for t in aprovados:
        padroes = []
        for campo in ("palavras_pt", "palavras_en"):
            valor = (t.get(campo) or "").strip()
            if valor:
                padroes.extend(p for p in valor.split("|") if p.strip())
        # O rotulo tambem vale como palavra: "Animal print" aparece assim no texto.
        if t.get("rotulo"):
            padroes.append(t["rotulo"])
        regexes = compilar_lista(padroes)
        if regexes:
            compilados[t["id"]] = regexes
    return compilados, categorias


def filtrar_por_categoria(achados, categorias):
    """§11: "Categoria e filtro, nao sinal."

    O documento e explicito -- "floral em alta" nao significa nada; "floral em
    alta dentro de vestidos" significa. Entao atributo so conta quando alguma
    CATEGORIA aparece no mesmo artigo.

    Sem isto, uma materia sobre mansao casava com `basico`, `longo` e
    `vermelho_rosa`, e uma sobre batom casava com `alfaiataria` e `festa_brilho`:
    palavras comuns do portugues ("ao longo de", "vida social") entrando no
    indice como se fossem desejo por peca.
    """
    if not achados:
        return set()
    if not (achados & categorias):
        return set()
    return achados


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    termos, categorias = carregar_termos_compilados()
    if not termos:
        print("Nenhum termo aprovado com palavras. Nada a casar.", file=sys.stderr)
        return 0
    print("Termos aprovados com palavras: {}".format(len(termos)), file=sys.stderr)

    veiculos = [v for v in csv.DictReader(open(VEICULOS, encoding="utf-8"))
                if v.get("status_feed") not in ("falhou", "pendente", "")
                # C5: Lyst e dado agregado, nao editorial. Fica fora da soma.
                and v.get("tipo") != "dado_agregado"]
    print("Veiculos com feed: {}".format(len(veiculos)), file=sys.stderr)

    artigos_novos = []
    # (termo_id, fonte, semana) -> numero de artigos distintos
    contagem = defaultdict(set)
    por_veiculo = {}

    for v in veiculos:
        itens, erro = itens_do_feed(v)
        if erro:
            por_veiculo[v["veiculo"]] = {"itens": 0, "casados": 0, "erro": erro}
            print("  {:24} {}".format(v["veiculo"][:24], erro), file=sys.stderr)
            continue

        fonte = "editorial_br" if (v.get("pais") or "").upper() == "BR" else "editorial_intl"
        casados = 0
        for titulo, link, quando, resumo in itens:
            # K8: titulo + resumo, nunca o texto integral (§18).
            achados = filtrar_por_categoria(
                termos_que_casam(titulo + " " + limpar(resumo), termos), categorias)
            artigos_novos.append({"veiculo": v["veiculo"], "url": link,
                                  "titulo": titulo[:500],
                                  "data_pub": quando.isoformat()})
            if not achados:
                continue
            casados += 1
            semana = semana_de(quando)
            for termo_id in achados:
                # §11: conjunto de artigos, entao o mesmo artigo conta 1 por
                # termo mesmo que varias palavras do termo aparecam.
                contagem[(termo_id, fonte, semana)].add(link)
        por_veiculo[v["veiculo"]] = {"itens": len(itens), "casados": casados,
                                     "erro": None, "fonte": fonte}
        print("  {:24} {:4} itens, {:4} com termo  ({})".format(
            v["veiculo"][:24], len(itens), casados, fonte), file=sys.stderr)

    # --- artigos (so metadados; §18 proibe o texto) ---
    vistos = set()
    unicos = []
    for a in artigos_novos:
        if a["url"] in vistos:
            continue
        vistos.add(a["url"])
        unicos.append(a)
    for i in range(0, len(unicos), 500):
        supabase_rest.upsert("artigos", unicos[i:i + 500], on_conflict="url")

    # --- serie editorial em janela movel de 4 semanas (§18) ---
    # A semana crua tambem vai gravada, porque o `pico` (C4) precisa dela.
    crua = dict((k, len(v)) for k, v in contagem.items())
    semanas = sorted({k[2] for k in crua})
    agora = datetime.now(timezone.utc).isoformat()
    linhas = []
    for (termo_id, fonte, semana) in sorted(crua):
        janela = [crua.get((termo_id, fonte, semana - timedelta(weeks=w)), 0)
                  for w in range(JANELA_SEMANAS)]
        linhas.append({
            "termo_id": termo_id, "segmento": SEGMENTO, "fonte": fonte,
            "semana": semana.isoformat(),
            "valor_bruto": sum(janela) / float(JANELA_SEMANAS),
            "z": None, "n_amostra": sum(janela),
            "meta": {"janela_semanas": JANELA_SEMANAS,
                     "contagem_semana_crua": crua[(termo_id, fonte, semana)],
                     "obs": "valor_bruto e a media da janela de 4 semanas (§18); "
                            "a semana crua serve ao estado `pico` (C4)",
                     "coletado_em": agora},
        })
    for i in range(0, len(linhas), 500):
        supabase_rest.upsert("series_semanais", linhas[i:i + 500],
                             on_conflict="termo_id,segmento,fonte,semana")

    # --- saude (§20): UMA linha por dia para a fonte editorial ---
    # Nao uma por veiculo: a chave unica e (data, fonte, marca_id) e marca_id e
    # nulo aqui -- em Postgres NULL nao conflita com NULL, entao 17 linhas
    # entrariam duplicadas todo dia em vez de atualizar. O detalhe por veiculo
    # vai no jsonb de alertas, que e onde §20 quer o diagnostico.
    hoje = date.today()
    com_erro = {n: m["erro"] for n, m in por_veiculo.items() if m["erro"]}
    zerados = [n for n, m in por_veiculo.items()
               if not m["erro"] and m["itens"] == 0]
    supabase_rest.upsert("saude", [{
        "data": hoje.isoformat(), "fonte": "editorial", "marca_id": None,
        "itens": sum(m["itens"] for m in por_veiculo.values()),
        "visitados": len(por_veiculo),
        "gravados": sum(m["casados"] for m in por_veiculo.values()),
        "pct_campos_ok": (round(
            sum(1 for m in por_veiculo.values() if not m["erro"])
            / float(len(por_veiculo)), 3) if por_veiculo else None),
        "alertas": {"veiculos_com_erro": com_erro or None,
                    "veiculos_sem_itens": zerados or None,
                    "por_veiculo": {n: m["itens"] for n, m in por_veiculo.items()}},
    }], on_conflict="data,fonte,marca_id")

    br = sum(1 for k in crua if k[1] == "editorial_br")
    intl = sum(1 for k in crua if k[1] == "editorial_intl")
    print("\n{} artigos únicos, {} pontos de série ({} BR, {} internacional).".format(
        len(unicos), len(linhas), br, intl), file=sys.stderr)
    if semanas:
        print("Semanas cobertas: {} a {}".format(semanas[0], semanas[-1]),
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
