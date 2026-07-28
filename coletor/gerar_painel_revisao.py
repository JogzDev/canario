"""Gera a pagina local de revisao da taxonomia + verificacao do Trends.

Existe porque abrir os links do Trends dentro do app trava com 429: o Google
limita requisicao automatizada. Aberta no navegador padrao, com a sessao do
usuario, a consulta e uma pessoa navegando e funciona normalmente.

A pagina e um ARQUIVO LOCAL: nada sobe para lugar nenhum.

Rodar: python3 coletor/gerar_painel_revisao.py
Abrir: open VERIFICACAO_TRENDS.html
"""

import csv
import html
import os
import sys
import urllib.parse

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAXONOMIA = os.path.join(RAIZ, "anexos", "taxonomia.csv")
SAIDA = os.path.join(RAIZ, "VERIFICACAO_TRENDS.html")

ANCORA = "vestido floral"
POR_GRUPO = 5

ORDEM_DIM = ["categoria", "estampa", "tecido", "comprimento", "silhueta",
             "cintura", "estetica", "cor"]

CSS = """
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body { margin:0; padding:2rem 1.25rem 4rem; font:16px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       max-width:1100px; margin-inline:auto; background:#fff; color:#1a1a1a; }
@media (prefers-color-scheme: dark){ body{ background:#15171a; color:#e8e6e3; } }
h1 { font-size:1.9rem; margin:0 0 .25rem; letter-spacing:-.02em; }
h2 { font-size:1.3rem; margin:2.5rem 0 .75rem; padding-bottom:.4rem; border-bottom:2px solid currentColor; }
h3 { font-size:1.05rem; margin:1.5rem 0 .5rem; }
.sub { opacity:.7; margin:0 0 1.5rem; }
.resumo { display:flex; gap:.75rem; flex-wrap:wrap; margin:1.25rem 0 2rem; }
.card { border:1px solid rgba(128,128,128,.35); border-radius:10px; padding:.7rem 1rem; min-width:120px; }
.card b { display:block; font-size:1.5rem; line-height:1.2; }
.card span { font-size:.8rem; opacity:.7; text-transform:uppercase; letter-spacing:.04em; }
.wrap { overflow-x:auto; -webkit-overflow-scrolling:touch; margin:.5rem 0 1rem; }
table { border-collapse:collapse; width:100%; font-size:.88rem; min-width:640px; }
th,td { text-align:left; padding:.45rem .6rem; border-bottom:1px solid rgba(128,128,128,.25); vertical-align:top; }
th { font-size:.72rem; text-transform:uppercase; letter-spacing:.05em; opacity:.65; font-weight:600; }
code { font:.85em ui-monospace,SFMono-Regular,Menlo,monospace; background:rgba(128,128,128,.15);
       padding:.12em .4em; border-radius:4px; }
.novo { background:rgba(46,160,67,.16); }
.corrigido { background:rgba(219,154,4,.16); }
.tag { font-size:.68rem; font-weight:700; padding:.1rem .4rem; border-radius:4px; text-transform:uppercase; letter-spacing:.03em; }
.tag.n { background:#2ea043; color:#fff; }
.tag.c { background:#db9a04; color:#000; }
.dim-meta { font-size:.85rem; opacity:.75; margin:.15rem 0 .6rem; }
.btn { display:inline-block; background:#1f6feb; color:#fff !important; text-decoration:none;
       padding:.6rem 1.1rem; border-radius:8px; font-weight:600; font-size:.92rem; margin:.35rem 0; }
.btn:hover { background:#1858c4; }
.grupo { border:1px solid rgba(128,128,128,.3); border-radius:12px; padding:1rem 1.25rem; margin:1rem 0; }
.aviso { border-left:4px solid #db9a04; padding:.75rem 1rem; margin:1.25rem 0;
         background:rgba(219,154,4,.09); border-radius:0 8px 8px 0; }
ul { padding-left:1.2rem; }
li { margin:.3rem 0; }
"""

# Marcados na revisao de 28/07.
NOVOS = {"macacao", "xadrez", "cintura_alta", "cinza", "amarelo_laranja", "outras_cores"}
CORRIGIDOS = {"trico_croche", "boho_artesanal", "animal_print", "reta_wide", "jeans",
              "geometrica", "festa_brilho"}


