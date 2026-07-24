"""Materializa os anexos CSV no banco (F1, §33).

Espelha painel_marcas.csv -> tabela marcas e taxonomia.csv -> tabela termos.
Idempotente (upsert): pode rodar todo dia no comeco da coleta para manter o
espelho em sincronia com os CSVs aprovados. O motor so usa termos aprovados
(regra 4); aqui so materializamos o espelho, sem julgar status.

Roda dentro do Actions, onde SUPABASE_* existem. A chave secreta nunca sai de
la (regra 9).
"""

import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import supabase_rest  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAINEL = os.path.join(RAIZ, "anexos", "painel_marcas.csv")
TAXONOMIA = os.path.join(RAIZ, "anexos", "taxonomia.csv")


def _val(linha, chave):
    v = (linha.get(chave) or "").strip()
    return v or None


def materializar_marcas():
    linhas = list(csv.DictReader(open(PAINEL, encoding="utf-8")))
    registros = []
    for l in linhas:
        status = _val(l, "status_teste") or "pendente"
        plataforma = status if status in ("vtex", "shopify") else None
        registros.append({
            "nome": l["marca"].strip(),
            "dominio": _val(l, "dominio"),
            "plataforma": plataforma,
            "segmento": _val(l, "segmento"),
            "papel": _val(l, "papel"),
            "justificativa": _val(l, "justificativa"),
            "status_teste": status,
            "data_teste": _val(l, "data_teste"),
            "detalhe_teste": _val(l, "detalhe_teste"),
            "ativa": True,
        })
    supabase_rest.upsert("marcas", registros, on_conflict="nome")
    return len(registros)


def materializar_termos():
    linhas = list(csv.DictReader(open(TAXONOMIA, encoding="utf-8")))
    registros = []
    for l in linhas:
        registros.append({
            "id": l["id"].strip(),
            "rotulo": _val(l, "rotulo"),
            "dimensao": _val(l, "dimensao"),
            "exclusiva": (_val(l, "exclusiva") or "").lower() == "sim",
            "sinonimos": _val(l, "sinonimos"),
            "termo_busca": _val(l, "termo_busca"),
            "palavras_pt": _val(l, "palavras_pt"),
            "palavras_en": _val(l, "palavras_en"),
            "exemplo": _val(l, "exemplo"),
            "status": _val(l, "status") or "proposto",
            "sem_perna_busca": _val(l, "sem_perna_busca") or "pendente",
            "motivo": _val(l, "motivo"),
        })
    supabase_rest.upsert("termos", registros, on_conflict="id")
    return len(registros)


def main():
    m = materializar_marcas()
    t = materializar_termos()
    print("Materializados: {} marcas, {} termos.".format(m, t))
    aprovados = supabase_rest.selecionar("termos", "?status=eq.aprovado&select=id")
    print("Termos aprovados (o motor só usa estes): {}.".format(len(aprovados)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
