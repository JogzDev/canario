"""Teste da lista negra de vocabulario (§6, A8, C6).

O §6 e explicito: "O agente deve implementar um teste automatizado que varre os
textos da interface contra esta lista." Este e esse teste. Ele existe ANTES da
interface de proposito -- quando as telas comecarem, o teste ja esta de pe e
qualquer texto novo passa por ele.

Tres blocos de proibicao:

1. §6, previsao de venda. E a regra inviolavel 1 em forma de palavra: nada pode
   afirmar ou sugerir quanto uma peca vai vender.
2. A8, vocabulario interno. "Efeito Ozempic", "provao" e apelidos de regra nunca
   viram produto. Referencia a medicamento, peso corporal ou condicao de saude e
   proibida em qualquer texto -- o achado da curva de tamanhos se descreve como
   "deslocamento da curva de tamanhos".
3. §27, palavras que sugerem cultivo ou espera ("atualizada hoje").

E uma allowlist, do C6. O principio, em uma linha:

    PASSADO OBSERVADO E PERMITIDO; FUTURO E PRESCRICAO SAO PROIBIDOS.

"% vendido a preco cheio" e fato passado sobre a colecao do proprio usuario, e
precisa aparecer na tela (§30, §31). "vai vender" continua proibido.

Rodar: python3 coletor/teste_vocabulario.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import compilar_lista, normalizar  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Onde os textos de interface vao morar. Varre o que existir; nao falha por
# pasta ainda vazia, porque o app comeca depois deste teste.
# `.xcstrings` entrou em 05/09, com a A53.
#
# Ate ali o texto de interface morava em `.swift`, e varrer `.swift` bastava.
# Com a traducao, metade das frases da tela passou a existir SO dentro do
# catalogo -- e em dois idiomas. O portao continuaria verde varrendo o codigo
# enquanto uma frase proibida em portugues viajava intacta ate o usuario, que e
# exatamente o buraco que a §6 manda nao ter.
ALVOS = [
    ("app", (".swift", ".strings", ".xcstrings")),
    ("coletor", (".py",)),
]

# Artefato de compilacao nao e codigo-fonte: varrer isso so gera ruido e ensina
# a ignorar o teste.
PASTAS_IGNORADAS = {".build", "build", "DerivedData", ".git"}

# --- Bloco 1: §6, previsao de venda -----------------------------------------
PROIBIDO_PREVISAO = [
    "prever", "previsao", "previsoes", "vai vender", "vao vender",
    "venda futura", "vendas futuras", "chance de sucesso", "probabilidade",
    "potencial de venda", "recomendamos produzir", "deve produzir",
    "sucesso da peca", "quanto vai vender",
]

# --- Bloco 2: A8, vocabulario interno ---------------------------------------
PROIBIDO_INTERNO = [
    "ozempic", "emagrecedor", "emagrecimento", "obesidade", "peso corporal",
    "provao", "canario",   # o codinome nunca aparece em frase de interface (§0)
]

# --- Bloco 3: §27, sugestao de cultivo/espera -------------------------------
PROIBIDO_CULTIVO = [
    "atualizada hoje", "atualizado hoje", "aguarde os dados",
    "em breve teremos",
]

# Cada bloco declara ONDE vale. O §6 fala de "texto de interface, template ou
# relatorio" -- codigo de coletor nao e interface, e tratar tudo igual gera
# falso positivo que ensina a ignorar o teste, que e como um teste morre.
#
# `canario` e o caso mais claro: o §0 manda usar o codinome como TOKEN ISOLADO
# (nome de projeto, diretorio, bundle id) e proibe so embutir em frase de
# interface. "CANARIO.md secao 17" numa docstring e uso correto.
BLOCOS = [
    ("previsao de venda (§6 / regra 1)", PROIBIDO_PREVISAO, ("app", "coletor")),
    ("vocabulario interno (A8)", PROIBIDO_INTERNO, ("app",)),
    ("sugestao de cultivo (§27)", PROIBIDO_CULTIVO, ("app",)),
]

# --- Allowlist (C6) ---------------------------------------------------------
# Curta, explicita e auditavel de proposito: cada linha aqui e uma excecao a um
# Won't Have permanente, e precisa se justificar. Duas familias:
#
# 1. PASSADO OBSERVADO. Fato ja acontecido sobre a colecao do proprio usuario.
#    "% vendido a preco cheio" precisa aparecer na tela (§30, §31) e nao e
#    previsao de coisa nenhuma.
#
# 2. NEGACAO DA AFIRMACAO PROIBIDA. Descoberto em 30/07, quando o teste barrou o
#    disclaimer que a propria §27 exige em texto: "Nao e previsao de venda".
#    Negar a promessa e o OPOSTO de faze-la, e e justamente onde o documento
#    quer a palavra aparecendo. Sem esta familia, o teste proibiria a frase que
#    protege a regra inviolavel 1.
PERMITIDO = [
    # (1) passado observado
    "% vendido a preco cheio",
    "percentual vendido a preco cheio",
    "pct_vendido_preco_cheio",
    "vendido sem remarcacao",
    # (2) negacao explicita
    "nao e previsao de venda",
    "nao preve",
    "nao prevemos",
    "sem previsao de venda",
    "nunca preve",
    # A traducao pt-BR da A53 escreve as mesmas negacoes que o ingles ja
    # escrevia. Elas entram aqui pelo mesmo motivo da familia (2): negar a
    # promessa e o oposto de faze-la, e e onde o documento quer a palavra.
    "nao e previsao",
    "nem garantia de venda",
    "nao previsoes",
]


def frases_do_catalogo(caminho):
    """Todas as traducoes de um String Catalog, em todos os idiomas.

    Le o JSON em vez de casar aspas: no `.xcstrings` a chave e o valor sao
    ambos strings JSON, e a varredura generica confundiria nome de campo com
    texto de tela. Aqui sai exatamente o que o usuario le -- a chave, que e o
    ingles-fonte, e cada `stringUnit` traduzido.
    """
    import json
    try:
        catalogo = json.load(open(caminho, encoding="utf-8"))
    except (IOError, ValueError, UnicodeDecodeError):
        return []
    saida = []
    for chave, entrada in (catalogo.get("strings") or {}).items():
        if len(chave.strip()) > 3:
            saida.append(chave)
        for local in (entrada.get("localizations") or {}).values():
            valor = (local.get("stringUnit") or {}).get("value", "")
            if len(valor.strip()) > 3:
                saida.append(valor)
    return saida


def linhas_de_texto(caminho):
    """Extrai literais de string de um arquivo de codigo."""
    if caminho.endswith(".xcstrings"):
        return frases_do_catalogo(caminho)
    try:
        conteudo = open(caminho, encoding="utf-8").read()
    except (IOError, UnicodeDecodeError):
        return []
    # Strings entre aspas simples ou duplas, incluindo as triplas.
    achados = re.findall(r'"""(.*?)"""|\'\'\'(.*?)\'\'\'|"([^"\n]*)"|\'([^\'\n]*)\'',
                         conteudo, re.S)
    saida = []
    for grupo in achados:
        for t in grupo:
            if t and len(t.strip()) > 3:
                saida.append(t)
    return saida


def esta_permitido(trecho):
    alvo = normalizar(trecho)
    return any(normalizar(p) in alvo for p in PERMITIDO)


def e_token_isolado(trecho):
    """True quando o trecho e uma palavra so, sem frase em volta.

    O §0 permite o codinome como TOKEN (nome de projeto, de target, bundle id)
    e proibe so embutir em FRASE de interface: "para a troca pelo nome
    definitivo ser uma operacao unica de find-and-replace". `Package.swift`
    usando "Canario" como nome de modulo e uso correto, e marcar isso como
    violacao ensinaria a ignorar o teste.
    """
    return len(trecho.strip().split()) == 1


def main():
    compilados = [(nome, compilar_lista(termos), escopo)
                  for nome, termos, escopo in BLOCOS]
    falhas = []
    arquivos = 0

    for pasta, extensoes in ALVOS:
        raiz = os.path.join(RAIZ, pasta)
        if not os.path.isdir(raiz):
            continue
        for atual, dirs, nomes in os.walk(raiz):
            dirs[:] = [d for d in dirs if d not in PASTAS_IGNORADAS]
            for nome in nomes:
                if not nome.endswith(extensoes):
                    continue
                # O proprio teste contem as palavras proibidas, por definicao.
                if nome == os.path.basename(__file__):
                    continue
                # SUITE DE TESTES NAO E INTERFACE.
                #
                # A §6 fala de "textos da interface", e um teste que garante a
                # ausencia de uma palavra precisa poder nomea-la. O
                # `SimilaresTests` afirma que o paragrafo da §29 nao contem
                # "vai vender", "probabilidade" nem "previsao" -- e por isso as
                # tres aparecem no arquivo. Barrar isso trocaria um teste que
                # protege a regra 1 por um que atrapalha.
                if (os.sep + "Testes" + os.sep) in (atual + os.sep):
                    continue
                caminho = os.path.join(atual, nome)
                arquivos += 1
                for trecho in linhas_de_texto(caminho):
                    if esta_permitido(trecho):
                        continue
                    for bloco, regexes, escopo in compilados:
                        if pasta not in escopo:
                            continue
                        # `canario` como token isolado e permitido (§0).
                        if bloco.startswith("vocabulario interno") and e_token_isolado(trecho):
                            continue
                        alvo = normalizar(trecho)
                        for r in regexes:
                            if r.search(alvo):
                                falhas.append((
                                    os.path.relpath(caminho, RAIZ), bloco,
                                    r.pattern, trecho.strip()[:70]))
                                break

    for arq, bloco, padrao, trecho in falhas:
        print("PROIBIDO em {}\n   bloco: {}\n   casou: {}\n   texto: {!r}".format(
            arq, bloco, padrao, trecho))

    print("{} arquivos varridos, {} ocorrências proibidas".format(
        arquivos, len(falhas)))
    if not falhas:
        print("Princípio em vigor: passado observado é permitido; "
              "futuro e prescrição são proibidos.")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
