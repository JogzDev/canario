#!/usr/bin/env python3
"""Acha prosa de tela que NAO passa por traducao.

POR QUE ESTE PORTAO EXISTE, SEPARADO DO OUTRO
=============================================

O `extrair_frases.py` confere que toda chave usada existe no catalogo e tem
pt-BR. Ele nao consegue ver a falha que sobrou, e a revisao do Codex nomeou
bem: *"o verificador confirma que determinadas chaves existem; nao confirma que
a tela realmente utiliza suas traducoes."*

Os tres casos medidos em 05/09, todos com o outro portao verde:

    "\\(numero) on the statistical scale, \\(lado) this attribute's..."
        `lado` era "above"/"below" cru. A frase de fora traduzia; o miolo nao.
        Na tela: "0,4 na escala estatistica, above o comportamento usual".

    "\\(ordinal)\\(suffix) \\(coisa) for size ... in \\(Formato.periodo(...))"
        Tudo ingles cravado, e `periodo` passou a devolver portugues.
        Na tela: "2nd restock for size G in 2 dias".

    case .pico: return "Spike"
        Nunca entrou no catalogo. O portao so confere chaves que existem.

O padrao comum e um literal de prosa que nao chega a `frase(...)` nem a um
construtor do SwiftUI. E o que este arquivo procura.

FALSO POSITIVO E O INIMIGO
==========================

Um portao com ruido vira portao ignorado. As regras de contexto abaixo tiram o
que e legitimo por construcao; o que sobra entra numa allowlist explicita, onde
cada linha precisa se justificar -- que e a mesma disciplina do
`teste_vocabulario.py`.

USO
===

    python3 ferramentas/frases_compostas.py --conferir
    python3 ferramentas/frases_compostas.py --listar   # sem falhar
"""
import argparse
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTES = os.path.join(RAIZ, "app", "Canario")
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "frases_compostas_permitidas.json")

FORMATO = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|u|lf|f|\.\d+f)")

# TUDO QUE LOCALIZA SOZINHO, NUMA LISTA SO.
#
# Havia duas listas -- uma regex para "esta na mesma linha" e um conjunto para
# "abriu o parentese la atras" -- e elas divergiram na primeira vez que alguem
# acrescentou um componente: `CoberturaInsuficiente` entrou numa e nao na outra,
# e o portao voltou a acusar chamadas legitimas. E o mesmo defeito que a
# `AbaDoApp` documenta sobre os rotulos das abas, e que este projeto ja pagou
# tres vezes. Uma lista, dois usos derivados dela.
ABREM_LOCALIZADO = {
    "frase", "Text", "Button", "Label", "Toggle", "Section", "Picker",
    "TextField", "SecureField", "navigationTitle", "accessibilityLabel",
    "accessibilityHint", "accessibilityValue", "accessibilityAction", "alert",
    "confirmationDialog", "ContentUnavailableView", "cabecalhoDeSecao",
    # Componentes proprios cujo parametro de texto E LocalizedStringKey.
    #
    # A lista e por CONSTRUTOR, e nao por nome de parametro, porque nome se
    # repete com tipo diferente: `BlocoInformativo(texto:)` e chave de catalogo
    # e `LinhaInsumo(texto:)` e String ja traduzida. Confiar no nome liberava os
    # dois, e o segundo e justamente o que precisa de `frase(...)`.
    #
    # Trocar o tipo de um destes para `String` sem tirar o nome daqui abre um
    # buraco silencioso. E o preco de nao ter um compilador aqui dentro.
    "BlocoInformativo", "TextoComTitulo", "CabecalhoDoMenu", "PecaSemFoto",
    "BotaoDeEntrada", "CoberturaInsuficiente", "opcaoAnaliseVisual", "Pergunta",
}


# Os dois usos, derivados da lista acima.
LOCALIZA = re.compile(
    r"\bString\(localized:|"
    r"\b(?:" + "|".join(sorted(ABREM_LOCALIZADO)) + r")\s*\(|"
    r"\b(?:titleKey|prompt|message)\s*:")

# `"chave": "valor"` -- tabela de dados, nao frase de tela. E como vivem os
# mapas de rotulo da taxonomia e os aliases de marca.
ENTRADA_DE_MAPA = re.compile(r'"[^"]*"\s*:\s*$')


