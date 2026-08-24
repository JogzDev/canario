"""Backfill do arquivo editorial via wp-json (§18).

Motivo de existir: a perna editorial nascia com 2 semanas de historia, o que a
deixaria sem z-score e, por tabela, sem ESTADO no app -- porque a §22 exige duas
fontes concordando e a busca sozinha nao basta.

A descoberta de feeds original testava caminhos EM ORDEM e parava no primeiro
que respondia, entao veiculo com `/feed` e `wp-json` foi registrado como
`/feed` e o arquivo profundo dele ficou invisivel. Re-sondando, 7 de 17 tem
wp-json (eu conhecia 2), sendo 4 brasileiros com 5+ anos.

COORTE FIXA, e esta e a decisao importante:

    A serie editorial com z-score e computada sobre um conjunto FIXO de
    veiculos -- os que tem arquivo profundo. Os demais continuam coletados para
    cobertura do presente, mas NAO entram no z.

Sem isso, o passado teria 4 veiculos e o presente teria 19, e o z leria o salto
de volume como sinal: "em alta" para tudo na semana em que os outros entraram.
E o mesmo motivo pelo qual a regra 5 congela o painel de marcas -- "painel
instavel corrompe o z-score" -- aplicado a veiculo.

O backfill vai ate 5 anos, para casar com a janela do Trends e com a validacao
retroativa da §31.
"""

import csv
import json
import os
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coletor_editorial import (limpar, semana_de, carregar_termos_compilados,
                               filtrar_contexto_editorial, JANELA_SEMANAS, SEGMENTO)
from descoberta_feeds import parse_data
from matcher import termos_que_casam
from filtro_genero_editorial import classificar_genero
from teste_30s import buscar
import supabase_rest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VEICULOS = os.path.join(RAIZ, "anexos", "veiculos.csv")
COORTE = os.path.join(RAIZ, "anexos", "coorte_editorial.json")

ANOS = 5
POR_PAGINA = 100
TETO_PAGINAS = 400          # ~40 mil artigos por veiculo; folga de sobra


def tem_wpjson(base, dominio):
    """Descobre se o veiculo expoe wp-json e desde quando."""
    url = base + "/wp-json/wp/v2/posts?per_page=1&order=asc&orderby=date&_fields=date"
    codigo, corpo, _, _ = buscar(url, dominio)
    if codigo not in (200, 206) or not corpo:
        return None
    try:
        posts = json.loads(corpo)
    except ValueError:
        return None
    if not isinstance(posts, list) or not posts:
        return None
    d = parse_data(posts[0].get("date"))
    return d.date() if d else None


