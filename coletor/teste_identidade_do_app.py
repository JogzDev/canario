"""A identidade da loja e uma so, em todos os lugares que a escrevem.

POR QUE ISTO EXISTE
===================

O bundle e a versao do app ja andaram sozinhos duas vezes, e nas duas ninguem
viu na hora:

* 08/2026, commit 8bb8dfd -- um commit que dizia "conferido chave a chave"
  reverteu bundle e versao no `project.pbxproj`. A conferencia tinha sido feita
  no Info.plist; o pbxproj no mesmo commit nao foi olhado.
* 19/08/2026 -- `app/gerar_projeto.py`, que e o jeito DOCUMENTADO de adicionar
  uma tela, ainda escrevia `com.canario.app` e nao emitia `DEVELOPMENT_TEAM`
  nenhum. Quem seguisse a documentacao trocava a identidade do app sem ver,
  com a versao em revisao na Apple.

Os dois casos tem a mesma forma: a mesma informacao escrita em mais de um
lugar, sem ninguem conferindo que continuam iguais. Este teste e o conferidor.
Ele nao decide qual e o valor certo -- decide que so existe um.
"""

import os
import re
import sys


RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(RAIZ, "app")
PBXPROJ = os.path.join(APP, "Canario.xcodeproj", "project.pbxproj")


def constantes_do_gerador():
    """Le as constantes sem importar o modulo, que escreve arquivo ao rodar."""
    fonte = open(os.path.join(APP, "gerar_projeto.py"), encoding="utf-8").read()
    achados = {}
    for nome in ("BUNDLE", "TIME_DE_DESENVOLVIMENTO"):
        m = re.search(r'^{}\s*=\s*"([^"]+)"'.format(nome), fonte, re.M)
        if m:
            achados[nome] = m.group(1)
    return achados, fonte


def valores(texto, chave):
    """Todos os valores distintos de uma chave, com ou sem aspas."""
    brutos = re.findall(r'{}\s*=\s*"?([^";]+)"?\s*;'.format(chave), texto)
    return sorted({v.strip() for v in brutos})


def main():
    if not os.path.exists(PBXPROJ):
        print("FALHOU: project.pbxproj nao encontrado em {}".format(PBXPROJ))
        return 1
    pbx = open(PBXPROJ, encoding="utf-8").read()
    gerador, fonte_gerador = constantes_do_gerador()

    for nome in ("BUNDLE", "TIME_DE_DESENVOLVIMENTO"):
        if nome not in gerador:
            print("FALHOU: gerar_projeto.py nao define {}".format(nome))
            return 1

    # 1. O projeto versionado nao pode ter duas identidades. Debug e Release
    #    divergirem e como o app subir com um bundle e assinar com outro.
    for chave, esperado in (
            ("PRODUCT_BUNDLE_IDENTIFIER", gerador["BUNDLE"]),
            ("DEVELOPMENT_TEAM", gerador["TIME_DE_DESENVOLVIMENTO"])):
        achados = valores(pbx, chave)
        if len(achados) != 1:
            print("FALHOU: {} tem {} valores no pbxproj: {}".format(
                chave, len(achados), achados))
            return 1
        if achados[0] != esperado:
            print("FALHOU: {} diverge -- gerador diz {!r}, pbxproj diz {!r}. "
                  "Um dos dois foi mexido sozinho.".format(
                      chave, esperado, achados[0]))
            return 1

    # 2. O gerador precisa EMITIR o time. Sem ele o Archive perde a assinatura,
    #    e o sintoma aparece so na hora de exportar para a loja.
    if "DEVELOPMENT_TEAM" not in fonte_gerador.split("BUNDLE =")[-1]:
        print("FALHOU: gerar_projeto.py nao emite DEVELOPMENT_TEAM")
        return 1

    # 3. A versao tambem e unica, e vem do pbxproj -- o Info.plist a referencia
    #    por $(MARKETING_VERSION) desde 8ce22fd em vez de repetir o numero.
    versoes = valores(pbx, "MARKETING_VERSION")
    if len(versoes) != 1:
        print("FALHOU: MARKETING_VERSION tem valores diferentes: {}".format(
            versoes))
        return 1
    info = os.path.join(APP, "Canario", "Info.plist")
    if os.path.exists(info):
        texto = open(info, encoding="utf-8").read()
        if "$(MARKETING_VERSION)" not in texto:
            print("FALHOU: Info.plist repete a versao em vez de referenciar "
                  "$(MARKETING_VERSION); volta a poder divergir do pbxproj")
            return 1

    # 4. Os guias que uma pessoa segue tem que citar o mesmo bundle -- guia com
    #    bundle errado ja custou uma submissao. Mas apagar as mencoes antigas
    #    tambem e ruim: elas contam o que aconteceu, e sem esse registro alguem
    #    "corrige" o projeto de volta para o bundle sem perfil de distribuicao.
    #
    #    A regra, entao, nao e "nunca cite o bundle antigo": e "se citar, avise
    #    no topo que e historico". Documento que cita sem avisar reprova.
    errados = []
    for doc in sorted(os.listdir(RAIZ)):
        if not doc.endswith(".md"):
            continue
        texto = open(os.path.join(RAIZ, doc), encoding="utf-8",
                     errors="ignore").read()
        antigos = {c for c in re.findall(r'\b(?:br\.)?com\.canario[\w.]*', texto)
                   if c != gerador["BUNDLE"]}
        if not antigos:
            continue
        cabecalho = texto[:1200]
        avisado = (gerador["BUNDLE"] in cabecalho
                   and ("histór" in cabecalho or "histor" in cabecalho))
        if not avisado:
            errados.append("{}: cita {} sem o aviso de que e historico".format(
                doc, ", ".join(sorted(antigos))))
    if errados:
        print("FALHOU: documento cita bundle antigo como se fosse o atual:")
        for e in sorted(set(errados)):
            print("  - {}".format(e))
        print("  Corrija o valor, ou marque a mencao como historica no topo "
              "citando {}.".format(gerador["BUNDLE"]))
        return 1

    print("Identidade do app: bundle {}, time {}, versao {} -- "
          "gerador, projeto, Info.plist e guias de acordo".format(
              gerador["BUNDLE"], gerador["TIME_DE_DESENVOLVIMENTO"],
              versoes[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
