"""Gera o mapa de categorias por marca (B5).

O documento manda "varrer o catalogo do segmento v1" (secao 17) mas nada define
como a arvore de categorias de cada site vira `feminino_casual_br`. Este script
le a arvore de cada marca aprovada no teste dos 30 segundos e propoe, categoria
por categoria, se ela entra no segmento.

Tudo sai com status=proposto: quem aprova e o JP (regra inviolavel 4).

Reaproveita os utilitarios de rede do teste_30s para nao duplicar a etiqueta de
coleta da regra 7 (1 req/s por dominio, User-Agent identificavel, robots.txt).
"""

import csv
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar, robots_permite  # noqa: E402
from matcher import normalizar, compilar_lista, casa_algum  # noqa: E402

_robots_cache = {}


def permitido(dominio, caminho):
    """Checa robots.txt uma vez por dominio (regra 7)."""
    chave = (dominio, caminho.split("?")[0])
    if chave not in _robots_cache:
        _robots_cache[chave] = robots_permite(dominio, chave[1])[0]
    return _robots_cache[chave]

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAINEL = os.path.join(RAIZ, "anexos", "painel_marcas.csv")
SAIDA = os.path.join(RAIZ, "anexos", "mapa_categorias.csv")

PROFUNDIDADE = 2  # departamento > categoria: a granularidade que da para revisar a mao

# Regras de exclusao, aplicadas ao caminho inteiro em minusculas e sem acento.
# A ordem importa: a primeira que casar decide, e o motivo vai para o CSV.
#
# Casamento e por PALAVRA INTEIRA. O sufixo `*` libera o final da palavra, e so
# deve ser usado onde a familia inteira e realmente excluivel: `masculin*` pega
# masculino e masculina, mas `casa` precisa ser exato para nao levar `casaco`
# junto, e `bota` precisa ser exato para nao levar `botao`.
EXCLUSOES = [
    ("outro publico", ["masculin*", "infant*", "kids", "menino*", "menina*",
                       "bebe*", "baby", "teen", "unissex", "homem", "homens"]),
    ("nao e vestuario", ["calcado*", "sapato*", "tenis", "sandalia*", "bota",
                         "botas", "bolsa", "bolsas", "acessorio*", "joia",
                         "joias", "bijuteria*", "oculos", "cinto", "cintos",
                         "chapeu*", "perfume*", "beleza", "casa",
                         "decoracao", "pet", "livro*"]),
    ("outro segmento", ["praia", "biquini*", "maio", "maios", "beachwear",
                        "fitness", "esporte*", "academia", "lingerie",
                        "pijama*", "moda intima", "sleepwear", "underwear"]),
    ("nao e categoria de produto", ["sale", "outlet", "promocao", "promocoes",
                                    "black", "novidade*", "lancamento*",
                                    "colecao", "colecoes", "presente",
                                    "presentes", "gift*", "todos", "ver tudo",
                                    "campanha*", "editorial", "blog"]),
]


# Compila os gatilhos uma vez, com o matcher compartilhado (correspondencia
# exata por palavra, prefixo livre so no `*`). Mesmo motor dos outros dois
# matchers do sistema.
_EXCLUSOES_COMPILADAS = [(motivo, compilar_lista(gatilhos))
                         for motivo, gatilhos in EXCLUSOES]


def classificar(caminho):
    """Propoe incluir/excluir para um caminho de categoria."""
    alvo = normalizar(caminho)
    for motivo, regexes in _EXCLUSOES_COMPILADAS:
        if casa_algum(alvo, regexes):
            return "nao", "", motivo
    return "sim", "feminino_casual_br", "vestuario feminino: proposto para o segmento v1"


def achatar_vtex(nos, prefixo="", nivel=1, saida=None):
    if saida is None:
        saida = []
    for no in nos or []:
        nome = no.get("name") or ""
        caminho = "{} > {}".format(prefixo, nome) if prefixo else nome
        saida.append({"caminho": caminho, "id_categoria": str(no.get("id") or ""),
                      "nivel": nivel})
        if nivel < PROFUNDIDADE:
            achatar_vtex(no.get("children"), caminho, nivel + 1, saida)
    return saida


