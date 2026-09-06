#!/usr/bin/env python3
"""Leva as chaves de `frase(_:)` para dentro do Localizable.xcstrings.

POR QUE ISTO EXISTE
===================

O Xcode extrai sozinho todo literal que chega a `Text(_:)`, `Button(_:)` ou
`String(localized:)`. Ele NAO extrai os que passam por uma funcao propria, e
`frase(_:)` e uma funcao propria -- ela existe justamente para alcancar as
centenas de frases que o app monta como `String` e mostra depois, que o
`LocalizedStringKey` do SwiftUI nunca ve.

Sem este passo o efeito seria silencioso e caro: o app compila, roda, troca de
idioma e continua em ingles nessas frases, sem erro nenhum na tela. Aqui a
divergencia vira numero na saida do comando, e o portao a transforma em falha.

COMO A CHAVE E FORMADA
======================

`frase("...")` recebe uma `String.LocalizationValue`. O compilador transforma
cada interpolacao no especificador do tipo interpolado; como a regra do projeto
e interpolar somente `String` dentro de `frase` (ver `Idioma.swift`), toda
interpolacao vira `%@` e a chave e previsivel. Este script aplica a mesma regra.

USO
===

    python3 ferramentas/extrair_frases.py --conferir   # so relata (portao)
    python3 ferramentas/extrair_frases.py --escrever   # acrescenta ao catalogo
"""
import argparse
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTES = os.path.join(RAIZ, "app", "Canario")
CATALOGO = os.path.join(FONTES, "Localizable.xcstrings")

# `frase("...")` -- as frases que o app monta como String.
ABERTURA = re.compile(r'\bfrase\(\s*"')

# Os construtores do SwiftUI que recebem `LocalizedStringKey`. O Xcode extrai
# estes sozinho DENTRO do Xcode, mas nao no `xcodebuild` da linha de comando que
# o portao usa -- e foi assim que "Language" e "Match iPhone language" chegaram
# ao simulador em ingles no meio de uma tela em portugues. Conferir os dois
# conjuntos no mesmo lugar e o que torna a lacuna visivel sem abrir o app.
SWIFTUI = re.compile(
    r'\bString\(localized:\s*"'
    r'|\b(?:Text|Button|Label|Toggle|Section|Picker|TextField|SecureField|'
    r'navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|'
    r'alert|confirmationDialog)\(\s*"'
    r'|\b(?:titleKey|prompt|message|titulo|texto|legenda|subtitulo|'
    r'mensagem|oQueTem)\s*:\s*"')

# `label:` e `rotulo:` ficaram de fora: o primeiro e tambem o nome de uma
# `DispatchQueue`, e o segundo e campo do modelo `Termo` (dado, nao tela).
#
# Os nomes em portugues entram porque os componentes proprios recebem texto por
# eles (`BlocoInformativo(titulo:texto:)`, `opcaoAnaliseVisual(titulo:)`). Um
# literal ali ou e chave de catalogo, ou e uma `String` crua que deveria estar
# envolvida em `frase(...)` -- os dois casos precisam aparecer. Foi por esta
# fresta que "Ask me the first time" chegou em ingles a uma tela em portugues.

# O especificador de formato, em qualquer forma. Existe porque o extrator nao
# tem compilador: `Text("Show all \(n) pieces")` com `n: Int` produz `%lld`, e
# `frase` produz sempre `%@`. Comparar as chaves normalizadas evita acusar
# ausencia onde ha so uma diferenca de tipo que o Swift ja resolveu.
FORMATO = re.compile(r'%(?:\d+\$)?(?:@|lld|ld|d|u|lf|f|\.\d+f)')


def normalizar(chave):
    return FORMATO.sub("%*", chave)


def eh_texto_de_tela(chave):
    """Descarta o que nunca foi frase: vazio, so simbolo, so especificador."""
    nucleo = FORMATO.sub("", chave).strip(" \u00b7\u2212%()[]{}.,:;\u2014-\n\t")
    return any(c.isalpha() for c in nucleo)


def _fatiar_literal(texto, inicio):
    """Devolve (conteudo_bruto, indice_apos_a_aspa_final) de um literal Swift.

    Percorre caractere a caractere porque um literal com interpolacao pode
    conter aspas dentro dos parenteses -- `\\(mapa["x"])` -- e qualquer regex de
    aspa a aspa cortaria no lugar errado.
    """
    i = inicio
    partes = []
    profundidade = 0
    while i < len(texto):
        c = texto[i]
        if c == "\\" and i + 1 < len(texto):
            seguinte = texto[i + 1]
            if seguinte == "(":
                profundidade = 1
                i += 2
                while i < len(texto) and profundidade:
                    if texto[i] == "(":
                        profundidade += 1
                    elif texto[i] == ")":
                        profundidade -= 1
                    elif texto[i] == '"':
                        # aspas dentro da interpolacao: pula o literal inteiro
                        i += 1
                        while i < len(texto) and texto[i] != '"':
                            i += 2 if texto[i] == "\\" else 1
                    i += 1
                partes.append("%@")
                continue
            partes.append(c + seguinte)
            i += 2
            continue
        if c == '"':
            return "".join(partes), i + 1
        partes.append(c)
        i += 1
    raise ValueError("literal sem fechamento a partir de {}".format(inicio))