def fatiar(texto, inicio):
    """Le um literal Swift a partir do indice DEPOIS da aspa de abertura."""
    i = inicio
    partes = []
    while i < len(texto):
        c = texto[i]
        if c == "\\" and i + 1 < len(texto):
            if texto[i + 1] == "(":
                prof, j = 1, i + 2
                while j < len(texto) and prof:
                    if texto[j] == "(":
                        prof += 1
                    elif texto[j] == ")":
                        prof -= 1
                    elif texto[j] == '"':
                        j += 1
                        while j < len(texto) and texto[j] != '"':
                            j += 2 if texto[j] == "\\" else 1
                    j += 1
                partes.append("%@")
                i = j
                continue
            partes.append(texto[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(partes), i + 1
        partes.append(c)
        i += 1
    raise ValueError("literal sem fechamento")


IDENTIFICADOR = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*$")


def _quem_abriu(fonte, ate):
    """Nome da funcao cujo parentese ainda esta aberto em `ate`, ou None.

    Percorre para tras contando parenteses. Nao entende strings nem
    comentarios com precisao cirurgica; erra para o lado de LIBERAR, porque
    um falso negativo aqui custa uma frase escapando, e um falso positivo
    custa o portao inteiro virar ruido e ser desligado.
    """
    profundidade = 0
    i = ate - 1
    limite = max(0, ate - 4000)
    while i >= limite:
        c = fonte[i]
        if c == ")":
            profundidade += 1
        elif c == "(":
            if profundidade == 0:
                achado = IDENTIFICADOR.search(fonte[max(0, i - 60):i])
                return achado.group(1) if achado else None
            profundidade -= 1
        elif c in "{};":
            return None
        i -= 1
    return None


def eh_prosa_de_tela(conteudo):
    nucleo = FORMATO.sub("", conteudo).strip()
    if len(nucleo) < 6 or " " not in nucleo:
        return False
    if not re.match(r"^[A-Za-z]", nucleo):
        return False
    # snake_case ou identificador com underscore nao e frase
    if "_" in nucleo and nucleo.islower():
        return False
    return True


def varrer():
    achados = []
    for pasta, _dirs, nomes in os.walk(FONTES):
        for nome in sorted(nomes):
            if not nome.endswith(".swift"):
                continue
            caminho = os.path.join(pasta, nome)
            with open(caminho, encoding="utf-8") as f:
                fonte = f.read()
            posicao = 0
            while True:
                i = fonte.find('"', posicao)
                if i < 0:
                    break
                inicio_linha = fonte.rfind("\n", 0, i) + 1
                fim = fonte.find("\n", i)
                linha = fonte[inicio_linha:fim if fim > 0 else len(fonte)]
                try:
                    conteudo, depois = fatiar(fonte, i + 1)
                except ValueError:
                    posicao = i + 1
                    continue
                posicao = depois
                prefixo = fonte[inicio_linha:i]
                if linha.strip().startswith(("//", "///")) or "//" in prefixo:
                    continue
                if not eh_prosa_de_tela(conteudo):
                    continue
                if LOCALIZA.search(prefixo) or ENTRADA_DE_MAPA.search(prefixo):
                    continue
                # A chamada que localiza pode estar em OUTRA linha:
                #
                #     ContentUnavailableView(
                #         "No matching clothes",
                #
                # Olhar so o prefixo da linha acusaria isso como prosa crua. A
                # busca abaixo volta ate o parentese aberto que ainda nao
                # fechou e pergunta quem o abriu -- que e a pergunta certa.
                if _quem_abriu(fonte, inicio_linha) in ABREM_LOCALIZADO:
                    continue
                achados.append({
                    "arquivo": os.path.relpath(caminho, RAIZ),
                    "linha": fonte[:i].count("\n") + 1,
                    "texto": conteudo,
                })
    return achados


def permitidas():
    if not os.path.exists(ALLOWLIST):
        return {}
    with open(ALLOWLIST, encoding="utf-8") as f:
        return json.load(f)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    grupo = p.add_mutually_exclusive_group(required=True)
    grupo.add_argument("--conferir", action="store_true")
    grupo.add_argument("--listar", action="store_true")
    args = p.parse_args()

    liberadas = permitidas()
    achados = varrer()
    novos = [a for a in achados if a["texto"] not in liberadas]

    print("prosa fora de traducao :", len(achados))
    print("liberada na allowlist  :", len(achados) - len(novos))
    print("pendente               :", len(novos))
    for a in novos:
        print("  {}:{}  {}".format(a["arquivo"], a["linha"], a["texto"][:90]))
    if args.listar:
        return 0
    return 1 if novos else 0


if __name__ == "__main__":
    sys.exit(main())
