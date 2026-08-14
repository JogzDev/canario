#!/usr/bin/env python3
"""Audita somente os links que as superfícies públicas do app exibem hoje.

Consulta os RPCs públicos com a mesma publishable key do binário e visita cada
URL no domínio da loja com User-Agent identificável, no máximo 1 req/s por
domínio e recuo real em 429. Não corrige nem contorna bloqueios; registra o que
um usuário receberia ao tocar no card.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import socket
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request


AGENTE = "DataDrobeLinkAudit/1.0 (+https://github.com/JogzDev/canario)"
PARES = [
    ["vestido", "geometrica"], ["camisa", "listra"],
    ["blusa_top", "preto"], ["casaco_jaqueta", "cinza"],
    ["calca", "amarelo_laranja"], ["saia", "floral"],
    ["short", "azul"], ["macacao", "liso"],
]
SINAIS_DE_ERRO = (
    "página não encontrada", "pagina nao encontrada", "page not found",
    "produto não encontrado", "produto nao encontrado", "busca não foi encontrada",
    "busca nao foi encontrada", "404 not found", "desculpe, não encontramos",
    "desculpe, nao encontramos",
)
SINAIS_DE_ESGOTADO = (
    "produto esgotado", "produto indisponível", "produto indisponivel",
    "fora de estoque", "out of stock", "sold out",
)


def configuracao(caminho):
    valores = {}
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        if "=" not in linha or linha.lstrip().startswith("//"):
            continue
        chave, valor = linha.split("=", 1)
        valores[chave.strip()] = valor.strip()
    url = valores.get("SUPABASE_URL", "")
    if url and not url.startswith("http"):
        url = "https://" + url
    chave = valores.get("SUPABASE_PUBLISHABLE_KEY", "")
    if not url or not chave:
        raise ValueError("Config.xcconfig incompleto")
    return url.rstrip("/"), chave


def rpc(base, chave, nome, argumentos):
    for tentativa in range(2):
        req = urllib.request.Request(
            base + "/rest/v1/rpc/" + nome,
            data=json.dumps(argumentos).encode("utf-8"),
            headers={
                "apikey": chave,
                "Authorization": "Bearer " + chave,
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": AGENTE,
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resposta:
                return json.load(resposta)
        except urllib.error.HTTPError as erro:
            if erro.code >= 500 and tentativa == 0:
                time.sleep(0.4)
                continue
            raise
    raise RuntimeError("RPC sem resposta")


def sem_acentos(texto):
    return "".join(c for c in unicodedata.normalize("NFKD", texto or "")
                   if not unicodedata.combining(c)).lower()


def palavras_relevantes(texto):
    ignorar = {"de", "da", "do", "das", "dos", "com", "e", "em", "para",
               "the", "a", "an", "off", "por", "feminino", "feminina"}
    return {p for p in re.findall(r"[a-z0-9]+", sem_acentos(texto))
            if len(p) >= 3 and p not in ignorar}


class Visitante:
    def __init__(self):
        self.ultima = defaultdict(float)

    def visitar(self, url, imagem=False):
        host = urllib.parse.urlparse(url).netloc.lower()
        espera = 1.0 - (time.monotonic() - self.ultima[host])
        if espera > 0:
            time.sleep(espera)
        for tentativa in range(3):
            req = urllib.request.Request(
                url,
                headers={"User-Agent": AGENTE, "Accept": "image/*" if imagem else "text/html,*/*;q=0.8"},
                method="GET",
            )
            try:
                self.ultima[host] = time.monotonic()
                with urllib.request.urlopen(req, timeout=20) as resposta:
                    corpo = resposta.read(131_072 if not imagem else 4_096)
                    return (resposta.status, resposta.geturl(),
                            resposta.headers.get("Content-Type", ""), corpo)
            except urllib.error.HTTPError as erro:
                self.ultima[host] = time.monotonic()
                if erro.code == 429 and tentativa < 2:
                    time.sleep(min(30, 2 ** (tentativa + 1)))
                    continue
                return erro.code, erro.geturl(), erro.headers.get("Content-Type", ""), erro.read(16_384)
            except (urllib.error.URLError, TimeoutError, socket.timeout) as erro:
                return 0, url, "", str(getattr(erro, "reason", erro)).encode("utf-8")
        return 429, url, "", b""


def auditar_item(visitante, item):
    status, final, tipo, corpo = visitante.visitar(item["url"], item["tipo"] == "imagem")
    texto = sem_acentos(corpo.decode("utf-8", errors="ignore"))
    flags = []
    if not 200 <= status < 400:
        flags.append("http_{}".format(status or "rede"))
    if item["tipo"] == "imagem":
        if status and not tipo.lower().startswith("image/"):
            flags.append("nao_e_imagem")
    else:
        if urllib.parse.urlparse(final).path.strip("/") == "":
            flags.append("caiu_na_home")
        if any(sinal in texto for sinal in SINAIS_DE_ERRO):
            flags.append("pagina_de_erro")
        if any(sinal in texto for sinal in SINAIS_DE_ESGOTADO):
            flags.append("esgotado_na_loja")
        esperadas = palavras_relevantes(item.get("titulo"))
        presentes = sum(p in texto for p in esperadas)
        if esperadas and texto and presentes / len(esperadas) < 0.25:
            flags.append("titulo_sem_confirmacao")
    return dict(item, http_status=status, final_url=final,
                content_type=tipo.split(";", 1)[0], flags=flags,
                ok=not flags)


def coletar(base, chave):
    itens = []
    erros = []
    for tipo in ("reposicao", "remarcacao"):
        try:
            eventos = rpc(base, chave, "eventos_recentes",
                          {"tipo_evento": tipo, "limite": 20})
        except urllib.error.HTTPError as erro:
            erros.append({"tipo": "rpc", "origem": "evento_" + tipo,
                          "marca": None, "titulo": None, "url": "",
                          "http_status": erro.code, "final_url": "",
                          "content_type": "", "flags": ["rpc_http_{}".format(erro.code)],
                          "ok": False})
            continue
        for evento in eventos:
            origem = "evento_" + tipo
            if evento.get("url_da_peca"):
                itens.append({"tipo": "produto", "origem": origem,
                              "marca": evento.get("marca"), "titulo": evento.get("peca"),
                              "url": evento["url_da_peca"]})
            if evento.get("imagem"):
                itens.append({"tipo": "imagem", "origem": origem,
                              "marca": evento.get("marca"), "titulo": evento.get("peca"),
                              "url": evento["imagem"]})
    for termos in PARES:
        try:
            resposta = rpc(base, chave, "similares_da_peca",
                           {"termos": termos, "limite": 12})
        except urllib.error.HTTPError as erro:
            erros.append({"tipo": "rpc", "origem": "similar_" + "+".join(termos),
                          "marca": None, "titulo": None, "url": "",
                          "http_status": erro.code, "final_url": "",
                          "content_type": "", "flags": ["rpc_http_{}".format(erro.code)],
                          "ok": False})
            continue
        for peca in resposta.get("pecas", []):
            origem = "similar_" + "+".join(termos)
            if peca.get("url"):
                itens.append({"tipo": "produto", "origem": origem,
                              "marca": peca.get("marca"), "titulo": peca.get("titulo"),
                              "url": peca["url"]})
            if peca.get("imagem"):
                itens.append({"tipo": "imagem", "origem": origem,
                              "marca": peca.get("marca"), "titulo": peca.get("titulo"),
                              "url": peca["imagem"]})
    unicos = {}
    for item in itens:
        chave_item = (item["tipo"], item["url"])
        if chave_item not in unicos:
            unicos[chave_item] = item
    return list(unicos.values()), erros


def resumo_markdown(resultados):
    falhas = [r for r in resultados if not r["ok"]]
    linhas = [
        "# Auditoria dos links exibidos pelo app", "",
        "- URLs únicas testadas: **{}**".format(len(resultados)),
        "- Sem sinal técnico de problema: **{}**".format(len(resultados) - len(falhas)),
        "- Pedem revisão: **{}**".format(len(falhas)), "",
        "O teste segue redirects e verifica status, tipo de imagem, queda na home,",
        "página de erro/esgotado e presença mínima do título no HTML. Uma página",
        "renderizada só por JavaScript pode gerar `titulo_sem_confirmacao` sem estar quebrada.",
        "", "## Revisar", "",
        "| marca | superfície | tipo | status | sinais | URL final |",
        "|---|---|---|---:|---|---|",
    ]
    for r in falhas:
        final = r["final_url"].replace("|", "%7C")
        linhas.append("| {} | {} | {} | {} | {} | {} |".format(
            r.get("marca") or "—", r["origem"], r["tipo"], r["http_status"],
            ", ".join(r["flags"]), final))
    return "\n".join(linhas) + "\n"


def main():
    raiz = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=raiz / "Config.xcconfig")
    parser.add_argument("--json", type=Path, default=raiz / "anexos" / "auditoria_links_app.json")
    parser.add_argument("--jsonl", type=Path, default=raiz / "anexos" / "auditoria_links_app.jsonl")
    parser.add_argument("--resumo", type=Path, default=raiz / "AUDITORIA_LINKS_APP.md")
    args = parser.parse_args()
    base, chave = configuracao(args.config)
    itens, resultados = coletar(base, chave)
    ja_feitos = {}
    if args.jsonl.is_file():
        for linha in args.jsonl.read_text(encoding="utf-8").splitlines():
            try:
                anterior = json.loads(linha)
                ja_feitos[(anterior["tipo"], anterior["url"])] = anterior
            except (json.JSONDecodeError, KeyError):
                continue
    visitante = Visitante()
    for indice, item in enumerate(itens, 1):
        chave_item = (item["tipo"], item["url"])
        resultado = ja_feitos.get(chave_item)
        if resultado is None:
            resultado = auditar_item(visitante, item)
            args.jsonl.parent.mkdir(parents=True, exist_ok=True)
            with args.jsonl.open("a", encoding="utf-8") as arquivo:
                arquivo.write(json.dumps(resultado, ensure_ascii=False) + "\n")
                arquivo.flush()
        resultados.append(resultado)
        print("[{}/{}] {} {} {}".format(
            indice, len(itens), resultado["http_status"],
            resultado.get("marca") or "—", ",".join(resultado["flags"]) or "ok"),
            flush=True)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(resultados, ensure_ascii=False, indent=2) + "\n")
    args.resumo.write_text(resumo_markdown(resultados), encoding="utf-8")


if __name__ == "__main__":
    main()
