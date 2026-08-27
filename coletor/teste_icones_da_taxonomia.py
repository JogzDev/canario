"""Todo termo aprovado da taxonomia tem icone na tela de atributos.

POR QUE ESTE ARQUIVO EXISTE
===========================

A tela "Fill the info" mostra os atributos como grade de icones, e nao mais
como lista de chips de texto. Isso troca o modo de falha: chip sem rotulo nao
existe, porque o rotulo E o chip. Icone faltando, sim -- e ele nao quebra
nada. O termo aparece na grade com um circulo pontilhado e segue selecionavel.

A taxonomia cresce. `couro` entrou em 26/08, os seis motivos de estampa
entraram antes, e a proxima marca ou tendencia vai trazer mais. Cada termo
novo nasce sem icone, e sem este portao a descoberta seria alguem abrindo a
tela e vendo o buraco.

O portao confere os dois lados:

  1. Todo id `aprovado` do CSV aparece no mapa do Swift.
  2. Todo id do mapa existe no CSV -- mapa que sobrevive a um termo removido
     vira lixo que ninguem tem coragem de apagar depois.

A validade dos NOMES de SF Symbol e outro portao, do lado Swift
(`IconesDaTaxonomiaTests`), porque so o catalogo do sistema sabe responder.
"""

import csv
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
TAXONOMIA = RAIZ / "anexos" / "taxonomia.csv"
MAPA = RAIZ / "app" / "Canario" / "Rede" / "IconesDaTaxonomia.swift"

# Alias historico: a A26 canonicaliza `trico_croche` para `malha` antes de
# consultar o mapa, entao ele pode estar nos dois lados sem ser divergencia.
ALIASES = {"trico_croche": "malha"}


def ids_da_taxonomia():
    with TAXONOMIA.open(encoding="utf-8") as arquivo:
        linhas = list(csv.DictReader(arquivo))
    return {
        linha["id"].strip()
        for linha in linhas
        if linha.get("status", "").strip() == "aprovado" and linha["id"].strip()
    }


def ids_do_mapa():
    fonte = MAPA.read_text(encoding="utf-8")
    # As chaves do dicionario, na forma `"id": .algumaCoisa`. Sem ancora de
    # inicio de linha: as cores sao escritas duas por linha, e ancorar deixava
    # a segunda de cada par invisivel para o portao -- que foi como este
    # arquivo acusou cinco cores inexistentes na primeira execucao.
    return set(re.findall(r'"([a-z0-9_]+)"\s*:\s*\.', fonte))


def main():
    if not TAXONOMIA.exists() or not MAPA.exists():
        print("FALHA: taxonomia.csv ou IconesDaTaxonomia.swift nao encontrado")
        return 1

    taxonomia = ids_da_taxonomia()
    mapa = ids_do_mapa()

    sem_icone = sorted(taxonomia - mapa - set(ALIASES))
    orfaos = sorted(mapa - taxonomia - set(ALIASES))

    if sem_icone:
        print(f"FALHA: {len(sem_icone)} termo(s) aprovado(s) sem icone:")
        for termo in sem_icone:
            print(f"  - {termo}")
        print()
        print("Acrescente o termo em app/Canario/Rede/IconesDaTaxonomia.swift.")
        print("Sem isso ele aparece na grade como circulo pontilhado.")

    if orfaos:
        print(f"FALHA: {len(orfaos)} icone(s) para termo que nao existe mais:")
        for termo in orfaos:
            print(f"  - {termo}")

    if sem_icone or orfaos:
        return 1

    print(f"OK: {len(taxonomia)} termos aprovados, todos com icone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
