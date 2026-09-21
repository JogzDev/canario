"""O que o app faz com imagem e o que os documentos publicos dizem sao a mesma coisa.

POR QUE ISTO EXISTE
===================

Em 25/08/2026 a A44 entrou em producao e passou a sincronizar a miniatura
reduzida do Closet para um bucket privado. Tres coisas foram atualizadas na
mesma leva -- o codigo, o `PrivacyInfo.xcprivacy` e a copy dentro do app -- e
duas nao foram:

* `POLITICA_PUBLICA_1.2.md` continuou afirmando "Closet thumbnails and original
  photos are not uploaded as part of account sync" e "No Closet-photo sync in
  version 1.2";
* `FICHA_APP_STORE_1.2.md` continuou declarando `Photos or Videos` como NAO
  vinculado ao usuario, contra o manifesto, que ja dizia `Linked = true`.

Isso nao e documentacao desatualizada como as outras: e **declaracao de
privacidade errada**, publicada para o usuario e enviada a Apple. Divergencia
entre a etiqueta de privacidade e o comportamento do binario e motivo direto de
rejeicao, e ninguem percebeu porque nada conferia.

O `teste_identidade_do_app.py` ja provou que o remedio para "a mesma informacao
escrita em dois lugares" e um conferidor. Este e o conferidor do que sai do
aparelho. Ele nao decide a politica de privacidade -- decide que so existe uma.

O gatilho e o CODIGO, nunca o documento: se o app parar de sincronizar
miniatura, este teste passa a exigir o texto oposto sozinho.
"""

import os
import plistlib
import re
import sys


RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(RAIZ, "app", "Canario")
MANIFESTO = os.path.join(APP, "PrivacyInfo.xcprivacy")
SYNC = os.path.join(APP, "Rede", "SincronizacaoDoCloset.swift")
EXCLUIR = os.path.join(RAIZ, "supabase", "functions", "excluir-conta", "index.ts")
REGISTRAR_APPLE = os.path.join(
    RAIZ, "supabase", "functions", "registrar-credencial-apple", "index.ts")
APPLE_COMPARTILHADO = os.path.join(
    RAIZ, "supabase", "functions", "_shared", "apple-sign-in.ts")
APPLE_MIGRACAO = os.path.join(
    RAIZ, "supabase", "migrations", "20260831152000_a50_tokens_de_revogacao_apple.sql")
APPLE_MIGRACAO_CIFRA = os.path.join(
    RAIZ, "supabase", "migrations", "20260921164500_a59_cifra_tokens_de_revogacao_apple.sql")
APPLE_CIFRA = os.path.join(
    RAIZ, "supabase", "functions", "_shared", "apple-refresh-token-crypto.ts")
ANALISE = os.path.join(RAIZ, "supabase", "functions", "analisar-peca", "index.ts")
BUCKET = "closet-thumbnails"

# Frases que descreviam o binario ANTERIOR a A44. Enquanto o app subir
# miniatura, nenhuma delas pode voltar a um documento publico -- foi exatamente
# esse texto que ficou no ar contradizendo o app.
NEGACOES_VENCIDAS = [
    "Closet photos remain on the iPhone",
    "Closet photos stay on this iPhone",
    "thumbnails and original photos are not uploaded",
    "No Closet-photo sync",
    "only structured Closet details sync",
]


def ler(caminho):
    try:
        return open(caminho, encoding="utf-8").read()
    except OSError as exc:
        print("FALHOU: arquivo obrigatorio ausente: {} ({})".format(caminho, exc))
        return None


def versao_do_app():
    """A versao vem do gerador, que e a fonte unica ja usada pela identidade."""
    fonte = ler(os.path.join(RAIZ, "app", "gerar_projeto.py"))
    if fonte is None:
        return None
    achado = re.search(r'^VERSAO_DO_APP\s*=\s*"([^"]+)"', fonte, re.M)
    return achado.group(1) if achado else None


