#!/usr/bin/env python3
"""Testa a rota paga de visão de ponta a ponta, como o app faz.

Sobe UMA imagem para a Edge Function e imprime o contrato devolvido. Custa
cerca de US$ 0,0007. A chave da OpenAI não passa por aqui: ela vive só nos
secrets da função, do lado do servidor.

Uso:
    python3 ferramentas/testar_edge_luna.py <imagem.jpg> [--alvo "o short laranja"]
    python3 ferramentas/testar_edge_luna.py --so-contrato   # sem imagem, sem custo
"""

import argparse
import base64
import json
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
ESTADOS = {
    "BOOT_ERROR": "a função NÃO sobe; o artefato publicado está quebrado",
    "analysis_not_configured": "sobe, mas falta OPENAI_API_KEY ou AI_RATE_LIMIT_SALT",
    "invalid_image": "sobe e os secrets estão cadastrados",
}


def configuracao():
    valores = {}
    caminho = RAIZ / "Config.xcconfig"
    if not caminho.is_file():
        raise SystemExit("Config.xcconfig não encontrado; copie do .example e preencha.")
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        if "=" in linha and not linha.lstrip().startswith("//"):
            chave, valor = linha.split("=", 1)
            valores[chave.strip()] = valor.strip()
    url = valores.get("SUPABASE_URL", "")
    if url and not url.startswith("http"):
        url = "https://" + url
    return url.rstrip("/"), valores.get("SUPABASE_PUBLISHABLE_KEY", "")


def postar(url, chave, corpo):
    pedido = urllib.request.Request(
        url + "/functions/v1/analisar-peca",
        data=json.dumps(corpo).encode("utf-8"),
        headers={"apikey": chave, "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(pedido, timeout=90) as resposta:
            return resposta.status, json.loads(resposta.read())
    except urllib.error.HTTPError as erro:
        bruto = erro.read().decode("utf-8", "ignore")
        try:
            return erro.code, json.loads(bruto)
        except json.JSONDecodeError:
            return erro.code, {"corpo": bruto[:200]}


def diagnosticar(codigo, dados):
    marca = dados.get("code") or dados.get("error") or ""
    for chave, texto in ESTADOS.items():
        if chave == marca:
            print("HTTP {} -> {}".format(codigo, texto))
            return chave
    print("HTTP {} -> {}".format(codigo, json.dumps(dados, ensure_ascii=False)[:160]))
    return marca


def preparar(caminho, segmentador):
    """Isola a peça e normaliza em PNG de até 1024 px, igual ao benchmark."""
    origem = Path(caminho)
    if not origem.is_file():
        raise SystemExit("imagem não encontrada: {}".format(origem))
    with tempfile.TemporaryDirectory() as pasta:
        atual = origem
        if segmentador:
            recortada = Path(pasta) / "recorte.png"
            processo = subprocess.run([segmentador, str(origem), str(recortada)],
                                      capture_output=True, text=True)
            if processo.returncode != 0:
                raise SystemExit("o segmentador recusou a imagem: {}".format(
                    processo.stderr.strip()[:120]))
            atual = recortada
        destino = Path(pasta) / "envio.png"
        subprocess.run(["/usr/bin/sips", "-Z", "1024", "--setProperty", "format", "png",
                        str(atual), "--out", str(destino)],
                       capture_output=True, check=True)
        return base64.b64encode(destino.read_bytes()).decode("ascii")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("imagem", nargs="?")
    parser.add_argument("--alvo", default=None,
                        help="dica de alvo, como a caixa de texto do app envia")
    parser.add_argument("--segmentador", default="/tmp/segmentar-fundo",
                        help="binário do segmentar_fundo.swift; use '' para pular")
    parser.add_argument("--so-contrato", action="store_true",
                        help="não manda imagem e não gasta nada")
    args = parser.parse_args()

    url, chave = configuracao()
    if not url or not chave:
        raise SystemExit("SUPABASE_URL ou SUPABASE_PUBLISHABLE_KEY ausentes.")

    print("== estado da função (sem custo) ==")
    estado = diagnosticar(*postar(url, chave, {}))
    if args.so_contrato:
        return
    if estado != "invalid_image":
        print("\nNão adianta mandar imagem enquanto o estado acima não for "
              "'sobe e os secrets estão cadastrados'.")
        return
    if not args.imagem:
        print("\nPasse o caminho de uma imagem para o teste pago.")
        return

    print("\n== enviando uma imagem (~US$ 0,0007) ==")
    corpo = {"image_base64": preparar(args.imagem, args.segmentador or None),
             "media_type": "image/png"}
    if args.alvo:
        corpo["target_hint"] = args.alvo
    codigo, dados = postar(url, chave, corpo)
    if codigo != 200:
        diagnosticar(codigo, dados)
        return
    print("HTTP 200 — contrato devolvido:\n")
    for campo in ("category", "target_clarity", "garment_structure", "colors",
                  "pattern", "length", "silhouette", "waist", "fabrics",
                  "aesthetics", "decision_evidence"):
        if campo in dados:
            print("  {:22s} {}".format(campo, json.dumps(dados[campo], ensure_ascii=False)))


if __name__ == "__main__":
    sys.exit(main())
