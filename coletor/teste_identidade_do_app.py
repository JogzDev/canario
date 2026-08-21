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

import json
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
    for nome in ("BUNDLE", "TIME_DE_DESENVOLVIMENTO", "VERSAO_DO_APP",
                 "BUILD_DO_APP"):
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

    for nome in ("BUNDLE", "TIME_DE_DESENVOLVIMENTO", "VERSAO_DO_APP",
                 "BUILD_DO_APP"):
        if nome not in gerador:
            print("FALHOU: gerar_projeto.py nao define {}".format(nome))
            return 1

    # 1. O projeto versionado nao pode ter duas identidades. Debug e Release
    #    divergirem e como o app subir com um bundle e assinar com outro.
    for chave, esperados in (
            ("PRODUCT_BUNDLE_IDENTIFIER", [gerador["BUNDLE"],
                                            gerador["BUNDLE"] + ".UITests"]),
            ("DEVELOPMENT_TEAM", [gerador["TIME_DE_DESENVOLVIMENTO"]])):
        achados = valores(pbx, chave)
        if achados != sorted(esperados):
            print("FALHOU: {} diverge -- gerador diz {!r}, pbxproj diz {!r}. "
                  "Um dos dois foi mexido sozinho.".format(
                      chave, sorted(esperados), achados))
            return 1

    # 2. O gerador precisa EMITIR o time. Sem ele o Archive perde a assinatura,
    #    e o sintoma aparece so na hora de exportar para a loja.
    if "DEVELOPMENT_TEAM" not in fonte_gerador.split("BUNDLE =")[-1]:
        print("FALHOU: gerar_projeto.py nao emite DEVELOPMENT_TEAM")
        return 1

    # 3. A versao tambem e unica, e vem do pbxproj -- o Info.plist a referencia
    #    por $(MARKETING_VERSION) desde 8ce22fd em vez de repetir o numero.
    versoes = valores(pbx, "MARKETING_VERSION")
    if versoes != [gerador["VERSAO_DO_APP"]]:
        print("FALHOU: MARKETING_VERSION tem valores diferentes: {}".format(
            versoes))
        return 1
    builds = valores(pbx, "CURRENT_PROJECT_VERSION")
    if builds != [gerador["BUILD_DO_APP"]]:
        print("FALHOU: CURRENT_PROJECT_VERSION diverge: {}".format(builds))
        return 1
    info = os.path.join(APP, "Canario", "Info.plist")
    if os.path.exists(info):
        texto = open(info, encoding="utf-8").read()
        if "$(MARKETING_VERSION)" not in texto:
            print("FALHOU: Info.plist repete a versao em vez de referenciar "
                  "$(MARKETING_VERSION); volta a poder divergir do pbxproj")
            return 1

    # 4. O String Catalog precisa existir, ser valido e estar empacotado. Sem
    #    estes tres guardrails, uma tela nova volta a espalhar texto sem uma
    #    fonte unica de traducao.
    catalogo = os.path.join(APP, "Canario", "Localizable.xcstrings")
    try:
        dados_catalogo = json.load(open(catalogo, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print("FALHOU: Localizable.xcstrings ausente ou invalido: {}".format(exc))
        return 1
    if dados_catalogo.get("sourceLanguage") != "en":
        print("FALHOU: idioma-fonte do String Catalog nao e en")
        return 1
    if len(dados_catalogo.get("strings", {})) < 100:
        print("FALHOU: String Catalog incompleto (menos de 100 chaves)")
        return 1
    if "Localizable.xcstrings in Resources" not in pbx:
        print("FALHOU: String Catalog existe, mas nao entra no app")
        return 1

    # 5. Os guias que uma pessoa segue tem que citar o mesmo bundle -- guia com
    #    bundle errado ja custou uma submissao. Mas apagar as mencoes antigas
    #    tambem e ruim: elas contam o que aconteceu, e sem esse registro alguem
    #    "corrige" o projeto de volta para o bundle sem perfil de distribuicao.
    #
    #    A regra, entao, nao e "nunca cite o bundle antigo": e "se citar, avise
    #    no topo que e historico". Documento que cita sem avisar reprova.
    errados = []
    documentos = [(d, os.path.join(RAIZ, d)) for d in sorted(os.listdir(RAIZ))]
    # `historico/` tambem entra: documento antigo pode estar certo sobre o
    # passado e ainda assim fazer alguem "corrigir" o projeto para o bundle
    # errado hoje. O aviso no topo e o que separa registro de instrucao.
    historico = os.path.join(RAIZ, "historico")
    if os.path.isdir(historico):
        documentos += [(os.path.join("historico", d), os.path.join(historico, d))
                       for d in sorted(os.listdir(historico))]
    for doc, caminho in documentos:
        if not doc.endswith(".md"):
            continue
        texto = open(caminho, encoding="utf-8", errors="ignore").read()
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

    print("Identidade do app: bundle {}, time {}, versao {} ({}), "
          "String Catalog com {} chaves -- gerador, projeto, Info.plist e "
          "guias de acordo".format(
              gerador["BUNDLE"], gerador["TIME_DE_DESENVOLVIMENTO"],
              versoes[0], builds[0], len(dados_catalogo["strings"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
