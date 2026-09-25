#!/usr/bin/env python3
"""Gera o Canario.xcodeproj a partir dos arquivos em Canario/.

Existe porque o .xcodeproj e um formato grande e chato de editar a mao, e
qualquer arquivo novo exigiria mexer nele em cinco lugares. Aqui, adicionar
tela e criar o .swift e rodar este script.

Os identificadores sao derivados do caminho por hash, entao regerar o projeto
nao embaralha o arquivo e o diff no git continua legivel.

Rodar: python3 app/gerar_projeto.py
"""

import hashlib
import os

RAIZ = os.path.dirname(os.path.abspath(__file__))
NOME = "Canario"
# IDENTIDADE DA LOJA -- mude aqui e em lugar nenhum mais.
#
# Este script e o jeito documentado de adicionar uma tela: cria o .swift e
# roda. Ate 19/08/2026 rodar era uma armadilha, porque ele reescrevia o bundle
# para `com.canario.app` -- que nao tem perfil de distribuicao -- e nao emitia
# DEVELOPMENT_TEAM nenhum. Quem adicionasse uma tela trocava a identidade do
# app sem ver, com a versao em revisao na Apple. Ja tinha acontecido uma vez
# por outro caminho (commit 8bb8dfd).
#
# `br.com.canario.ch3.app` e o bundle que esta em revisao e o que tem perfil de
# loja. `coletor/teste_identidade_do_app.py` confere que o que sai daqui e o
# que esta no .xcodeproj versionado, e falha se um dos dois andar sozinho.
BUNDLE = "br.com.canario.ch3.app"
TIME_DE_DESENVOLVIMENTO = "67AYPRFZH8"
IOS_MINIMO = "17.0"
VERSAO_DO_APP = "1.2"
BUILD_DO_APP = "2"
GOOGLE_SIGN_IN_VERSAO = "9.0.0"
GOOGLE_SIGN_IN_REPOSITORIO = "https://github.com/google/GoogleSignIn-iOS"


def ident(*partes):
    """ID de 24 hex, estavel para o mesmo caminho."""
    h = hashlib.md5(("::".join(partes)).encode()).hexdigest()
    return h[:24].upper()


def fontes():
    base = os.path.join(RAIZ, NOME)
    achados = []
    for atual, _dirs, nomes in os.walk(base):
        # Nao desce dentro do catalogo de assets: ele entra inteiro como um
        # recurso so, e os PNGs de dentro nao sao arquivos do projeto.
        if ".xcassets" in atual:
            continue
        for n in sorted(nomes):
            if n.endswith(".swift"):
                achados.append(os.path.relpath(os.path.join(atual, n), RAIZ))
    return sorted(achados)


def fontes_de_ui_test():
    base = os.path.join(RAIZ, "CanarioUITests")
    if not os.path.isdir(base):
        return []
    return sorted(
        os.path.relpath(os.path.join(base, n), RAIZ)
        for n in os.listdir(base) if n.endswith(".swift"))


# Recursos que precisam ser EMPACOTADOS no .app, e nao compilados.
#
# Existe porque o gerador so conhecia `.swift`, e sem isto o TestFlight recusa
# o envio: a validacao da Apple exige icone, e `ASSETCATALOG_COMPILER_APPICON_NAME`
# ja apontava para um `AppIcon` que nao existia em lugar nenhum.
def recursos():
    achados = []
    for nome, tipo in (("Assets.xcassets", "folder.assetcatalog"),
                       ("PrivacyInfo.xcprivacy", "text.plist.xml"),
                       ("Localizable.xcstrings", "text.json.xcstrings")):
        caminho = os.path.join(RAIZ, NOME, nome)
        if os.path.exists(caminho):
            achados.append((os.path.join(NOME, nome), nome, tipo))
    return achados


