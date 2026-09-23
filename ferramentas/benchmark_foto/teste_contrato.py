"""O benchmark de foto lê o contrato da Edge Function, e este teste garante
que ele continua conseguindo. Se o `index.ts` mudar de forma, o benchmark não
pode passar a medir um pedido diferente do que o app manda sem ninguém ver."""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luna  # noqa: E402


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def main():
    instrucoes, esquema, versao = luna.contrato_do_app()
    props = esquema["properties"]
    if len(props["garment_structure"]["enum"]) != 9:
        return falhar("estruturas da Edge Function nao foram lidas")
    for campo, minimo in (("pattern", 5), ("length", 3), ("colors", 8)):
        valores = props[campo].get("enum") or props[campo]["items"]["enum"]
        if len(valores) < minimo:
            return falhar("lista de {} veio curta: {}".format(campo, valores))
    if "Taxonomy:" not in instrucoes or "- colors: preto" not in instrucoes:
        return falhar("a taxonomia nao foi interpolada nas instrucoes")
    if not versao.startswith("alvo-"):
        return falhar("versao do prompt ilegivel: {}".format(versao))

    fotos = json.loads(luna.MANIFESTO.read_text(encoding="utf-8"))
    if len(fotos) != 100 or len({f["id"] for f in fotos}) != 100:
        return falhar("manifesto precisa de 100 fotos com id unico")
    for foto in fotos:
        if foto["licenca"] not in ("cc0", "by") or not foto.get("pagina"):
            return falhar("foto sem licenca aberta ou sem pagina de origem: {}".format(foto["id"]))
        if not foto["url"].startswith("https://"):
            return falhar("foto fora de https: {}".format(foto["id"]))
    print("OK: benchmark de foto le o contrato do app ({}) e 100 fotos de licenca aberta"
          .format(versao))
    return 0


if __name__ == "__main__":
    sys.exit(main())
