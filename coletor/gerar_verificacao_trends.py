"""Gera a lista de consultas do Trends para a verificacao manual (passo 2 da
sessao de aprovacao).

Motivo: aprovar um `termo_busca` sem olhar o volume e aprovar as cegas, e o erro
so apareceria semanas depois, quando a serie ja estivesse morta. O Trends aceita
ate 5 termos por comparacao; K7 exige uma ANCORA FIXA comum a todos os grupos,
senao os niveis nao sao comparaveis entre grupos (valores do Trends sao
relativos a consulta).

Ancora escolhida: "vestido floral". Volume medio e presenca continua no
mercado BR -- uma ancora de volume altissimo (como "vestido") esmagaria os
demais para perto de zero e destruiria a resolucao da leitura.

Rodar: python3 coletor/gerar_verificacao_trends.py
"""

import csv
import os
import sys
import urllib.parse

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAXONOMIA = os.path.join(RAIZ, "anexos", "taxonomia.csv")
SAIDA = os.path.join(RAIZ, "VERIFICACAO_TRENDS.md")

ANCORA = "vestido floral"
POR_GRUPO = 5  # teto do Trends


def url_trends(termos):
    q = ",".join(urllib.parse.quote(t) for t in termos)
    return ("https://trends.google.com.br/trends/explore"
            "?date=today%205-y&geo=BR&hl=pt-BR&q={}".format(q))


def main():
    linhas = list(csv.DictReader(open(TAXONOMIA, encoding="utf-8")))
    sem_busca = [r for r in linhas if not r["termo_busca"].strip()]
    termos = [r for r in linhas if r["termo_busca"].strip()]

    # A ancora e verificada em todo grupo por construcao; nao repetir na fila.
    fila = [r for r in termos if r["termo_busca"] != ANCORA]
    grupos = [fila[i:i + (POR_GRUPO - 1)] for i in range(0, len(fila), POR_GRUPO - 1)]

    out = []
    out.append("# Verificação manual do Trends — passo 2 da sessão de aprovação\n")
    out.append("**Gerado de** `anexos/taxonomia.csv` "
               "({} termos com busca, {} sem).\n".format(len(termos), len(sem_busca)))
    out.append("\n**Âncora fixa (K7):** `{}` — aparece em todos os {} grupos, "
               "para os níveis serem comparáveis entre eles. "
               "Não troque a âncora no meio da verificação.\n".format(ANCORA, len(grupos)))
    out.append("\n## Como preencher\n")
    out.append("Abra cada link (já vem com **Brasil**, **5 anos** e **pt-BR** aplicados), "
               "olhe a linha de cada termo e marque na coluna:\n")
    out.append("- **ok** — a série tem volume visível e forma plausível;\n")
    out.append("- **morto** — série achatada no zero ou quase; vira `sem_perna_busca=sim` "
               "e o termo anda nas pernas de varejo e editorial;\n")
    out.append("- **contaminado** — tem volume, mas o pico não bate com moda "
               "(ex.: sobe em data de artesanato, ou o \"consultas relacionadas\" mostra "
               "decoração/receita). Nesse caso anote uma variante melhor.\n")
    out.append("\nDepois me devolva a tabela preenchida: eu aplico no CSV e no banco.\n")

    for i, grupo in enumerate(grupos, 1):
        consulta = [ANCORA] + [r["termo_busca"] for r in grupo]
        dims = sorted({r["dimensao"] for r in grupo})
        out.append("\n---\n")
        out.append("\n### Grupo {} de {} — {}\n".format(i, len(grupos), ", ".join(dims)))
        out.append("\n[Abrir no Google Trends]({})\n".format(url_trends(consulta)))
        out.append("\n| # | id | termo_busca | dimensão | veredito | variante melhor (se contaminado) |")
        out.append("|---|---|---|---|---|---|")
        out.append("| — | _(âncora)_ | `{}` | estampa | — | — |".format(ANCORA))
        for r in grupo:
            out.append("| {} | `{}` | `{}` | {} |  |  |".format(
                i, r["id"], r["termo_busca"], r["dimensao"]))

    if sem_busca:
        out.append("\n---\n")
        out.append("\n## Sem perna de busca por desenho\n")
        for r in sem_busca:
            out.append("\n- `{}` ({}): {}\n".format(
                r["id"], r["dimensao"], r["motivo"][:160]))

    out.append("\n---\n")
    out.append("\n## O que já espero encontrar\n")
    out.append("\nPalpites meus, para você conferir se batem — se baterem, "
               "ganhamos confiança no resto da lista:\n")
    out.append("\n1. **`liso` (`vestido liso`)** é o candidato mais forte a morto. "
               "É o denominador da dimensão estampa, então se morrer, mantenha "
               "`aprovado` com `sem_perna_busca=sim` em vez de reprovar.\n")
    out.append("2. **`look alfaiataria`** e **`look básico`** são os mais incertos: "
               "a âncora `look` é a menos testada das oito dimensões.\n")
    out.append("3. **`vestido feminino`** pode ter volume bem menor que `vestido` puro. "
               "Se a queda for brutal, vale discutir soltar o sufixo em toda a "
               "dimensão categoria — mas aí some a proteção contra vazamento de masculino.\n")
    out.append("4. **`vestido de croche`** deve ter volume baixo, e tudo bem: "
               "é exatamente o preço de tirar a contaminação de artesanato.\n")

    with open(SAIDA, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("Escrito: {} ({} grupos, {} termos com busca)".format(
        SAIDA, len(grupos), len(termos)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
