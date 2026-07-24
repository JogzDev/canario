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


def compilar(padrao):
    """Compila um padrao (palavra ou frase) em regex de palavra inteira.

    Sufixo `*` libera o fim da ultima palavra (prefixo intencional). O comeco
    fica sempre ancorado em fronteira, para nunca casar no meio de outra
    palavra.
    """
    prefixo_livre = padrao.endswith("*")
    if prefixo_livre:
        padrao = padrao[:-1]
    tokens = normalizar(padrao).split()
    if not tokens:
        return None
    corpo = r"\s+".join(re.escape(t) for t in tokens)
    if prefixo_livre:
        return re.compile(r"\b" + corpo + r"\w*")
    return re.compile(r"\b" + corpo + r"\b")


def compilar_lista(padroes):
    """Compila varios padroes de uma vez, descartando vazios."""
    return [c for c in (compilar(p) for p in padroes if p and p.strip()) if c]


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
