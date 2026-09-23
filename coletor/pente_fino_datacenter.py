"""Pente fino do datacenter (item 3.2 + investigacao Shopify, 24/07).

Re-testa do IP do Actions, com o ritmo correto (1 req/s) e um unico retry de
backoff longo, os 4 casos-limite:
  * Colcci, Centauro: deram 403 do IP residencial em janela de penalidade VTEX.
    Se limpo, 403 era penalidade; se persistir, e politica da loja (falha
    definitiva regra 7).
  * Amaro, PatBo: Shopify que deu 429. O 429 quase sempre e falta de intervalo,
    nao bloqueio de datacenter. Ritmo correto deve resolver.

NAO usa proxy nem headers alternativos: forcar entrada e contornar bloqueio, e a
regra 7 vale para Shopify igual (decisao do JP). So diagnostica e reporta
codigos; atualiza o painel so quando um 403 vira catalogo valido.
"""

import csv
import json
import os
import sys
import time
from datetime import date, datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar, robots_permite  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAINEL = os.path.join(RAIZ, "anexos", "painel_marcas.csv")
SAIDA = os.path.join(RAIZ, "PENTE_FINO_DATACENTER.md")

BACKOFF = 60
_ultima = [0.0]

ALVOS = [
    ("Colcci", "www.colcci.com.br", "vtex"),
    ("Centauro", "www.centauro.com.br", "vtex"),
    # A Amaro saiu da Shopify em 23/09/2026.
    ("Charry", "www.charry.com.br", "shopify"),
    ("PatBo", "www.patbo.com.br", "shopify"),
]
CAMINHO = {
    "vtex": "/api/catalog_system/pub/products/search/vestido",
    "shopify": "/products.json?limit=5",
}

# Marcas do grupo Azzas com AUTORIZACAO ESCRITA do cliente (registrada no
# changelog em 28/07). As duas sao VTEX mas fecharam a API no dominio proprio.
# Com autorizacao do dono da marca, o host da plataforma deixa de ser contorno
# e passa a ser acesso autorizado -- a distincia que separa isto de Colcci e
# Centauro, que continuam fora porque nao temos (nem pediremos) autorizacao.
AUTORIZADAS = [
    ("Maria Filo", ["mariafilo", "mariafilolojas", "grupomariafilo"]),
    ("Fabula", ["afabula", "fabula", "fabulakids"]),
]
HOST_PLATAFORMA = "{}.vtexcommercestable.com.br"


def testar_host_plataforma(marca, contas):
    """Descobre a conta VTEX de uma marca autorizada e testa o catalogo."""
    tentativas = []
    for conta in contas:
        dominio = HOST_PLATAFORMA.format(conta)
        url = "https://{}{}".format(dominio, CAMINHO["vtex"])
        _ritmo()
        codigo, corpo, _, _ = buscar(url, dominio)
        tentativas.append("{}:{}".format(conta, codigo))
        if codigo in (200, 206) and corpo:
            try:
                dados = json.loads(corpo)
            except ValueError:
                continue
            if isinstance(dados, list) and dados:
                return {"marca": marca, "dominio": dominio, "plataforma": "vtex",
                        "tentativas": tentativas, "http": codigo, "json_ok": True,
                        "veredito": "ABRIU pelo host da plataforma (conta '{}'), "
                                    "com autorizacao escrita do cliente".format(conta)}
    return {"marca": marca, "dominio": HOST_PLATAFORMA.format(contas[0]),
            "plataforma": "vtex", "tentativas": tentativas, "http": None,
            "json_ok": False,
            "veredito": "conta VTEX nao descoberta entre os candidatos testados"}


def _ritmo():
    espera = 1.0 - (time.monotonic() - _ultima[0])
    if espera > 0:
        time.sleep(espera)
    _ultima[0] = time.monotonic()