def paginar_wpjson(base, dominio, desde):
    """Percorre o arquivo do veiculo, do mais recente para tras, ate `desde`."""
    pagina = 1
    while pagina <= TETO_PAGINAS:
        url = ("{}/wp-json/wp/v2/posts?per_page={}&page={}&orderby=date&order=desc"
               "&after={}T00:00:00&_fields=link,title,excerpt,date_gmt,date".format(
                   base, POR_PAGINA, pagina, desde.isoformat()))
        codigo, corpo, _, _ = buscar(url, dominio)
        if codigo == 400:
            return  # o WordPress devolve 400 quando a pagina passa do fim
        if codigo not in (200, 206) or not corpo:
            return
        try:
            posts = json.loads(corpo)
        except ValueError:
            return
        if not isinstance(posts, list) or not posts:
            return
        for p in posts:
            titulo = p.get("title")
            titulo = titulo.get("rendered") if isinstance(titulo, dict) else titulo
            resumo = p.get("excerpt")
            resumo = resumo.get("rendered") if isinstance(resumo, dict) else resumo
            d = parse_data(p.get("date_gmt") or p.get("date"))
            if titulo and p.get("link") and d:
                yield (limpar(titulo, 300), p["link"], d.date(), limpar(resumo))
        if len(posts) < POR_PAGINA:
            return
        pagina += 1


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    termos, categorias = carregar_termos_compilados()
    desde = date.today() - timedelta(days=365 * ANOS)
    print("Backfill editorial desde {} ({} anos)\n".format(desde, ANOS), file=sys.stderr)

    veiculos = [v for v in csv.DictReader(open(VEICULOS, encoding="utf-8"))
                if v.get("status_feed") not in ("falhou", "pendente", "")
                and v.get("tipo") != "dado_agregado"]

    coorte = []
    artigos, contagem = [], defaultdict(set)
    # Mesma razao do coletor diario: o app precisa nomear quem publicou, nao so
    # contar. Sem isto o backfill sobrescreveria a meta do diario com uma versao
    # mais pobre, porque os dois fazem upsert na mesma chave.
    veiculos_por_celula = defaultdict(lambda: defaultdict(int))
    exemplos = defaultdict(list)
    por_veiculo = {}

    for v in veiculos:
        base = v["url"].rstrip("/")
        dominio = urlparse(base).netloc
        inicio = tem_wpjson(base, dominio)
        if not inicio:
            continue
        # So entra na coorte quem cobre a janela inteira: um veiculo que so
        # comeca no meio reintroduz o salto que a coorte fixa existe para evitar.
        cobre = inicio <= desde
        fonte = "editorial_br" if (v.get("pais") or "").upper() == "BR" else "editorial_intl"
        if not cobre:
            print("  {:24} arquivo so desde {} -- FORA da coorte".format(
                v["veiculo"][:24], inicio), file=sys.stderr)
            por_veiculo[v["veiculo"]] = {"itens": 0, "motivo": "arquivo curto"}
            continue

        n = 0
        for titulo, link, quando, resumo in paginar_wpjson(base, dominio, desde):
            genero = classificar_genero(titulo, v.get("foco_genero"))
            artigos.append({"veiculo": v["veiculo"], "url": link,
                            "titulo": titulo[:500], "data_pub": quando.isoformat(),
                            "publico_editorial": genero["publico"],
                            "pontos_femininos": genero["pontos_femininos"],
                            "pontos_masculinos": genero["pontos_masculinos"]})
            if genero["publico"] == "masculino":
                n += 1
                continue
            achados = filtrar_contexto_editorial(
                titulo, resumo,
                termos_que_casam(titulo + " " + resumo, termos), categorias)
            if achados:
                semana = semana_de(quando)
                for termo_id in achados:
                    celula = (termo_id, fonte, semana)
                    if link not in contagem[celula]:
                        veiculos_por_celula[celula][v["veiculo"]] += 1
                        if len(exemplos[celula]) < 3:
                            exemplos[celula].append({"veiculo": v["veiculo"],
                                                     "titulo": titulo[:160],
                                                     "url": link})
                    contagem[celula].add(link)
            n += 1
        coorte.append({"veiculo": v["veiculo"], "fonte": fonte,
                       "arquivo_desde": inicio.isoformat(), "artigos": n})
        por_veiculo[v["veiculo"]] = {"itens": n, "motivo": None}
        print("  {:24} {:6} artigos desde {}  [{}]".format(
            v["veiculo"][:24], n, desde, fonte), file=sys.stderr)

    if not coorte:
        print("\nNenhum veiculo cobre a janela inteira. Coorte vazia.", file=sys.stderr)
        return 0

    # --- grava artigos (so metadados; §18 proibe o texto integral) ---
    vistos, unicos = set(), []
    for a in artigos:
        if a["url"] not in vistos:
            vistos.add(a["url"])
            unicos.append(a)
    for i in range(0, len(unicos), 500):
        supabase_rest.inserir_ignorando_existentes(
            "artigos", unicos[i:i + 500], on_conflict="url")

    # --- serie em janela movel de 4 semanas (§18), coorte fixa ---
    crua = dict((k, len(v)) for k, v in contagem.items())
    agora = datetime.now(timezone.utc).isoformat()
    nomes = sorted(c["veiculo"] for c in coorte)
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
                     "unidade": "materias que citaram o termo",
                     "veiculos": dict(sorted(
                         veiculos_por_celula[(termo_id, fonte, semana)].items(),
                         key=lambda kv: (-kv[1], kv[0]))),
                     "exemplos": exemplos[(termo_id, fonte, semana)],
                     "coorte_fixa": nomes,
                     "obs": "coorte FIXA de veiculos com arquivo profundo: sem isso "
                            "o passado teria 4 veiculos e o presente 19, e o z leria "
                            "o salto de volume como sinal (mesma logica da regra 5)",
                     "coletado_em": agora},
        })
    for i in range(0, len(linhas), 500):
        supabase_rest.upsert("series_semanais", linhas[i:i + 500],
                             on_conflict="termo_id,segmento,fonte,semana")

    with open(COORTE, "w", encoding="utf-8") as f:
        json.dump({"definida_em": date.today().isoformat(),
                   "janela_anos": ANOS,
                   "criterio": "expoe wp-json E cobre a janela inteira",
                   "veiculos": coorte}, f, ensure_ascii=False, indent=1)

    semanas = sorted({k[2] for k in crua})
    print("\n{} artigos unicos, {} pontos de serie.".format(len(unicos), len(linhas)),
          file=sys.stderr)
    if semanas:
        print("Semanas cobertas: {} a {} ({} semanas)".format(
            semanas[0], semanas[-1], len(semanas)), file=sys.stderr)
    print("Coorte fixa: {}".format(", ".join(nomes)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
