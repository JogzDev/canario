"""Sonda de datacenter (condicao 2.2 das instrucoes de 24/07).

Os testes da F1 rodaram do IP residencial do JP. O coletor vai rodar de IP de
datacenter do GitHub Actions, que CDNs barram com mais frequencia. Esta sonda
NAO coleta: so bate em 2-3 dominios e no Supabase e relata os codigos de
resposta, para decidir se da para confiar no agendamento.

Se houver bloqueio, o resultado deixa isso explicito e o coletor NAO deve ser
agendado antes de o JP ver. Escreve SONDA_ACTIONS.md (commitado de volta pelo
workflow) para o resultado voltar sem depender de ler log de Actions.
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teste_30s import buscar  # noqa: E402
import supabase_rest  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA = os.path.join(RAIZ, "SONDA_ACTIONS.md")

# Amostra: as duas plataformas, com as DUAS Shopify (Amaro e PatBo) para
# distinguir bloqueio de plataforma de 429 transitorio de uma loja so.
ALVOS = [
    ("Cantao", "www.cantao.com.br", "vtex"),
    ("C&A", "www.cea.com.br", "vtex"),
    ("Amaro", "amaro.com", "shopify"),
    ("PatBo", "www.patbo.com.br", "shopify"),
]

CAMINHO = {
    "vtex": "/api/catalog_system/pub/products/search/vestido",
    "shopify": "/products.json?limit=5",
}

ESPERAS = [0, 8, 20]  # backoff entre tentativas: distingue transitorio de duro


def sondar_dominio(marca, dominio, plataforma):
    url = "https://{}{}".format(dominio, CAMINHO[plataforma])
    tentativas = []
    codigo = corpo = None
    cab = {}
    for i, espera in enumerate(ESPERAS):
        if espera:
            time.sleep(espera)
        codigo, corpo, _, cab = buscar(url, dominio)
        tentativas.append(codigo)
        if codigo not in (403, 429, None):
            break  # respondeu: nao adianta insistir

    ok_json = False
    total = ""
    try:
        dados = json.loads(corpo) if corpo else None
        if plataforma == "vtex":
            ok_json = isinstance(dados, list) and bool(dados)
            recurso = cab.get("resources") or cab.get("Resources") or ""
            if "/" in recurso:
                total = recurso.split("/")[-1]
        else:
            ok_json = isinstance(dados, dict) and isinstance(dados.get("products"), list)
    except ValueError:
        ok_json = False
    bloqueado = codigo in (403, 429) or codigo is None
    return {
        "marca": marca, "dominio": dominio, "plataforma": plataforma,
        "http": codigo, "tentativas": tentativas, "json_ok": ok_json,
        "total_catalogo": total, "bloqueado": bloqueado,
    }


def sondar_supabase():
    if not supabase_rest.configurado():
        return {"ok": False, "detalhe": "SUPABASE_URL/SUPABASE_SECRET_KEY ausentes"}
    try:
        n = supabase_rest.contar("marcas")
        return {"ok": True, "detalhe": "conectado; tabela marcas tem {} linhas".format(n)}
    except Exception as e:
        return {"ok": False, "detalhe": "{}: {}".format(type(e).__name__, str(e)[:200])}


def main():
    agora = datetime.now(timezone.utc)
    dominios = [sondar_dominio(*a) for a in ALVOS]
    supa = sondar_supabase()

    def bloqueio_plataforma(plat):
        ds = [d for d in dominios if d["plataforma"] == plat]
        return ds and all(d["bloqueado"] for d in ds)

    vtex_bloqueada = bloqueio_plataforma("vtex")
    shopify_bloqueada = bloqueio_plataforma("shopify")

    if vtex_bloqueada:
        veredito = "BLOQUEIO EM VTEX — espinha dorsal do painel barrada; parar e avisar o JP"
    elif shopify_bloqueada:
        veredito = ("SHOPIFY BARRA O DATACENTER — VTEX (12 marcas) livre; as 2 Shopify "
                    "(Amaro, PatBo) precisam de decisao do JP antes de agendar")
    elif any(d["bloqueado"] for d in dominios):
        veredito = "BLOQUEIO PARCIAL — ver tabela; decidir antes de agendar"
    else:
        veredito = "SEM BLOQUEIO — datacenter do Actions responde nas duas plataformas; seguro agendar"

    linhas = []
    linhas.append("# Sonda do Actions — condicao 2.2\n")
    linhas.append("**Executado (UTC):** {}  \n".format(agora.isoformat()))
    linhas.append("**IP de origem:** datacenter do GitHub Actions (não o residencial do JP)\n")
    linhas.append("\n## Veredito: {}\n".format(veredito))
    linhas.append("\n| Marca | Domínio | Plataforma | Tentativas HTTP | JSON ok | Catálogo | Bloqueado |")
    linhas.append("|---|---|---|---|---|---|---|")
    for d in dominios:
        tent = " → ".join(str(t) for t in d["tentativas"])
        linhas.append("| {} | {} | {} | {} | {} | {} | {} |".format(
            d["marca"], d["dominio"], d["plataforma"], tent,
            "sim" if d["json_ok"] else "não", d["total_catalogo"] or "—",
            "SIM" if d["bloqueado"] else "não"))
    linhas.append("\n## Supabase\n")
    linhas.append("- {}: {}\n".format("OK" if supa["ok"] else "FALHOU", supa["detalhe"]))
    linhas.append("\n---\n")
    linhas.append("Gerado por `coletor/sonda_actions.py`. Não coleta dado; só diagnostica.\n")

    with open(SAIDA, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))

    # Espelha no stdout do Actions para leitura rapida no log.
    print("\n".join(linhas))
    print("\nRESUMO_JSON:", json.dumps(
        {"vtex_bloqueada": vtex_bloqueada, "shopify_bloqueada": shopify_bloqueada,
         "bloqueio_parcial": any(d["bloqueado"] for d in dominios),
         "supabase_ok": supa["ok"],
         "http": {d["marca"]: d["http"] for d in dominios}}, ensure_ascii=False))
    # Nunca falha o job: um exit!=0 abortaria o commit do resultado.
    return 0


if __name__ == "__main__":
    sys.exit(main())