def testar(marca, dominio, plataforma):
    caminho = CAMINHO[plataforma]
    if not robots_permite(dominio, caminho)[0]:
        return {"marca": marca, "dominio": dominio, "plataforma": plataforma,
                "tentativas": ["robots"], "http": None, "json_ok": False,
                "veredito": "robots proibe"}
    url = "https://{}{}".format(dominio, caminho)
    tentativas = []
    codigo = corpo = None
    cab = {}
    for i in range(2):  # uma tentativa + um retry longo (decisao do JP)
        _ritmo()
        codigo, corpo, _, cab = buscar(url, dominio)
        tentativas.append(codigo)
        if codigo not in (403, 429, None):
            break
        if i == 0:
            time.sleep(BACKOFF)

    json_ok = False
    try:
        dados = json.loads(corpo) if corpo else None
        if plataforma == "vtex":
            json_ok = isinstance(dados, list) and bool(dados)
        else:
            json_ok = isinstance(dados, dict) and isinstance(dados.get("products"), list)
    except ValueError:
        json_ok = False

    if json_ok:
        veredito = "ABRIU — catalogo valido do datacenter"
    elif codigo in (403,):
        veredito = "403 confirmado do datacenter — politica da loja, falha definitiva (regra 7)"
    elif codigo in (429,):
        veredito = "429 persistiu apos backoff longo — aguarda; nao forcar (regra 7)"
    else:
        veredito = "http {} — sem catalogo".format(codigo)

    return {"marca": marca, "dominio": dominio, "plataforma": plataforma,
            "tentativas": tentativas, "http": codigo, "json_ok": json_ok,
            "veredito": veredito}


def atualizar_painel(resultados):
    """So promove: um 403 que virou catalogo valido vira status=vtex."""
    L = list(csv.DictReader(open(PAINEL, encoding="utf-8")))
    hoje = date.today().isoformat()
    promovidos = []
    for l in L:
        for r in resultados:
            if l["marca"] == r["marca"] and r["json_ok"] and l["status_teste"] == "falhou":
                l["status_teste"] = r["plataforma"]
                l["data_teste"] = hoje
                # O dominio precisa virar o que respondeu, senao o coletor
                # continuaria batendo no endereco que fechou no edge.
                l["dominio"] = r["dominio"]
                l["detalhe_teste"] = "pente fino {}: {}".format(hoje, r["veredito"])
                promovidos.append(r["marca"])
    if promovidos:
        campos = ["marca", "dominio", "segmento", "papel", "justificativa",
                  "status_teste", "data_teste", "detalhe_teste"]
        w = csv.DictWriter(open(PAINEL, "w", newline="", encoding="utf-8"),
                           fieldnames=campos, extrasaction="ignore")
        w.writeheader()
        w.writerows(L)
    return promovidos


def main():
    agora = datetime.now(timezone.utc)
    resultados = [testar(*a) for a in ALVOS]
    resultados += [testar_host_plataforma(marca, contas) for marca, contas in AUTORIZADAS]
    promovidos = atualizar_painel(resultados)

    linhas = ["# Pente fino do datacenter — 4 casos-limite\n",
              "**Executado (UTC):** {}\n".format(agora.isoformat()),
              "\n| Marca | Plataforma | Tentativas HTTP | JSON | Veredito |",
              "|---|---|---|---|---|"]
    for r in resultados:
        tent = " → ".join(str(t) for t in r["tentativas"])
        linhas.append("| {} | {} | {} | {} | {} |".format(
            r["marca"], r["plataforma"], tent, "sim" if r["json_ok"] else "não", r["veredito"]))
    if promovidos:
        linhas.append("\n**Promovidos a coletáveis:** {} (403 era penalidade, não política).\n".format(
            ", ".join(promovidos)))
    else:
        linhas.append("\n**Nenhuma promoção:** os vereditos acima são finais para esta temporada.\n")
    linhas.append("\nRegra 7: nenhum proxy nem header alternativo. Só diagnóstico honesto.\n")

    with open(SAIDA, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))
    print("\n".join(linhas))
    print("\nRESUMO_JSON:", json.dumps(
        {r["marca"]: {"http": r["http"], "json_ok": r["json_ok"]} for r in resultados},
        ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