def url_trends(termos):
    q = ",".join(urllib.parse.quote(t) for t in termos)
    return ("https://trends.google.com.br/trends/explore"
            "?date=today%205-y&geo=BR&hl=pt-BR&q={}".format(q))


def e(s):
    return html.escape(s or "")


def main():
    linhas = list(csv.DictReader(open(TAXONOMIA, encoding="utf-8")))
    por_dim = {}
    for r in linhas:
        por_dim.setdefault(r["dimensao"], []).append(r)

    termos_busca = [r for r in linhas if r["termo_busca"].strip()]
    fila = [r for r in termos_busca if r["termo_busca"] != ANCORA]
    grupos = [fila[i:i + (POR_GRUPO - 1)] for i in range(0, len(fila), POR_GRUPO - 1)]

    h = []
    h.append("<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>")
    h.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    h.append("<title>Canário — taxonomia e verificação do Trends</title>")
    h.append("<style>{}</style></head><body>".format(CSS))

    h.append("<h1>Taxonomia do Canário</h1>")
    h.append("<p class='sub'>Revisão de 28/07/2026 &middot; arquivo local, não sobe para lugar nenhum</p>")

    aprovados = sum(1 for r in linhas if r["status"] == "aprovado")
    h.append("<div class='resumo'>")
    for valor, rotulo in [(len(linhas), "termos"), (len(por_dim), "dimensões"),
                          (aprovados, "aprovados"), (len(NOVOS), "novos"),
                          (len(CORRIGIDOS), "corrigidos")]:
        h.append("<div class='card'><b>{}</b><span>{}</span></div>".format(valor, rotulo))
    h.append("</div>")

    h.append("<div class='aviso'><b>Sobre a aprovação:</b> os 41 termos estão "
             "<code>aprovado</code>. A perna <b>editorial</b> já pode andar, porque o "
             "casamento editorial usa <code>palavras_pt</code>/<code>palavras_en</code> e "
             "nunca toca em <code>termo_busca</code>. A perna de <b>busca</b> ainda depende "
             "da verificação abaixo — é ela que consome <code>termo_busca</code>. Um termo "
             "aprovado pode virar <code>sem_perna_busca=sim</code> depois da verificação sem "
             "perder a aprovação.</div>")

    # --- Taxonomia por dimensao ---
    h.append("<h2>A taxonomia, por dimensão</h2>")
    h.append("<p><span class='tag n'>novo</span> entrou em 28/07 &nbsp; "
             "<span class='tag c'>corrigido</span> teve termo_busca ou palavras alteradas</p>")

    for dim in ORDEM_DIM:
        rows = por_dim.get(dim, [])
        if not rows:
            continue
        exclusiva = rows[0]["exclusiva"]
        ancoras = sorted({r["termo_busca"].split()[0] for r in rows if r["termo_busca"]})
        h.append("<h3>{} <span style='opacity:.6;font-weight:400'>&mdash; {} termos</span></h3>".format(
            e(dim), len(rows)))
        h.append("<p class='dim-meta'>exclusiva: <b>{}</b> &nbsp;&middot;&nbsp; âncora: <code>{}</code></p>".format(
            "sim" if exclusiva == "sim" else "não (pode ter mais de um)",
            e(", ".join(ancoras)) or "—"))
        h.append("<div class='wrap'><table><thead><tr>"
                 "<th>id</th><th>rótulo</th><th>termo_busca</th>"
                 "<th>sinônimos</th><th>palavras_pt</th><th>palavras_en</th>"
                 "</tr></thead><tbody>")
        for r in rows:
            cls = "novo" if r["id"] in NOVOS else ("corrigido" if r["id"] in CORRIGIDOS else "")
            tag = ""
            if r["id"] in NOVOS:
                tag = " <span class='tag n'>novo</span>"
            elif r["id"] in CORRIGIDOS:
                tag = " <span class='tag c'>corrigido</span>"
            h.append("<tr class='{}'>".format(cls))
            h.append("<td><code>{}</code>{}</td>".format(e(r["id"]), tag))
            h.append("<td>{}</td>".format(e(r["rotulo"])))
            h.append("<td><code>{}</code></td>".format(e(r["termo_busca"]) or "—"))
            h.append("<td>{}</td>".format(e(r["sinonimos"].replace("|", ", ")) or "—"))
            h.append("<td>{}</td>".format(e(r["palavras_pt"].replace("|", ", ")) or "—"))
            h.append("<td>{}</td>".format(e(r["palavras_en"].replace("|", ", ")) or "—"))
            h.append("</tr>")
            if r["motivo"].strip():
                h.append("<tr class='{}'><td></td><td colspan='5' style='opacity:.72;font-size:.85em'>{}</td></tr>".format(
                    cls, e(r["motivo"])))
        h.append("</tbody></table></div>")

    # --- Verificacao do Trends ---
    h.append("<h2>Verificação do Trends &mdash; {} grupos</h2>".format(len(grupos)))
    h.append("<p>Âncora fixa: <code>{}</code>, presente em todos os grupos para os níveis "
             "serem comparáveis entre eles (K7). Não troque a âncora no meio.</p>".format(e(ANCORA)))
    h.append("<p>Cada link já vem com <b>Brasil</b>, <b>5 anos</b> e <b>pt-BR</b> aplicados. "
             "Para cada termo, decida:</p>")
    h.append("<ul>"
             "<li><b>ok</b> — série com volume visível e forma plausível;</li>"
             "<li><b>morto</b> — achatada no zero; vira <code>sem_perna_busca=sim</code> e o termo "
             "anda nas pernas de varejo e editorial;</li>"
             "<li><b>contaminado</b> — tem volume, mas o pico não é de moda (veja "
             "\"consultas relacionadas\": se aparecer receita, decoração ou tutorial, é isso).</li>"
             "</ul>")
    h.append("<p>Me devolva os vereditos em texto solto mesmo &mdash; eu aplico no CSV e no banco.</p>")

    for i, grupo in enumerate(grupos, 1):
        consulta = [ANCORA] + [r["termo_busca"] for r in grupo]
        dims = sorted({r["dimensao"] for r in grupo})
        h.append("<div class='grupo'>")
        h.append("<h3>Grupo {} de {} <span style='opacity:.6;font-weight:400'>&mdash; {}</span></h3>".format(
            i, len(grupos), e(", ".join(dims))))
        h.append("<a class='btn' href='{}' target='_blank' rel='noopener'>Abrir no Google Trends &rarr;</a>".format(
            url_trends(consulta)))
        h.append("<div class='wrap'><table><thead><tr><th>id</th><th>termo_busca</th>"
                 "<th>dimensão</th><th>veredito</th></tr></thead><tbody>")
        h.append("<tr><td colspan='2'><code>{}</code> <i>(âncora)</i></td><td>estampa</td><td>—</td></tr>".format(
            e(ANCORA)))
        for r in grupo:
            h.append("<tr><td><code>{}</code></td><td><code>{}</code></td><td>{}</td><td></td></tr>".format(
                e(r["id"]), e(r["termo_busca"]), e(r["dimensao"])))
        h.append("</tbody></table></div></div>")

    h.append("<h2>O que eu já espero encontrar</h2>")
    h.append("<p>Palpites meus. Se baterem, ganhamos confiança no resto da lista:</p><ul>")
    h.append("<li><code>vestido liso</code> é o candidato mais forte a <b>morto</b>. É o denominador "
             "da dimensão estampa: se morrer, mantenha aprovado com "
             "<code>sem_perna_busca=sim</code> em vez de reprovar.</li>")
    h.append("<li><code>look alfaiataria</code> e <code>look basico</code> são os mais incertos: "
             "<code>look</code> é a âncora menos testada das oito.</li>")
    h.append("<li><code>vestido feminino</code> pode ter volume bem menor que <code>vestido</code> puro. "
             "Se a queda for brutal, vale discutir soltar o sufixo em toda a dimensão categoria "
             "&mdash; mas aí some a proteção contra vazamento de masculino.</li>")
    h.append("<li><code>vestido de croche</code> deve ter volume baixo, e tudo bem: é o preço de "
             "tirar a contaminação de artesanato.</li>")
    h.append("</ul>")

    h.append("</body></html>")

    with open(SAIDA, "w", encoding="utf-8") as f:
        f.write("\n".join(h))
    print("Escrito: {}".format(SAIDA), file=sys.stderr)
    print("{} termos, {} dimensoes, {} grupos".format(
        len(linhas), len(por_dim), len(grupos)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
