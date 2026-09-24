#!/usr/bin/env python3
"""Compara as leituras de cada modelo com o gabarito humano.

Uso:
    python3 ferramentas/benchmark_foto/comparar.py gabarito.json \
        respostas_luna.jsonl respostas_apple.jsonl > comparacao.md

REGRAS DE CONTAGEM
==================

- Categoria: acerto quando a estrutura lida, traduzida pela mesma tabela do
  app, está entre as aceitas pelo gabarito. `target_not_determinable` conta
  como "ambiguo", que o gabarito aceita só onde duas peças disputam de fato.
- Estampa, cor principal e comprimento: só contam quando o modelo leu a peça
  que o gabarito marca como alvo. Se ele escolheu outra peça, a cor que deu é
  da peça errada, e contar isso misturaria dois erros num número só.
- Campo nulo no gabarito (foto em preto e branco, comprimento fora do
  quadro) não entra na conta.
- Erro de chamada (rede, recusa, JSON quebrado) conta como erro de leitura, à
  parte: nunca vira acerto nem erro de categoria.
"""

import json
import statistics
import sys
from collections import defaultdict

CATEGORIA = {
    "one_piece_no_separate_legs": "vestido",
    "one_piece_with_separate_legs": "macacao",
    "lower_continuous_panel": "saia",
    "lower_two_legs_short": "short",
    "lower_two_legs_long": "calca",
    "upper_shirt_construction": "camisa",
    "upper_outer_layer": "casaco_jaqueta",
    "upper_other": "blusa_top",
    "target_not_determinable": "ambiguo",
}


def ler_jsonl(caminho):
    linhas = []
    for linha in open(caminho, encoding="utf-8"):
        linha = linha.strip()
        if linha:
            dado = json.loads(linha)
            resposta = dado.get("resposta")
            if isinstance(resposta, str):
                try:
                    resposta = json.loads(resposta)
                except ValueError:
                    resposta = None
                    dado["erro"] = dado.get("erro") or "json invalido"
            dado["resposta"] = resposta
            linhas.append(dado)
    return linhas


def avaliar(gabarito, linhas):
    """Devolve, por modelo e conjunto, as contagens de cada regra."""
    placar = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    tempos = defaultdict(list)
    erros_por_foto = defaultdict(list)
    for linha in linhas:
        modelo = linha["modelo"]
        foto = gabarito.get(linha["id"])
        if foto is None:
            continue
        conjunto = "solta" if linha["id"].startswith("s-") else "vestida"
        for chave in ((modelo, conjunto), (modelo, "todas")):
            p = placar[chave]
            p["fotos"][1] += 1
            resposta = linha.get("resposta")
            if linha.get("erro") or not isinstance(resposta, dict):
                p["erro_de_leitura"][0] += 1
                continue
            categoria = CATEGORIA.get(resposta.get("garment_structure"), "?")
            p["categoria"][1] += 1
            if categoria in foto["cat"]:
                p["categoria"][0] += 1
            elif chave[1] == "todas":
                erros_por_foto[modelo].append((linha["id"], categoria, foto["cat"]))
            if categoria == "ambiguo":
                p["absteve"][0] += 1
            alvos = foto.get("alvo")
            alvos = [alvos] if isinstance(alvos, str) else (alvos or [])
            if categoria not in alvos:
                continue
            p["leu_o_alvo"][0] += 1
            if foto.get("estampa"):
                p["estampa"][1] += 1
                p["estampa"][0] += resposta.get("pattern") in foto["estampa"]
            if foto.get("cor"):
                cores = resposta.get("colors") or []
                p["cor principal"][1] += 1
                p["cor principal"][0] += bool(cores) and cores[0] in foto["cor"]
            if foto.get("comprimento"):
                p["comprimento"][1] += 1
                p["comprimento"][0] += resposta.get("length") in foto["comprimento"]
        if linha.get("segundos") is not None and not linha.get("erro"):
            tempos[modelo].append(float(linha["segundos"]))
    return placar, tempos, erros_por_foto


def pct(par):
    acertos, total = par
    return "—" if not total else "{:.0f}% ({}/{})".format(100 * acertos / total, acertos, total)


def main():
    gabarito = json.load(open(sys.argv[1], encoding="utf-8"))
    linhas = [l for caminho in sys.argv[2:] for l in ler_jsonl(caminho)]
    placar, tempos, erros = avaliar(gabarito, linhas)
    modelos = sorted({m for m, _ in placar})
    regras = ("categoria", "estampa", "cor principal", "comprimento")
    for conjunto in ("todas", "solta", "vestida"):
        print("\n### {}\n".format({"todas": "As 100 fotos", "solta": "Peça solta (50)",
                                    "vestida": "Peça vestida (50)"}[conjunto]))
        print("| Modelo | " + " | ".join(r.capitalize() for r in regras)
              + " | Alvo ambíguo | Erro de leitura |")
        print("|---" * (len(regras) + 3) + "|")
        for modelo in modelos:
            p = placar[(modelo, conjunto)]
            fotos = p["fotos"][1]
            print("| {} | {} | {} | {} |".format(
                modelo, " | ".join(pct(p[r]) for r in regras),
                "{}/{}".format(p["absteve"][0], fotos),
                "{}/{}".format(p["erro_de_leitura"][0], fotos)))
    print("\n### Tempo por foto (mediana)\n")
    for modelo in modelos:
        if tempos[modelo]:
            print("- {}: {:.1f} s".format(modelo, statistics.median(tempos[modelo])))
    print("\n### Categorias erradas\n")
    for modelo in modelos:
        print("- {}: {}".format(modelo, ", ".join(
            "{} leu {} (aceito: {})".format(i, c, "/".join(a)) for i, c, a in erros[modelo]) or "nenhuma"))


if __name__ == "__main__":
    main()
