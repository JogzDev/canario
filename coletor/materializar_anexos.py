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
#: Plataformas que o coletor de varejo sabe ler. A Nuvemshop entrou em
#: 23/09/2026, quando a Amaro saiu da Shopify.
PLATAFORMAS = ("vtex", "shopify", "nuvemshop")
TAXONOMIA = os.path.join(RAIZ, "anexos", "taxonomia.csv")


def _val(linha, chave):
    v = (linha.get(chave) or "").strip()
    return v or None


def registro_do_termo(linha):
    """Campos de configuracao cujo dono e o CSV aprovado.

    `sem_perna_busca`, `volume_verificado_em` e `volume_detalhe` nao entram
    aqui de proposito: sao estado medido pelo coletor de Trends. Reaplicar o
    CSV diariamente sobre esses campos apagava verificacoes ja feitas e fazia
    termos medidos voltarem para `pendente`.
    """
    return {
        "id": linha["id"].strip(),
        "rotulo": _val(linha, "rotulo"),
        "dimensao": _val(linha, "dimensao"),
        "exclusiva": (_val(linha, "exclusiva") or "").lower() == "sim",
        "sinonimos": _val(linha, "sinonimos"),
        "termo_busca": _val(linha, "termo_busca"),
        "palavras_pt": _val(linha, "palavras_pt"),
        "palavras_en": _val(linha, "palavras_en"),
        "exemplo": _val(linha, "exemplo"),
        "status": _val(linha, "status") or "proposto",
        "motivo": _val(linha, "motivo"),
    }


def registro_da_marca(linha):
    """Converte uma linha do painel na configuracao operacional da marca.

    Apenas marcas cuja plataforma foi comprovada entram na coleta. Isso evita
    que uma marca mantida no painel por contexto competitivo seja tratada como
    fonte obrigatoria do recorte atual.
    """
    status = _val(linha, "status_teste") or "pendente"
    plataforma = status if status in PLATAFORMAS else None
    return {
        "nome": linha["marca"].strip(),
        "dominio": _val(linha, "dominio"),
        "plataforma": plataforma,
        "segmento": _val(linha, "segmento"),
        "papel": _val(linha, "papel"),
        "justificativa": _val(linha, "justificativa"),
        "status_teste": status,
        "data_teste": _val(linha, "data_teste"),
        "detalhe_teste": _val(linha, "detalhe_teste"),
        "ativa": plataforma is not None,
    }


def materializar_marcas():
    linhas = list(csv.DictReader(open(PAINEL, encoding="utf-8")))
    registros = [registro_da_marca(l) for l in linhas]
    supabase_rest.upsert("marcas", registros, on_conflict="nome")
    return len(registros)


def materializar_termos():
    linhas = list(csv.DictReader(open(TAXONOMIA, encoding="utf-8")))
    registros = [registro_do_termo(l) for l in linhas]
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
