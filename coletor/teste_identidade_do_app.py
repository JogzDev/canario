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
import plistlib
import re
import struct
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

    # A exportacao pode trocar de equipe mesmo com o Archive correto. Este
    # arquivo ainda apontava para uma equipe historica e so falharia no ultimo
    # passo do upload, porque o Organizer escolhe a conta por fora do projeto.
    export_options = os.path.join(APP, "ExportOptions-AppStore.plist")
    try:
        with open(export_options, "rb") as arquivo:
            opcoes = plistlib.load(arquivo)
    except (OSError, ValueError) as exc:
        print("FALHOU: ExportOptions-AppStore.plist invalido: {}".format(exc))
        return 1
    if opcoes.get("teamID") != gerador["TIME_DE_DESENVOLVIMENTO"]:
        print("FALHOU: ExportOptions usa teamID {!r}, projeto usa {!r}".format(
            opcoes.get("teamID"), gerador["TIME_DE_DESENVOLVIMENTO"]))
        return 1
    if opcoes.get("manageAppVersionAndBuildNumber") is not False:
        print("FALHOU: ExportOptions deixa o Xcode trocar o build durante a "
              "exportacao; o numero precisa ser decidido no projeto")
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
    with open(info, "rb") as arquivo:
        plist_identidade = plistlib.load(arquivo)
    if plist_identidade.get("CFBundleDisplayName") != "Seam":
        print("FALHOU: nome visível do app precisa ser Seam")
        return 1
    for uso in ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"):
        descricao = plist_identidade.get(uso, "")
        if "Seam" not in descricao or "DataDrobe" in descricao:
            print("FALHOU: texto de permissão ainda usa a identidade anterior: " + uso)
            return 1

    icones = os.path.join(APP, "Canario", "Assets.xcassets", "AppIcon.appiconset")
    with open(os.path.join(icones, "Contents.json"), encoding="utf-8") as arquivo:
        variantes = json.load(arquivo)["images"]
    esperadas = {
        "light": "AppIcon-clara-1024.png",
        "dark": "AppIcon-escura-1024.png",
        "tinted": "AppIcon-tingida-1024.png",
    }
    achadas = {}
    for variante in variantes:
        aparencias = variante.get("appearances", [])
        nome = aparencias[0]["value"] if aparencias else "light"
        achadas[nome] = variante["filename"]
        with open(os.path.join(icones, variante["filename"]), "rb") as arquivo:
            cabecalho = arquivo.read(26)
        if cabecalho[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" or struct.unpack(">II", cabecalho[16:24]) != (1024, 1024):
            print("FALHOU: ícone ausente ou fora de 1024×1024: " + variante["filename"])
            return 1
        # As variantes coloridas precisam ser opacas; a versão tingida usa
        # transparência para o iOS aplicar a cor escolhida pela pessoa.
        if nome != "tinted" and cabecalho[25] in (4, 6):
            print("FALHOU: ícone colorido contém canal alfa: " + variante["filename"])
            return 1
    if achadas != esperadas:
        print("FALHOU: faltam aparências do ícone Seam: " + repr(achadas))
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
    if "DataDrobe" in json.dumps(dados_catalogo, ensure_ascii=False):
        print("FALHOU: catálogo ainda exibe a identidade anterior")
        return 1
    if "Localizable.xcstrings in Resources" not in pbx:
        print("FALHOU: String Catalog existe, mas nao entra no app")
        return 1

    # 5. Google nativo precisa de quatro peças que o Xcode não relaciona por
    #    conta própria: pacote, client iOS, audience web e URL scheme reverso.
    #    Qualquer uma ausente compila em alguns caminhos e falha só depois que
    #    a pessoa escolhe a conta no Google.
    try:
        with open(info, "rb") as arquivo:
            plist_do_app = plistlib.load(arquivo)
    except (OSError, ValueError) as exc:
        print("FALHOU: Info.plist invalido ao conferir Google: {}".format(exc))
        return 1
    cliente_google = plist_do_app.get("GIDClientID", "")
    servidor_google = plist_do_app.get("GIDServerClientID", "")
    sufixo_google = ".apps.googleusercontent.com"
    if not cliente_google.endswith(sufixo_google) or not servidor_google.endswith(sufixo_google):
        print("FALHOU: client IDs do Google nativo ausentes no Info.plist")
        return 1
    esquema_esperado = "com.googleusercontent.apps." + cliente_google[:-len(sufixo_google)]
    esquemas = {
        esquema
        for tipo in plist_do_app.get("CFBundleURLTypes", [])
        for esquema in tipo.get("CFBundleURLSchemes", [])
    }
    if esquema_esperado not in esquemas or "datadrobe" not in esquemas:
        print("FALHOU: URL schemes do Google ou do DataDrobe incompletos")
        return 1
    if ("GoogleSignIn-iOS" not in pbx
            or "GoogleSignIn in Frameworks" not in pbx):
        print("FALHOU: GoogleSignIn nao esta ligado ao target do app")
        return 1

    # 6. Os documentos ATIVOS de distribuição precisam acompanhar a versão.
    # O guia anterior ficou em 0.1/1.0 enquanto o projeto já estava em 1.1 e
    # chegou a afirmar que o app era pt-BR e não enviava foto. Bundle correto
    # sozinho não torna uma ficha de privacidade correta.
    documentos_de_release = {
        "RELEASE_DATADROBE.md": [
            "DataDrobe", gerador["BUNDLE"], "Versão | **{}**".format(
                gerador["VERSAO_DO_APP"]),
            "Build | **{}**".format(gerador["BUILD_DO_APP"]),
            "Idioma-fonte | inglês", "OpenAI", "consentimento"],
        "TESTFLIGHT.md": [
            "DataDrobe {} (build {})".format(
                gerador["VERSAO_DO_APP"], gerador["BUILD_DO_APP"]),
            gerador["BUNDLE"], "Idioma-fonte do app: inglês",
            "cloud-consent"],
        "FICHA_APP_STORE_{}.md".format(gerador["VERSAO_DO_APP"]): [
            "DataDrobe {} (build {})".format(
                gerador["VERSAO_DO_APP"], gerador["BUILD_DO_APP"]),
            "Photos or Videos collected", "OpenAI", "até 30 dias"],
    }
    for doc, trechos in documentos_de_release.items():
        caminho = os.path.join(RAIZ, doc)
        try:
            texto = open(caminho, encoding="utf-8").read()
        except OSError as exc:
            print("FALHOU: guia ativo de release ausente: {} ({})".format(
                doc, exc))
            return 1
        ausentes = [trecho for trecho in trechos if trecho not in texto]
        if ausentes:
            print("FALHOU: {} nao descreve o candidato atual; faltam: {}".format(
                doc, ", ".join(repr(x) for x in ausentes)))
            return 1

    # 6a. A ficha precisa ser copiavel, nao apenas lembrar o que mudou. Em
    #     20/09 a ficha 1.2 tinha What's New e um trecho substituto, mas nao
    #     continha Description, Promotional Text nem Keywords completos. Isso
    #     so apareceria como campo vazio durante o preenchimento da loja.
    ficha_atual = open(os.path.join(
        RAIZ, "FICHA_APP_STORE_{}.md".format(gerador["VERSAO_DO_APP"])),
        encoding="utf-8").read()

    def bloco_da_ficha(titulo):
        padrao = (r"(?mi)^#{2,3}\s+" + re.escape(titulo)
                  + r"\s*$\s*```text\s*\n(.*?)\n```")
        achado = re.search(padrao, ficha_atual, re.S)
        return achado.group(1).strip() if achado else None

    campos = {
        "Subtitle": bloco_da_ficha("Subtitle"),
        "Promotional text": bloco_da_ficha("Promotional text"),
        "Description": bloco_da_ficha("Description"),
        "Keywords": bloco_da_ficha("Keywords"),
        "What's New": bloco_da_ficha("What's New"),
    }
    ausentes = [nome for nome, valor in campos.items() if not valor]
    if ausentes:
        print("FALHOU: ficha da App Store nao tem campos completos: {}".format(
            ", ".join(ausentes)))
        return 1

    limites = {
        "Subtitle": (30, "caracteres"),
        "Promotional text": (170, "caracteres"),
        "Description": (4000, "caracteres"),
        "Keywords": (100, "bytes UTF-8"),
    }
    for nome, (limite, unidade) in limites.items():
        valor = campos[nome]
        tamanho = len(valor.encode("utf-8")) if nome == "Keywords" else len(valor)
        if tamanho > limite:
            print("FALHOU: {} tem {} {}, limite {}".format(
                nome, tamanho, unidade, limite))
            return 1
    if any(c != c.strip() for c in campos["Keywords"].split(",")):
        print("FALHOU: Keywords contem espaco desnecessario")
        return 1
    if "account" not in campos["Description"].lower():
        print("FALHOU: Description da 1.2 omite a conta opcional")
        return 1

    # 7. Os guias que uma pessoa segue tem que citar o mesmo bundle -- guia com
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
          "String Catalog com {} chaves -- gerador, projeto, Info.plist, "
          "ficha e guias de release de acordo".format(
              gerador["BUNDLE"], gerador["TIME_DE_DESENVOLVIMENTO"],
              versoes[0], builds[0], len(dados_catalogo["strings"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
