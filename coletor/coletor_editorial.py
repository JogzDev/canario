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
import re
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from descoberta_feeds import parse_data  # noqa: E402
from teste_30s import buscar, robots_permite  # noqa: E402
from matcher import compilar_lista, termos_que_casam  # noqa: E402
from filtro_genero_editorial import classificar_genero  # noqa: E402
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


def filtrar_contexto_editorial(titulo, resumo, achados, categorias,
                               achados_no_titulo=None):
    """Recusa categoria citada fora de contexto de vestuário.

    O falso positivo que motivou a trava foi real: a Harper's Bazaar publicou
    um perfil do Vini Jr.; "camisa 7" era posição no futebol, mas virou sinal de
    `camisa` no índice de moda. Exigir apenas alguma categoria no artigo não
    resolve, porque a própria palavra ambígua é a categoria.

    A coleta ainda casa título + resumo, mas o artigo só entra se o TÍTULO
    declarar uma peça ou intenção editorial de moda. Resumo é útil para achar
    atributos de uma matéria pertinente; não pode transformar uma notícia de
    gravidez, futebol ou viagem em matéria de moda só porque descreveu a roupa
    de alguém numa frase lateral.

    `achados_no_titulo` vem do mesmo matcher da taxonomia e é aceito como
    argumento para tornar essa separação auditável nos testes. A decisão final
    usa também um vocabulário estreito de intenção de moda, pois vários termos
    da taxonomia ("top", "longo", "social") são palavras comuns fora dela.
    """
    categorias_achadas = achados & categorias
    if not achados or not categorias_achadas:
        return set()
    achados_no_titulo = set(achados_no_titulo or ())
    titulo_limpo = limpar(titulo or "").lower()
    contexto_forte = (
        "moda", "fashion", "look", "looks", "roupa", "roupas", "outfit",
        "outfits", "style", "estilo", "tendencia", "tendência", "trend",
        "trends", "colecao", "coleção", "collection", "runway", "passarela",
        "wear", "wearing", "styling", "alfaiataria", "fashion week",
        "streetwear", "street style", "wardrobe", "closet", "fw26", "ss27",
    )
    evidencia_de_peca_no_titulo = (
        "vestido", "vestidos", "saia", "saias", "calca", "calça", "calcas",
        "calças", "short", "shorts", "bermuda", "bermudas", "blusa",
        "blusas", "crop top", "tank top", "camiseta", "camisetas", "t-shirt",
        "t-shirts", "jaqueta", "jaquetas", "casaco", "casacos", "blazer",
        "blazers", "macacao", "macacão", "macacoes", "macacões", "jeans",
        "trico", "tricô", "croche", "crochê", "alfaiataria", "manga", "gola",
        "tecido", "silhueta", "estampa", "shirt", "shirts", "blouse",
        "blouses", "skirt", "skirts", "pants", "trousers", "dress", "dresses",
        "gown", "gowns", "jumpsuit", "jumpsuits", "jacket", "jackets", "coat",
        "coats", "sleeve", "collar", "fabric", "silhouette", "print", "denim",
    )
    metaforas_recusadas = (
        r"\bcamisa\s+(?:\d+|do time|da empresa|da campanha)\b",
        r"\bvestir?\s+a\s+camisa\s+(?:da|do)\b",
        r"\bwear\s+the\s+company\s+shirt\b",
    )
    if any(re.search(p, titulo_limpo) for p in metaforas_recusadas):
        return set()

    titulo_declara_moda = any(
        re.search(r"\b{}\b".format(re.escape(p)), titulo_limpo)
        for p in contexto_forte + evidencia_de_peca_no_titulo)
    categorias_no_titulo = achados_no_titulo & categorias
    # `top` também significa modelo/celebridade e ranking. Só ele não prova
    # uma blusa; construções inequívocas como crop top/tank top já estão no
    # vocabulário de peça acima.
    top_ambiguo = (
        categorias_no_titulo == {"blusa_top"}
        and re.search(r"\btops?\b", titulo_limpo)
        and not re.search(r"\b(?:crop|tank)\s+tops?\b", titulo_limpo)
    )
    titulo_declara_categoria = bool(categorias_no_titulo) and not top_ambiguo
    if titulo_declara_moda or titulo_declara_categoria:
        return achados
    return set()


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
    # (termo_id, fonte, semana) -> {veiculo: n}. O app precisa NOMEAR as fontes:
    # "baseado em: editorial BR" nao diz nada a quem compra colecao, "Elle
    # Brasil (4) e Vogue Brasil (2)" diz. A regra 3 pede o caminho ate a origem,
    # e ate agora a origem parava no rotulo da perna.
    veiculos_por_celula = defaultdict(lambda: defaultdict(int))
    # Ate 3 manchetes por celula, para a tela mostrar o que o bot leu.
    exemplos = defaultdict(list)
    por_veiculo = {}
    # Semanas que a perna efetivamente observou, mesmo quando nenhum termo
    # casou. Elas permitem publicar ZERO explícito e, sobretudo, sobrescrever
    # um falso positivo de uma coleta anterior. Antes, corrigir o filtro não
    # limpava "camisa 7": a célula velha ficava no banco para sempre porque o
    # coletor só fazia upsert das células que ainda tinham match.
    semanas_observadas = defaultdict(set)

    for v in veiculos:
        itens, erro = itens_do_feed(v)
        if erro:
            por_veiculo[v["veiculo"]] = {"itens": 0, "casados": 0, "erro": erro}
            print("  {:24} {}".format(v["veiculo"][:24], erro), file=sys.stderr)
            continue

        fonte = "editorial_br" if (v.get("pais") or "").upper() == "BR" else "editorial_intl"
        casados = 0
        descartados_masculinos = 0
        for titulo, link, quando, resumo in itens:
            genero = classificar_genero(titulo, v.get("foco_genero"))
            artigos_novos.append({"veiculo": v["veiculo"], "url": link,
                                  "titulo": titulo[:500],
                                  "data_pub": quando.isoformat(),
                                  "publico_editorial": genero["publico"],
                                  "pontos_femininos": genero["pontos_femininos"],
                                  "pontos_masculinos": genero["pontos_masculinos"]})
            if genero["publico"] == "masculino":
                descartados_masculinos += 1
                continue
            semana = semana_de(quando)
            semanas_observadas[fonte].add(semana)
            # K8: titulo + resumo, nunca o texto integral (§18).
            achados_titulo = termos_que_casam(titulo, termos)
            achados = filtrar_contexto_editorial(
                titulo, resumo,
                termos_que_casam(titulo + " " + limpar(resumo), termos), categorias,
                achados_no_titulo=achados_titulo)
            if not achados:
                continue
            casados += 1
            for termo_id in achados:
                # §11: conjunto de artigos, entao o mesmo artigo conta 1 por
                # termo mesmo que varias palavras do termo aparecam.
                celula = (termo_id, fonte, semana)
                if link not in contagem[celula]:
                    veiculos_por_celula[celula][v["veiculo"]] += 1
                    if len(exemplos[celula]) < 3:
                        exemplos[celula].append({"veiculo": v["veiculo"],
                                                 "titulo": titulo[:160],
                                                 "url": link})
                contagem[celula].add(link)
        por_veiculo[v["veiculo"]] = {"itens": len(itens), "casados": casados,
                                     "masculinos": descartados_masculinos,
                                     "erro": None, "fonte": fonte}
        print("  {:24} {:4} itens, {:3} masc. fora, {:4} com termo  ({})".format(
            v["veiculo"][:24], len(itens), descartados_masculinos, casados, fonte),
            file=sys.stderr)

    # --- artigos (so metadados; §18 proibe o texto) ---
    vistos = set()
    unicos = []
    for a in artigos_novos:
        if a["url"] in vistos:
            continue
        vistos.add(a["url"])
        unicos.append(a)
    # Artigo ja gravado NAO e reescrito: os feeds devolvem os mesmos itens por
    # varios dias, e reescrever a linha inteira para gravar o titulo identico
    # que ja estava la custava versao de linha nova a cada coleta.
    for i in range(0, len(unicos), 500):
        supabase_rest.inserir_ignorando_existentes(
            "artigos", unicos[i:i + 500], on_conflict="url")

    # --- serie editorial em janela movel de 4 semanas (§18) ---
    # A semana crua tambem vai gravada, porque o `pico` (C4) precisa dela.
    crua = dict((k, len(v)) for k, v in contagem.items())
    semanas = sorted({s for conjunto in semanas_observadas.values() for s in conjunto})
    agora = datetime.now(timezone.utc).isoformat()
    linhas = []
    # Só materializa todos os zeros na semana MAIS NOVA de cada perna. Feeds
    # curtos deixam artigos antigos cair; zerar toda semana histórica vista por
    # qualquer outro veículo apagaria uma contagem legítima que já saiu do feed.
    # A semana nova, ao contrário, está inteira na execução corrente e pode
    # substituir com segurança uma célula que o filtro antigo contaminou.
    celulas_observadas = set(crua)
    for fonte, semanas_da_fonte in semanas_observadas.items():
        if semanas_da_fonte:
            semana_mais_nova = max(semanas_da_fonte)
            celulas_observadas.update(
                (termo_id, fonte, semana_mais_nova) for termo_id in termos)
    for (termo_id, fonte, semana) in sorted(celulas_observadas):
        janela = [crua.get((termo_id, fonte, semana - timedelta(weeks=w)), 0)
                  for w in range(JANELA_SEMANAS)]
        contagem_crua = crua.get((termo_id, fonte, semana), 0)
        linhas.append({
            "termo_id": termo_id, "segmento": SEGMENTO, "fonte": fonte,
            "semana": semana.isoformat(),
            # VALOR DE PASSAGEM, e' o motor que normaliza (§33).
            #
            # Aqui havia `sum(janela) / JANELA_SEMANAS` -- divisao pelo numero
            # de SEMANAS -- e isso e' contagem absoluta, nao share de coisa
            # nenhuma, apesar de o docstring deste arquivo e o nome do workflow
            # dizerem "share of voice" desde sempre.
            #
            # O estrago era mensuravel: quando Marie Claire, Vogue Brasil e
            # Glamour entraram entre 23 e 27/07, o denominador BR foi de ~460
            # para 896 materias em uma semana (+90%). Todo termo subiu junto
            # sem o mercado ter se mexido, e quatro `pico` acenderam. Nos
            # veiculos que ja eram medidos, a cobertura daqueles termos naquela
            # semana caiu para 1 artigo -- o menor de toda a serie.
            #
            # O share NAO e' calculado aqui de proposito: o denominador e o
            # total de materias da perna na janela de 4 semanas, e o coletor so
            # enxerga o feed recente. Quem tem a serie inteira e o banco, entao
            # quem divide e `computar_serie_editorial()`, no motor. Enquanto
            # ela nao roda, este campo e a contagem crua.
            "valor_bruto": sum(janela),
            "z": None, "n_amostra": sum(janela),
            "meta": {"janela_semanas": JANELA_SEMANAS,
                     "normalizacao": "pendente: computar_serie_editorial()",
                     "contagem_semana_crua": contagem_crua,
                     "unidade": "materias que citaram o termo",
                     "veiculos": dict(sorted(
                         veiculos_por_celula[(termo_id, fonte, semana)].items(),
                         key=lambda kv: (-kv[1], kv[0]))),
                     "exemplos": exemplos[(termo_id, fonte, semana)],
                     "contexto_editorial": "moda_declarada_no_titulo",
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