def main():
    arquivos = fontes()
    arquivos_ui = fontes_de_ui_test()
    if not arquivos:
        raise SystemExit("Nenhum .swift encontrado em {}/".format(NOME))
    pacote = recursos()

    proj = ident("projeto")
    alvo = ident("alvo")
    produto = ident("produto")
    alvo_ui = ident("alvo", "ui-tests")
    produto_ui = ident("produto", "ui-tests")
    fase_fontes = ident("fase", "fontes")
    fase_frameworks = ident("fase", "frameworks")
    fase_recursos = ident("fase", "recursos")
    fase_fontes_ui = ident("fase", "fontes", "ui-tests")
    fase_frameworks_ui = ident("fase", "frameworks", "ui-tests")
    fase_recursos_ui = ident("fase", "recursos", "ui-tests")
    lista_proj = ident("lista", "projeto")
    lista_alvo = ident("lista", "alvo")
    lista_alvo_ui = ident("lista", "alvo", "ui-tests")
    cfg_proj_debug = ident("cfg", "proj", "debug")
    cfg_proj_release = ident("cfg", "proj", "release")
    cfg_alvo_debug = ident("cfg", "alvo", "debug")
    cfg_alvo_release = ident("cfg", "alvo", "release")
    cfg_ui_debug = ident("cfg", "ui-tests", "debug")
    cfg_ui_release = ident("cfg", "ui-tests", "release")
    grupo_raiz = ident("grupo", "raiz")
    grupo_app = ident("grupo", "app")
    grupo_ui = ident("grupo", "ui-tests")
    grupo_produtos = ident("grupo", "produtos")
    proxy_ui = ident("proxy", "ui-tests", "app")
    dependencia_ui = ident("dependencia", "ui-tests", "app")
    pacote_google = ident("pacote", "GoogleSignIn")
    produto_google = ident("produto-pacote", "GoogleSignIn")
    build_google = ident("build-pacote", "GoogleSignIn")

    # Um grupo por pasta, para o navegador do Xcode espelhar o disco.
    pastas = sorted({os.path.dirname(a) for a in arquivos if os.path.dirname(a) != NOME})
    grupos_pasta = {p: ident("grupo", p) for p in pastas}

    L = []
    A = L.append
    A("// !$*UTF8*$!")
    A("{")
    A("\tarchiveVersion = 1;")
    A("\tclasses = {};")
    A("\tobjectVersion = 56;")
    A("\tobjects = {")

    # --- PBXBuildFile ---
    A("\n/* Begin PBXBuildFile section */")
    for a in arquivos:
        A("\t\t{} /* {} in Sources */ = {{isa = PBXBuildFile; fileRef = {} /* {} */; }};".format(
            ident("build", a), os.path.basename(a), ident("ref", a), os.path.basename(a)))
    for a in arquivos_ui:
        A("\t\t{} /* {} in Sources */ = {{isa = PBXBuildFile; fileRef = {} /* {} */; }};".format(
            ident("build", a), os.path.basename(a), ident("ref", a), os.path.basename(a)))
    for caminho, nome, _tipo in pacote:
        A("\t\t{} /* {} in Resources */ = {{isa = PBXBuildFile; fileRef = {} /* {} */; }};".format(
            ident("build", caminho), nome, ident("ref", caminho), nome))
    A("\t\t{} /* GoogleSignIn in Frameworks */ = {{isa = PBXBuildFile; productRef = {} /* GoogleSignIn */; }};".format(
        build_google, produto_google))
    A("/* End PBXBuildFile section */")

    # --- PBXFileReference ---
    A("\n/* Begin PBXFileReference section */")
    A('\t\t{} /* {}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; '
      'includeInIndex = 0; path = "{}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'.format(
          produto, NOME, NOME))
    A('\t\t{} /* {}UITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; '
      'includeInIndex = 0; path = "{}UITests.xctest"; sourceTree = BUILT_PRODUCTS_DIR; }};'.format(
          produto_ui, NOME, NOME))
    for a in arquivos:
        A('\t\t{} /* {} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
          'path = "{}"; sourceTree = "<group>"; }};'.format(
              ident("ref", a), os.path.basename(a), os.path.basename(a)))
    for a in arquivos_ui:
        A('\t\t{} /* {} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
          'path = "{}"; sourceTree = "<group>"; }};'.format(
              ident("ref", a), os.path.basename(a), os.path.basename(a)))
    A('\t\t{} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; '
      'path = Info.plist; sourceTree = "<group>"; }};'.format(ident("ref", "Info.plist")))
    for caminho, nome, tipo in pacote:
        A('\t\t{} /* {} */ = {{isa = PBXFileReference; lastKnownFileType = {}; '
          'path = "{}"; sourceTree = "<group>"; }};'.format(
              ident("ref", caminho), nome, tipo, nome))
    # O Config.xcconfig vive na raiz do repositorio (fora de app/), porque e
    # ele que o README manda copiar do .example. Sem esta referencia, o
    # $(SUPABASE_URL) do Info.plist nunca e substituido e o app sobe sem
    # saber falar com o servidor -- compila, mas nao conecta.
    # sourceTree = SOURCE_ROOT resolve a partir da pasta do .xcodeproj (app/),
    # e nao do grupo -- com "<group>" o caminho cairia em app/Canario/../, que
    # e app/, e o arquivo esta um nivel acima.
    A('\t\t{} /* Config.xcconfig */ = {{isa = PBXFileReference; '
      'lastKnownFileType = text.xcconfig; name = Config.xcconfig; '
      'path = "../Config.xcconfig"; sourceTree = SOURCE_ROOT; }};'.format(
          ident("ref", "Config.xcconfig")))
    A("/* End PBXFileReference section */")

    # --- PBXContainerItemProxy ---
    A("\n/* Begin PBXContainerItemProxy section */")
    A("\t\t{} = {{".format(proxy_ui))
    A("\t\t\tisa = PBXContainerItemProxy;")
    A("\t\t\tcontainerPortal = {} /* Project object */;".format(proj))
    A("\t\t\tproxyType = 1;")
    A("\t\t\tremoteGlobalIDString = {};".format(alvo))
    A("\t\t\tremoteInfo = {};".format(NOME))
    A("\t\t};")
    A("/* End PBXContainerItemProxy section */")

    # --- PBXFrameworksBuildPhase ---
    A("\n/* Begin PBXFrameworksBuildPhase section */")
    A("\t\t{} = {{".format(fase_frameworks))
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (\n\t\t\t\t{} /* GoogleSignIn in Frameworks */,\n\t\t\t);".format(
        build_google))
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("\t\t{} = {{".format(fase_frameworks_ui))
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = ();")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXFrameworksBuildPhase section */")

    # --- PBXGroup ---
    A("\n/* Begin PBXGroup section */")
    A("\t\t{} = {{".format(grupo_raiz))
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A("\t\t\t\t{} /* {} */,".format(grupo_app, NOME))
    A("\t\t\t\t{} /* {}UITests */,".format(grupo_ui, NOME))
    A("\t\t\t\t{} /* Products */,".format(grupo_produtos))
    A("\t\t\t);")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")

    A("\t\t{} /* Products */ = {{".format(grupo_produtos))
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (\n\t\t\t\t{} /* {}.app */,\n\t\t\t\t{} /* {}UITests.xctest */,\n\t\t\t);".format(
        produto, NOME, produto_ui, NOME))
    A("\t\t\tname = Products;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")

    A("\t\t{} /* {}UITests */ = {{".format(grupo_ui, NOME))
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    for a in arquivos_ui:
        A("\t\t\t\t{} /* {} */,".format(ident("ref", a), os.path.basename(a)))
    A("\t\t\t);")
    A('\t\t\tpath = "{}UITests";'.format(NOME))
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")

    raiz_direto = [a for a in arquivos if os.path.dirname(a) == NOME]
    A("\t\t{} /* {} */ = {{".format(grupo_app, NOME))
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    for a in raiz_direto:
        A("\t\t\t\t{} /* {} */,".format(ident("ref", a), os.path.basename(a)))
    for p in pastas:
        A("\t\t\t\t{} /* {} */,".format(grupos_pasta[p], os.path.basename(p)))
    for caminho, nome, _tipo in pacote:
        A("\t\t\t\t{} /* {} */,".format(ident("ref", caminho), nome))
    A("\t\t\t\t{} /* Info.plist */,".format(ident("ref", "Info.plist")))
    A("\t\t\t\t{} /* Config.xcconfig */,".format(ident("ref", "Config.xcconfig")))
    A("\t\t\t);")
    A('\t\t\tpath = "{}";'.format(NOME))
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")

    for p in pastas:
        dentro = [a for a in arquivos if os.path.dirname(a) == p]
        A("\t\t{} /* {} */ = {{".format(grupos_pasta[p], os.path.basename(p)))
        A("\t\t\tisa = PBXGroup;")
        A("\t\t\tchildren = (")
        for a in dentro:
            A("\t\t\t\t{} /* {} */,".format(ident("ref", a), os.path.basename(a)))
        A("\t\t\t);")
        A('\t\t\tpath = "{}";'.format(os.path.basename(p)))
        A("\t\t\tsourceTree = \"<group>\";")
        A("\t\t};")
    A("/* End PBXGroup section */")

    # --- PBXNativeTarget ---
    A("\n/* Begin PBXNativeTarget section */")
    A("\t\t{} /* {} */ = {{".format(alvo, NOME))
    A("\t\t\tisa = PBXNativeTarget;")
    A("\t\t\tbuildConfigurationList = {} ;".format(lista_alvo))
    A("\t\t\tbuildPhases = (")
    A("\t\t\t\t{} ,".format(fase_fontes))
    A("\t\t\t\t{} ,".format(fase_frameworks))
    A("\t\t\t\t{} ,".format(fase_recursos))
    A("\t\t\t);")
    A("\t\t\tbuildRules = ();")
    A("\t\t\tdependencies = ();")
    A('\t\t\tname = "{}";'.format(NOME))
    A('\t\t\tproductName = "{}";'.format(NOME))
    A("\t\t\tproductReference = {} ;".format(produto))
    A("\t\t\tpackageProductDependencies = (\n\t\t\t\t{} /* GoogleSignIn */,\n\t\t\t);".format(
        produto_google))
    A('\t\t\tproductType = "com.apple.product-type.application";')
    A("\t\t};")
    A("\t\t{} /* {}UITests */ = {{".format(alvo_ui, NOME))
    A("\t\t\tisa = PBXNativeTarget;")
    A("\t\t\tbuildConfigurationList = {} ;".format(lista_alvo_ui))
    A("\t\t\tbuildPhases = (")
    A("\t\t\t\t{} ,".format(fase_fontes_ui))
    A("\t\t\t\t{} ,".format(fase_frameworks_ui))
    A("\t\t\t\t{} ,".format(fase_recursos_ui))
    A("\t\t\t);")
    A("\t\t\tbuildRules = ();")
    A("\t\t\tdependencies = (\n\t\t\t\t{} ,\n\t\t\t);".format(dependencia_ui))
    A('\t\t\tname = "{}UITests";'.format(NOME))
    A('\t\t\tproductName = "{}UITests";'.format(NOME))
    A("\t\t\tproductReference = {} ;".format(produto_ui))
    A('\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";')
    A("\t\t};")
    A("/* End PBXNativeTarget section */")

    # --- PBXProject ---
    A("\n/* Begin PBXProject section */")
    A("\t\t{} /* Project object */ = {{".format(proj))
    A("\t\t\tisa = PBXProject;")
    A("\t\t\tattributes = {{ BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; "
      "LastUpgradeCheck = 1600; TargetAttributes = {{ "
      "{} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {}; }}; }}; }};".format(
          alvo_ui, alvo))
    A("\t\t\tbuildConfigurationList = {} ;".format(lista_proj))
    A('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    A("\t\t\tdevelopmentRegion = en;")
    A("\t\t\thasScannedForEncodings = 0;")
    # pt-BR entra aqui, e nao so no catalogo: sem a regiao declarada no
    # projeto, o Xcode compila o .xcstrings mas nao empacota o pt-BR.lproj --
    # e o app fica com a troca de idioma ligada e sem tradução para servir.
    A("\t\t\tknownRegions = (en, \"pt-BR\", Base, );")
    A("\t\t\tmainGroup = {} ;".format(grupo_raiz))
    A("\t\t\tproductRefGroup = {} ;".format(grupo_produtos))
    A("\t\t\tpackageReferences = (\n\t\t\t\t{} /* XCRemoteSwiftPackageReference \"GoogleSignIn-iOS\" */,\n\t\t\t);".format(
        pacote_google))
    A('\t\t\tprojectDirPath = "";')
    A('\t\t\tprojectRoot = "";')
    A("\t\t\ttargets = (\n\t\t\t\t{} ,\n\t\t\t\t{} ,\n\t\t\t);".format(
        alvo, alvo_ui))
    A("\t\t};")
    A("/* End PBXProject section */")

    # --- PBXResourcesBuildPhase ---
    A("\n/* Begin PBXResourcesBuildPhase section */")
    A("\t\t{} = {{".format(fase_recursos))
    A("\t\t\tisa = PBXResourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    if pacote:
        A("\t\t\tfiles = (")
        for caminho, nome, _tipo in pacote:
            A("\t\t\t\t{} /* {} in Resources */,".format(ident("build", caminho), nome))
        A("\t\t\t);")
    else:
        A("\t\t\tfiles = ();")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("\t\t{} = {{".format(fase_recursos_ui))
    A("\t\t\tisa = PBXResourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = ();")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXResourcesBuildPhase section */")

    # --- PBXSourcesBuildPhase ---
    A("\n/* Begin PBXSourcesBuildPhase section */")
    A("\t\t{} = {{".format(fase_fontes))
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for a in arquivos:
        A("\t\t\t\t{} /* {} in Sources */,".format(ident("build", a), os.path.basename(a)))
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("\t\t{} = {{".format(fase_fontes_ui))
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for a in arquivos_ui:
        A("\t\t\t\t{} /* {} in Sources */,".format(
            ident("build", a), os.path.basename(a)))
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXSourcesBuildPhase section */")

    # --- XCBuildConfiguration ---
    comuns = [
        'ALWAYS_SEARCH_USER_PATHS = NO;',
        'CLANG_ENABLE_MODULES = YES;',
        'CLANG_ENABLE_OBJC_ARC = YES;',
        'ENABLE_STRICT_OBJC_MSGSEND = YES;',
        'GCC_C_LANGUAGE_STANDARD = gnu17;',
        'IPHONEOS_DEPLOYMENT_TARGET = {};'.format(IOS_MINIMO),
        'MTL_FAST_MATH = YES;',
        'SDKROOT = iphoneos;',
        'SWIFT_VERSION = 5.0;',
    ]
    alvo_comuns = [
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
        'CODE_SIGN_STYLE = Automatic;',
        'CODE_SIGN_ENTITLEMENTS = "{}/Canario.entitlements";'.format(NOME),
        'CURRENT_PROJECT_VERSION = {};'.format(BUILD_DO_APP),
        'DEVELOPMENT_TEAM = {};'.format(TIME_DE_DESENVOLVIMENTO),
        'ENABLE_PREVIEWS = YES;',
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = "{}/Info.plist";'.format(NOME),
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;',
        'INFOPLIST_KEY_UILaunchScreen_Generation = YES;',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", );',
        'MARKETING_VERSION = {};'.format(VERSAO_DO_APP),
        'PRODUCT_BUNDLE_IDENTIFIER = "{}";'.format(BUNDLE),
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SWIFT_EMIT_LOC_STRINGS = YES;',
        'TARGETED_DEVICE_FAMILY = 1;',
    ]
    ui_comuns = [
        'CODE_SIGN_STYLE = Automatic;',
        'CURRENT_PROJECT_VERSION = {};'.format(BUILD_DO_APP),
        'DEVELOPMENT_TEAM = {};'.format(TIME_DE_DESENVOLVIMENTO),
        'GENERATE_INFOPLIST_FILE = YES;',
        'MARKETING_VERSION = {};'.format(VERSAO_DO_APP),
        'PRODUCT_BUNDLE_IDENTIFIER = "{}.UITests";'.format(BUNDLE),
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SWIFT_EMIT_LOC_STRINGS = NO;',
        'TARGETED_DEVICE_FAMILY = 1;',
        'TEST_TARGET_NAME = {};'.format(NOME),
    ]

    A("\n/* Begin XCBuildConfiguration section */")
    for cid, nome, extra in [
        (cfg_proj_debug, "Debug", ['DEBUG_INFORMATION_FORMAT = dwarf;',
                                   'ENABLE_TESTABILITY = YES;',
                                   'GCC_OPTIMIZATION_LEVEL = 0;',
                                   'ONLY_ACTIVE_ARCH = YES;',
                                   'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
                                   # O padrão do Xcode, que o gerador não
                                   # emitia: sem isto `#if DEBUG` nunca compila,
                                   # e ferramenta de desenvolvimento some calada.
                                   'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;']),
        (cfg_proj_release, "Release", ['DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
                                       'ENABLE_NS_ASSERTIONS = NO;',
                                       'SWIFT_COMPILATION_MODE = wholemodule;',
                                       'VALIDATE_PRODUCT = YES;']),
    ]:
        A("\t\t{} /* {} */ = {{".format(cid, nome))
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        for s in comuns + extra:
            A("\t\t\t\t" + s)
        A("\t\t\t};")
        A('\t\t\tname = "{}";'.format(nome))
        A("\t\t};")

    for cid, nome in [(cfg_alvo_debug, "Debug"), (cfg_alvo_release, "Release")]:
        A("\t\t{} /* {} */ = {{".format(cid, nome))
        A("\t\t\tisa = XCBuildConfiguration;")
        # E daqui que SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY entram no build.
        A("\t\t\tbaseConfigurationReference = {} /* Config.xcconfig */;".format(
            ident("ref", "Config.xcconfig")))
        A("\t\t\tbuildSettings = {")
        for s in alvo_comuns:
            A("\t\t\t\t" + s)
        A("\t\t\t};")
        A('\t\t\tname = "{}";'.format(nome))
        A("\t\t};")
    for cid, nome in [(cfg_ui_debug, "Debug"), (cfg_ui_release, "Release")]:
        A("\t\t{} /* {} */ = {{".format(cid, nome))
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        for s in ui_comuns:
            A("\t\t\t\t" + s)
        A("\t\t\t};")
        A('\t\t\tname = "{}";'.format(nome))
        A("\t\t};")
    A("/* End XCBuildConfiguration section */")

    # --- XCConfigurationList ---
    A("\n/* Begin XCConfigurationList section */")
    for lid, d, r, alvo_de in [(lista_proj, cfg_proj_debug, cfg_proj_release, "PBXProject"),
                               (lista_alvo, cfg_alvo_debug, cfg_alvo_release, "PBXNativeTarget"),
                               (lista_alvo_ui, cfg_ui_debug, cfg_ui_release, "PBXNativeTarget")]:
        A("\t\t{} /* Build configuration list for {} */ = {{".format(lid, alvo_de))
        A("\t\t\tisa = XCConfigurationList;")
        A("\t\t\tbuildConfigurations = (\n\t\t\t\t{} ,\n\t\t\t\t{} ,\n\t\t\t);".format(d, r))
        A("\t\t\tdefaultConfigurationIsVisible = 0;")
        A("\t\t\tdefaultConfigurationName = Release;")
        A("\t\t};")
    A("/* End XCConfigurationList section */")

    # --- Swift Package Manager ---
    A("\n/* Begin XCRemoteSwiftPackageReference section */")
    A('\t\t{} /* XCRemoteSwiftPackageReference "GoogleSignIn-iOS" */ = {{'.format(
        pacote_google))
    A("\t\t\tisa = XCRemoteSwiftPackageReference;")
    A('\t\t\trepositoryURL = "{}";'.format(GOOGLE_SIGN_IN_REPOSITORIO))
    A("\t\t\trequirement = { kind = exactVersion; version = %s; };" % GOOGLE_SIGN_IN_VERSAO)
    A("\t\t};")
    A("/* End XCRemoteSwiftPackageReference section */")

    A("\n/* Begin XCSwiftPackageProductDependency section */")
    A("\t\t{} /* GoogleSignIn */ = {{".format(produto_google))
    A("\t\t\tisa = XCSwiftPackageProductDependency;")
    A("\t\t\tpackage = {} /* XCRemoteSwiftPackageReference \"GoogleSignIn-iOS\" */;".format(
        pacote_google))
    A("\t\t\tproductName = GoogleSignIn;")
    A("\t\t};")
    A("/* End XCSwiftPackageProductDependency section */")

    # --- PBXTargetDependency ---
    A("\n/* Begin PBXTargetDependency section */")
    A("\t\t{} = {{isa = PBXTargetDependency; target = {}; targetProxy = {}; }};".format(
        dependencia_ui, alvo, proxy_ui))
    A("/* End PBXTargetDependency section */")

    A("\t};")
    A("\trootObject = {} /* Project object */;".format(proj))
    A("}")

    destino = os.path.join(RAIZ, "{}.xcodeproj".format(NOME))
    os.makedirs(destino, exist_ok=True)
    with open(os.path.join(destino, "project.pbxproj"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("Gerado: {} com {} arquivos Swift".format(destino, len(arquivos)))


if __name__ == "__main__":
    main()