def main():
    versao = versao_do_app()
    if not versao:
        print("FALHOU: gerar_projeto.py nao define VERSAO_DO_APP")
        return 1

    sync = ler(SYNC)
    if sync is None:
        return 1

    # 1. A pergunta de fato: o binario sobe imagem do Closet?
    sobe_miniatura = BUCKET in sync and "storage/v1/object" in sync

    ficha = ler(os.path.join(RAIZ, "FICHA_APP_STORE_{}.md".format(versao)))
    politica = ler(os.path.join(RAIZ, "POLITICA_PUBLICA_{}.md".format(versao)))
    if ficha is None or politica is None:
        return 1

    try:
        manifesto = plistlib.load(open(MANIFESTO, "rb"))
    except (OSError, ValueError) as exc:
        print("FALHOU: PrivacyInfo.xcprivacy invalido: {}".format(exc))
        return 1

    tipos = manifesto.get("NSPrivacyCollectedDataTypes", [])

    def exigir_tipo(nome, ligado):
        encontrados = [t for t in tipos if t.get("NSPrivacyCollectedDataType") == nome]
        if len(encontrados) != 1:
            print("FALHOU: o manifesto precisa declarar {!r} exatamente uma "
                  "vez; declarou {}".format(nome, len(encontrados)))
            return False
        item = encontrados[0]
        if bool(item.get("NSPrivacyCollectedDataTypeLinked")) != ligado:
            print("FALHOU: {!r} tem Linked incorreto (esperado {})".format(
                nome, ligado))
            return False
        if bool(item.get("NSPrivacyCollectedDataTypeTracking")):
            print("FALHOU: {!r} foi marcado como tracking".format(nome))
            return False
        if item.get("NSPrivacyCollectedDataTypePurposes") != [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"]:
            print("FALHOU: {!r} precisa ter somente App Functionality como "
                  "finalidade".format(nome))
            return False
        return True

    # O código é novamente o gatilho. Favorito e rejeição de similares são
    # interações sincronizadas; o hash de origem fica sete dias no servidor.
    # Se essas coletas saírem do binário, o teste deixa de exigi-las.
    interacao_sincronizada = (
        "similaresRejeitados" in sync and "favorita" in sync)
    analise = ler(ANALISE)
    if analise is None:
        return 1
    identificador_de_origem = (
        "AI_RATE_LIMIT_SALT" in analise
        and "_reservar_analise_visual" in analise
        and "originHash" in analise)

    if interacao_sincronizada:
        if not exigir_tipo("NSPrivacyCollectedDataTypeProductInteraction", True):
            return 1
        ficha_lisa = re.sub(r"[*_`]", "", ficha)
        if not re.search(r"Usage Data\s*→\s*Product Interaction\s*\|\s*sim\s*\|\s*sim",
                         ficha_lisa):
            print("FALHOU: a ficha nao declara Product Interaction vinculado")
            return 1

    if identificador_de_origem:
        if not exigir_tipo("NSPrivacyCollectedDataTypeDeviceID", False):
            return 1
        ficha_lisa = re.sub(r"[*_`]", "", ficha)
        if not re.search(r"Identifiers\s*→\s*Device ID\s*\|\s*sim\s*\|\s*não",
                         ficha_lisa):
            print("FALHOU: a ficha nao declara Device ID nao vinculado")
            return 1

    fotos = [t for t in tipos
             if t.get("NSPrivacyCollectedDataType")
             == "NSPrivacyCollectedDataTypePhotosorVideos"]
    if len(fotos) != 1:
        print("FALHOU: o manifesto precisa declarar `Photos or Videos` "
              "exatamente uma vez; declarou {}".format(len(fotos)))
        return 1
    vinculado_no_manifesto = bool(fotos[0].get("NSPrivacyCollectedDataTypeLinked"))

    # 2. Sincronizar miniatura vincula imagem a uma conta. Manifesto e ficha
    #    precisam dizer isso juntos: um `Linked = false` com upload por
    #    `auth.uid` e uma etiqueta de privacidade falsa.
    if sobe_miniatura and not vinculado_no_manifesto:
        print("FALHOU: o app envia miniatura para o bucket {!r}, mas o "
              "PrivacyInfo declara `Photos or Videos` como nao vinculado".format(
                  BUCKET))
        return 1
    if not sobe_miniatura and vinculado_no_manifesto:
        print("FALHOU: o app nao envia mais miniatura, mas o PrivacyInfo "
              "continua declarando `Photos or Videos` como vinculado")
        return 1

    # O negrito do markdown cai antes da comparacao: o que importa e a frase,
    # nao onde os asteriscos foram parar.
    ficha_lisa = re.sub(r"[*_`]", "", ficha)
    declara_vinculado = bool(re.search(
        r"Photos or Videos collected:\s*Yes,\s*linked to the user", ficha_lisa))
    if vinculado_no_manifesto != declara_vinculado:
        print("FALHOU: a ficha da App Store e o PrivacyInfo discordam sobre "
              "`Photos or Videos` estar vinculado ao usuario "
              "(manifesto={}, ficha={})".format(
                  vinculado_no_manifesto, declara_vinculado))
        return 1

    if not sobe_miniatura:
        print("Privacidade declarada: o app nao sincroniza imagem do Closet e "
              "manifesto e ficha dizem o mesmo")
        return 0

    # 3. As negacoes vencidas nao podem voltar a nenhum documento publico.
    for nome, texto in (("FICHA_APP_STORE_{}.md".format(versao), ficha),
                        ("POLITICA_PUBLICA_{}.md".format(versao), politica)):
        for frase in NEGACOES_VENCIDAS:
            if frase in texto:
                print("FALHOU: {} afirma {!r}, mas o app sincroniza miniatura "
                      "desde a A44".format(nome, frase))
                return 1

    # 4. Nao basta parar de negar: os dois precisam DESCREVER o que sobe, e
    #    manter as duas promessas que continuam verdadeiras.
    exigidos = {
        "FICHA_APP_STORE_{}.md".format(versao): (ficha, [
            "thumbnail",
            "720",
            "original photos stay on this iphone",
        ]),
        "POLITICA_PUBLICA_{}.md".format(versao): (politica, [
            "thumbnail",
            "720",
            "the original photo is never uploaded",
            "deleting your account deletes every thumbnail",
        ]),
    }
    for nome, (texto, trechos) in exigidos.items():
        minusculo = texto.lower()
        faltando = [trecho for trecho in trechos if trecho not in minusculo]
        if faltando:
            print("FALHOU: {} nao descreve a sincronizacao de miniatura; "
                  "faltam: {}".format(nome, ", ".join(repr(x) for x in faltando)))
            return 1

    # 5. A promessa de exclusao precisa de codigo atras dela. Apagar o usuario
    #    NAO apaga objeto de bucket: sem esta purga, a politica prometeria uma
    #    coisa que o servidor nao faz.
    excluir = ler(EXCLUIR)
    if excluir is None:
        return 1
    # Comentario nao conta: a ordem conferida e a das CHAMADAS, senao a propria
    # frase que explica a ordem certa reprovaria o arquivo.
    codigo = "\n".join(linha for linha in excluir.splitlines()
                       if not linha.lstrip().startswith("//"))
    if BUCKET not in codigo or ".remove(" not in codigo:
        print("FALHOU: excluir-conta nao remove as miniaturas do bucket {!r}, "
              "mas a politica promete que a exclusao apaga todas".format(BUCKET))
        return 1
    if "admin.deleteUser(" not in codigo:
        print("FALHOU: excluir-conta nao chama admin.deleteUser")
        return 1
    if codigo.index(".remove(") > codigo.index("admin.deleteUser("):
        print("FALHOU: excluir-conta apaga o usuario ANTES de purgar o bucket; "
              "depois do deleteUser os objetos ficam orfaos")
        return 1

    # 6. Sign in with Apple só é revogável por REST se o authorization code
    #    nativo for trocado e o refresh token ficar no servidor. A interface
    #    pode oferecer o caminho manual para sessões legadas, mas novo código
    #    não pode voltar a fingir que deleteUser revoga a autorização Apple.
    registrar_apple = ler(REGISTRAR_APPLE)
    apple_compartilhado = ler(APPLE_COMPARTILHADO)
    migracao_apple = ler(APPLE_MIGRACAO)
    if registrar_apple is None or apple_compartilhado is None or migracao_apple is None:
        return 1
    if ("authorization_code" not in registrar_apple
            or "trocarCodigoApple" not in registrar_apple
            or "apple_refresh_tokens" not in registrar_apple):
        print("FALHOU: novo login Apple nao troca e guarda o refresh token "
              "necessario para a revogacao REST")
        return 1
    if ("APPLE_AUDIENCE" not in apple_compartilhado
            or "/auth/revoke" not in apple_compartilhado
            or "refresh_token" not in apple_compartilhado):
        print("FALHOU: a revogacao REST da Apple nao usa o endpoint/token esperado")
        return 1
    if ("revogarTokenApple" not in codigo
            or "apple_revocation" not in codigo
            or "apple_refresh_tokens" not in codigo):
        print("FALHOU: excluir-conta nao chama a revogacao Apple antes do delete")
        return 1
    if ("force row level security" not in migracao_apple.lower()
            or "revoke all on table public.apple_refresh_tokens" not in migracao_apple.lower()
            or "on delete cascade" not in migracao_apple.lower()):
        print("FALHOU: refresh token Apple nao esta protegido e acoplado a exclusao")
        return 1

    # A59: o novo login so grava cifra; Delete account suporta tanto a linha
    # legada quanto a cifrada e falha para revogacao manual se a chave faltar.
    cifra = ler(APPLE_CIFRA)
    migracao_cifra = ler(APPLE_MIGRACAO_CIFRA)
    if cifra is None or migracao_cifra is None:
        return 1
    if ("AES-GCM" not in cifra
            or "additionalData: dadosAssociados(userId)" not in cifra
            or "APPLE_REFRESH_TOKEN_KEY_VERSION" not in cifra
            or "APPLE_REFRESH_TOKEN_KEY_V${versao}" not in cifra
            or "refresh_token: null" not in registrar_apple
            or "cifrarTokenAppleComChave" not in registrar_apple
            or "recuperarTokenApple" not in codigo
            or "manual_required" not in codigo
            or "refresh_token_cifrado" not in migracao_cifra):
        print("FALHOU: A59 perdeu cifra, rotacao ou fallback de exclusao Apple")
        return 1

    print("Privacidade declarada: app, manifesto, ficha, politica e "
          "excluir-conta concordam sobre miniatura e revogacao Apple")
    return 0


if __name__ == "__main__":
    sys.exit(main())