def _desescapar(bruto):
    """Aplica os escapes do Swift que mudam o texto da chave."""
    return (bruto.replace("\\n", "\n").replace("\\t", "\t")
                 .replace('\\"', '"').replace("\\\\", "\\"))


def chaves_no_arquivo(caminho):
    with open(caminho, encoding="utf-8") as f:
        fonte = f.read()
    achadas = []
    for m in list(ABERTURA.finditer(fonte)) + list(SWIFTUI.finditer(fonte)):
        # Ignora ocorrencia dentro de comentario de linha: a documentacao deste
        # projeto cita `frase("...")` em prosa, e citar nao e chamar.
        inicio_da_linha = fonte.rfind("\n", 0, m.start()) + 1
        antes = fonte[inicio_da_linha:m.start()]
        if "//" in antes:
            continue
        conteudo, _ = _fatiar_literal(fonte, m.end())
        achadas.append(_desescapar(conteudo))
    return achadas


def todas_as_chaves():
    achadas = set()
    for pasta, _dirs, nomes in os.walk(FONTES):
        for nome in sorted(nomes):
            if nome.endswith(".swift"):
                achadas.update(chaves_no_arquivo(os.path.join(pasta, nome)))
    return achadas


def main():
    p = argparse.ArgumentParser(description=__doc__)
    grupo = p.add_mutually_exclusive_group(required=True)
    grupo.add_argument("--conferir", action="store_true",
                       help="falha quando alguma chave de interface nao esta no catalogo")
    grupo.add_argument("--escrever", action="store_true",
                       help="acrescenta as chaves ausentes, sem traducao")
    args = p.parse_args()

    with open(CATALOGO, encoding="utf-8") as f:
        catalogo = json.load(f)
    strings = catalogo["strings"]

    chaves = {k for k in todas_as_chaves() if eh_texto_de_tela(k)}
    # O catalogo e indexado tambem pela forma normalizada, para uma chave com
    # `%lld` no codigo casar com a mesma frase ja traduzida.
    por_normal = {}
    for k in strings:
        por_normal.setdefault(normalizar(k), k)

    def no_catalogo(chave):
        """A entrada do catalogo para `chave`, ou None.

        A versao anterior era
        `strings.get(chave) or strings.get(por_normal.get(normalizar(chave), ""))`
        e tinha um buraco que anulava o portao inteiro: quando a chave nao
        existia, `por_normal.get(..., "")` devolvia string vazia, e o catalogo
        TINHA uma chave vazia (lixo gravado por um `--escrever` anterior).
        `strings.get("")` devolvia entrada de verdade, o `or` a considerava
        verdadeira e toda chave ausente era reportada como presente. Medido em
        05/09 com "The flash always fires...", que o portao jurava estar no
        catalogo e nao estava.

        Agora a busca e explicita, e nao ha valor de fallback que possa casar
        com uma chave real.
        """
        if chave in strings:
            return strings[chave]
        equivalente = por_normal.get(normalizar(chave))
        return strings.get(equivalente) if equivalente is not None else None

    ausentes = sorted(k for k in chaves if no_catalogo(k) is None)
    sem_pt = sorted(k for k in chaves
                    if (entrada := no_catalogo(k)) is not None
                    and "pt-BR" not in entrada.get("localizations", {}))

    print("chaves de interface no codigo :", len(chaves))
    print("ausentes do catalogo        :", len(ausentes))
    print("no catalogo e sem pt-BR     :", len(sem_pt))

    if args.conferir:
        for k in ausentes:
            print("  AUSENTE:", json.dumps(k, ensure_ascii=False))
        for k in sem_pt:
            print("  SEM PT :", json.dumps(k, ensure_ascii=False))
        return 1 if (ausentes or sem_pt) else 0

    for k in ausentes:
        strings[k] = {"extractionState": "manual", "localizations": {
            "en": {"stringUnit": {"state": "new", "value": k}}}}
    with open(CATALOGO, "w", encoding="utf-8") as f:
        json.dump(catalogo, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print("acrescentadas               :", len(ausentes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
