"""Correspondencia exata, compartilhada pelos tres matchers do sistema.

Existe por causa de um bug real (achado na F1): casar por substring exclui
"casaco" porque contem "casa", "botao" porque contem "bota", e casaria uma
peca "preta" com a silhueta "reta". A regra do projeto (item 4 das instrucoes
de 24/07) e: **correspondencia exata por padrao, prefixo livre apenas onde
declarado**, nos tres matchers -- mapa de categorias, titulo->termo (varejo) e
texto editorial.

Como declarar prefixo livre: sufixar o padrao com `*`.
  "masculin*"  casa masculino, masculina, masculinas
  "reta"       casa "saia reta"; NAO casa "preta" (esta e a regressao critica)
  "wide leg"   frase: casa as duas palavras em sequencia, com fronteira

A fronteira `\\b` do regex resolve o caso reta/preta sozinha: em "preta" nao ha
fronteira entre o "p" e o "reta", entao `\\breta\\b` nao casa. O `*` afrouxa
so o FIM da palavra, nunca o comeco -- o comeco e sempre ancorado.
"""

import re
import unicodedata


def normalizar(texto):
    """Minusculas, sem acento, espacos colapsados."""
    sem_acento = unicodedata.normalize("NFKD", texto or "")
    sem_acento = "".join(c for c in sem_acento if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", sem_acento.lower()).strip()


# Terminacoes que, em portugues, sao inequivocamente de ADJETIVO. So nelas vale
# trocar o genero: "canelado/canelada" e seguro, mas "linho/linha" nao seria --
# linho e tecido, linha e outra coisa. Por isso a troca nao e geral.
_ADJETIVO = re.compile(r"^(.*(?:ad|id|os|ic))[oa]$")


def _com_flexao(palavra):
    """Trecho de regex que cobre plural e, quando cabe, genero.

    Titulo de moda em portugues flexiona o tempo todo -- "Blusa Canelada",
    "Camisa Listrada", "Saia Rodada", e a categoria do site vem no plural
    ("Vestidos"). Sem isto o casamento perde esses produtos em silencio.

    O comeco continua ancorado em `\\b` no chamador, entao a regressao critica
    segue de pe: `reta` vira `retas?` e continua NAO casando `preta`.
    """
    m = _ADJETIVO.match(palavra)
    if m:
        return re.escape(m.group(1)) + "[oa]s?"
    return re.escape(palavra) + "s?"


def compilar(padrao, flexionar=True):
    """Compila um padrao (palavra ou frase) em regex de palavra inteira.

    Sufixo `*` libera o fim da ultima palavra (prefixo intencional). O comeco
    fica sempre ancorado em fronteira, para nunca casar no meio de outra
    palavra.

    `flexionar=False` desliga plural e genero: e o que o classificador de
    categorias usa, porque ali os nomes vem da arvore do site e ja sao exatos.
    """
    prefixo_livre = padrao.endswith("*")
    if prefixo_livre:
        padrao = padrao[:-1]
    tokens = normalizar(padrao).split()
    if not tokens:
        return None
    if prefixo_livre:
        corpo = r"\s+".join(re.escape(t) for t in tokens)
        return re.compile(r"\b" + corpo + r"\w*")
    if flexionar:
        # A flexao vale so na ULTIMA palavra: "wide leg" -> "wide legs?".
        partes = [re.escape(t) for t in tokens[:-1]] + [_com_flexao(tokens[-1])]
    else:
        partes = [re.escape(t) for t in tokens]
    return re.compile(r"\b" + r"\s+".join(partes) + r"\b")


def compilar_lista(padroes, flexionar=True):
    """Compila varios padroes de uma vez, descartando vazios."""
    return [c for c in (compilar(p, flexionar) for p in padroes
                        if p and p.strip()) if c]


def casa_algum(texto, regexes):
    """True se qualquer regex ja compilado casa no texto (normalizado uma vez)."""
    alvo = normalizar(texto)
    return any(r.search(alvo) for r in regexes)


def termos_que_casam(texto, termos_compilados):
    """Dado {chave: [regex, ...]}, devolve o conjunto de chaves que casam.

    E o coracao do matching titulo->termo (varejo) e texto->termo (editorial):
    contagem unica por termo (§11), porque o retorno e um set de chaves, nao de
    ocorrencias -- varias palavras-chave do mesmo termo contam uma vez so.
    """
    alvo = normalizar(texto)
    return {chave for chave, regexes in termos_compilados.items()
            if any(r.search(alvo) for r in regexes)}