def buscar_paciente(url, dominio, tentativas=4):
    """Como `buscar`, mas recua diante de 429.

    As lojas VTEX ficam atras da mesma infraestrutura, entao varios dominios em
    paralelo chegam la como um unico cliente. O recuo exponencial e a resposta
    correta a um 429: o servidor esta pedindo espaco, e a regra 7 e sobre nao
    incomodar quem esta servindo o dado de graca.
    """
    espera = 3.0
    for tentativa in range(tentativas):
        codigo, corpo, url_final, cabecalhos = buscar(url, dominio)
        if codigo != 429:
            return codigo, corpo, url_final, cabecalhos
        if tentativa < tentativas - 1:
            time.sleep(espera)
            espera *= 2
    return 429, "", url, {}


def categorias_vtex(dominio):
    caminho = "/api/catalog_system/pub/category/tree/{}".format(PROFUNDIDADE)
    if not permitido(dominio, caminho):
        return [], "robots.txt proibe a arvore de categorias"
    url = "https://{}{}".format(dominio, caminho)
    codigo, corpo, _, _ = buscar_paciente(url, dominio)
    if codigo not in (200, 206):
        return [], "arvore vtex http {}".format(codigo)
    try:
        arvore = json.loads(corpo)
    except ValueError:
        return [], "arvore vtex nao-json"
    if not isinstance(arvore, list):
        return [], "arvore vtex em formato inesperado"
    return achatar_vtex(arvore), ""


def categorias_shopify(dominio):
    if not permitido(dominio, "/collections.json"):
        return [], "robots.txt proibe collections.json"
    url = "https://{}/collections.json?limit=250".format(dominio)
    codigo, corpo, _, _ = buscar_paciente(url, dominio)
    if codigo not in (200, 206):
        return [], "collections http {}".format(codigo)
    try:
        dados = json.loads(corpo)
    except ValueError:
        return [], "collections nao-json"
    colecoes = dados.get("collections") if isinstance(dados, dict) else None
    if not isinstance(colecoes, list):
        return [], "collections sem lista"
    return ([{"caminho": c.get("title") or "", "id_categoria": c.get("handle") or "",
              "nivel": 1} for c in colecoes], "")


def processar(linha):
    marca, dominio, plataforma = linha["marca"], linha["dominio"], linha["status_teste"]
    if plataforma == "vtex":
        cats, erro = categorias_vtex(dominio)
    elif plataforma == "shopify":
        cats, erro = categorias_shopify(dominio)
    else:
        return []

    if erro:
        print("  {}: {}".format(marca, erro), file=sys.stderr)
        return []

    linhas = []
    for c in cats:
        if not c["caminho"].strip():
            continue
        incluir, segmento, motivo = classificar(c["caminho"])
        linhas.append({
            "marca": marca, "plataforma": plataforma,
            "caminho_no_site": c["caminho"], "id_categoria": c["id_categoria"],
            "nivel": c["nivel"], "segmento": segmento, "incluir": incluir,
            "status": "proposto", "motivo": motivo,
        })
    print("  {}: {} categorias".format(marca, len(linhas)), file=sys.stderr)
    return linhas


def main():
    painel = list(csv.DictReader(open(PAINEL, encoding="utf-8")))
    aprovadas = [l for l in painel if l["status_teste"] in ("vtex", "shopify")]
    print("Marcas aprovadas no teste dos 30 segundos: {}".format(len(aprovadas)),
          file=sys.stderr)

    # Serial, de proposito. O 429 da VTEX e por IP, nao por dominio: as lojas
    # ficam atras da mesma infraestrutura, entao paralelizar so gera recusa.
    blocos = []
    for i, linha in enumerate(aprovadas):
        blocos.append(processar(linha))
        if i < len(aprovadas) - 1:
            time.sleep(4.0)

    linhas = [x for bloco in blocos for x in bloco]
    linhas.sort(key=lambda r: (r["marca"], r["nivel"], r["caminho_no_site"]))

    campos = ["marca", "plataforma", "caminho_no_site", "id_categoria", "nivel",
              "segmento", "incluir", "status", "motivo"]
    with open(SAIDA, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        w.writerows(linhas)

    incluidas = sum(1 for r in linhas if r["incluir"] == "sim")
    print("\n{} categorias no total, {} propostas para feminino_casual_br".format(
        len(linhas), incluidas), file=sys.stderr)


if __name__ == "__main__":
    main()
