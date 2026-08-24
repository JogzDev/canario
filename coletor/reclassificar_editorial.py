"""Refiltra o arquivo editorial existente e reconstrói as séries derivadas.

Não baixa páginas nem apaga artigos. Lê título, veículo, URL e data já
persistidos, registra a pontuação de gênero e troca cada perna de série numa
transação. Falha antes da troca se não produzir uma carga material.
"""

import csv
import os
import sys
from collections import defaultdict
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coletor_editorial import (carregar_termos_compilados,
                               filtrar_contexto_editorial, semana_de,
                               JANELA_SEMANAS, SEGMENTO)
from filtro_genero_editorial import classificar_genero
from matcher import termos_que_casam
import supabase_rest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VEICULOS = os.path.join(RAIZ, "anexos", "veiculos.csv")
PAGINA = 1000


def carregar_artigos():
    ultimo = 0
    while True:
        lote = supabase_rest.selecionar(
            "artigos", "?select=id,veiculo,url,titulo,data_pub&id=gt.{}"
            "&order=id.asc&limit={}".format(ultimo, PAGINA))
        if not lote:
            return


def inicios_ja_medidos():
    """Primeira semana real por termo/perna; não fabrica zero pré-taxonomia."""
    ultimo = 0
    inicios = {}
    while True:
        lote = supabase_rest.selecionar(
            "series_semanais", "?select=id,termo_id,fonte,semana&id=gt.{}"
            "&fonte=in.(editorial_br,editorial_intl)&order=id.asc&limit={}".format(
                ultimo, PAGINA))
        if not lote:
            return inicios
        for linha in lote:
            chave = (linha["termo_id"], linha["fonte"])
            semana = date.fromisoformat(linha["semana"])
            inicios[chave] = min(inicios.get(chave, semana), semana)
        ultimo = lote[-1]["id"]
        if len(lote) < PAGINA:
            return inicios
        for artigo in lote:
            yield artigo
        ultimo = lote[-1]["id"]
        if len(lote) < PAGINA:
            return


def segundas(inicio, fim):
    atual = inicio
    while atual <= fim:
        yield atual
        atual += timedelta(days=7)


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1
    termos, categorias = carregar_termos_compilados()
    inicios = inicios_ja_medidos()
    focos = {v["veiculo"]: (v.get("foco_genero") or "misto")
             for v in csv.DictReader(open(VEICULOS, encoding="utf-8"))}
    fontes = {v["veiculo"]: ("editorial_br" if v["pais"].upper() == "BR"
                              else "editorial_intl")
              for v in csv.DictReader(open(VEICULOS, encoding="utf-8"))
              if v.get("tipo") != "dado_agregado"}

    crua = defaultdict(set)
    denominador = defaultdict(set)
    exemplos = defaultdict(list)
    classificacoes = []
    totais = defaultdict(int)

    for artigo in carregar_artigos():
        titulo = artigo.get("titulo") or ""
        genero = classificar_genero(titulo, focos.get(artigo["veiculo"], "misto"))
        classificacoes.append({"id": artigo["id"], "publico": genero["publico"],
                               "feminino": genero["pontos_femininos"],
                               "masculino": genero["pontos_masculinos"]})
        if len(classificacoes) >= 500:
            supabase_rest.rpc("registrar_classificacao_editorial",
                              {"classificacoes": classificacoes})
            classificacoes = []
        totais[genero["publico"]] += 1
        if genero["publico"] == "masculino" or not artigo.get("data_pub"):
            continue
        fonte = fontes.get(artigo["veiculo"])
        if not fonte:
            continue
        quando = date.fromisoformat(artigo["data_pub"])
        semana = semana_de(quando)
        denominador[(fonte, semana)].add(artigo["url"])
        achados = termos_que_casam(titulo, termos)
        achados = filtrar_contexto_editorial(
            titulo, "", achados, categorias, achados_no_titulo=achados)
        for termo in achados:
            chave = (termo, fonte, semana)
            crua[chave].add(artigo["url"])
            if len(exemplos[chave]) < 3:
                exemplos[chave].append({"veiculo": artigo["veiculo"],
                                        "titulo": titulo[:160], "url": artigo["url"]})
    if classificacoes:
        supabase_rest.rpc("registrar_classificacao_editorial",
                          {"classificacoes": classificacoes})

    for fonte in ("editorial_br", "editorial_intl"):
        semanas = sorted(s for f, s in denominador if f == fonte)
        if not semanas:
            raise RuntimeError("{} sem artigos após filtro; série preservada".format(fonte))
        linhas = []
        for semana in segundas(semanas[0], semanas[-1]):
            total = sum(len(denominador.get((fonte, semana - timedelta(weeks=w)), ()))
                        for w in range(JANELA_SEMANAS))
            if not total:
                continue
            for termo in termos:
                inicio = inicios.get((termo, fonte))
                if inicio is None or semana < inicio:
                    continue
                contagens = [len(crua.get((termo, fonte, semana - timedelta(weeks=w)), ()))
                             for w in range(JANELA_SEMANAS)]
                n = sum(contagens)
                linhas.append({
                    "termo_id": termo, "segmento": SEGMENTO, "fonte": fonte,
                    "semana": semana.isoformat(),
                    "valor_bruto": round(1000.0 * n / total, 4), "z": None,
                    "n_amostra": n,
                    "meta": {"janela_semanas": JANELA_SEMANAS,
                             "contagem_semana_crua": contagens[0],
                             "materias_da_perna_na_janela": total,
                             "unidade": "materias por mil da perna, em janela de 4 semanas",
                             "recorte_genero": "masculino acima de 50% excluido",
                             "classificacao": "titulo persistido; regra uniforme no historico e futuro",
                             "exemplos": exemplos.get((termo, fonte, semana), [])},
                })
        if len(linhas) < len(termos) * 6:
            raise RuntimeError("{} produziu série curta; carga preservada".format(fonte))
        inseridas = supabase_rest.rpc("substituir_serie_editorial",
                                      {"perna": fonte, "linhas": linhas},
                                      tentativas=1, timeout=180)
        print("{}: {} pontos substituídos".format(fonte, inseridas), file=sys.stderr)

    supabase_rest.rpc("computar_z", {}, tentativas=1, timeout=180)
    supabase_rest.rpc("computar_indice", {}, tentativas=1, timeout=180)
    print("Classificação: {}".format(dict(totais)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
