#!/usr/bin/env python3
"""Portoes locais para invariantes de seguranca que podem regredir em texto."""

import re
from pathlib import Path


RAIZ = Path(__file__).resolve().parents[1]


def ler(caminho: str) -> str:
    return (RAIZ / caminho).read_text(encoding="utf-8")


def main() -> None:
    autenticacao = ler("app/Canario/Rede/Autenticacao.swift")
    supabase = ler("app/Canario/Rede/Supabase.swift")
    edge = [
        ler("supabase/functions/analisar-peca/index.ts"),
        ler("supabase/functions/excluir-conta/index.ts"),
        ler("supabase/functions/registrar-credencial-apple/index.ts"),
    ]

    for nome, texto in (("Autenticacao", autenticacao), ("Supabase", supabase)):
        assert 'url.scheme?.lowercased() == "https"' in texto, (
            f"{nome} deixou de exigir HTTPS")
        assert 'URL(string: "https://invalido.invalido")' in texto, (
            f"{nome} nao falha fechado para endpoint invalido")

    for texto in edge:
        minusculo = texto.lower()
        assert '"cache-control": "no-store"' in minusculo, (
            "resposta sensivel pode ser armazenada em cache")
        assert '"x-content-type-options": "nosniff"' in minusculo, (
            "resposta JSON perdeu nosniff")

    imports = "\n".join(edge)
    assert "npm:@supabase/server@1.7.0" in imports
    assert "https://esm.sh/@supabase/supabase-js@2.116.0" in imports
    assert not re.search(r"supabase-js@2(?:[\"'/]|$)", imports), (
        "dependencia Deno voltou a flutuar no major")

    for workflow in (RAIZ / ".github/workflows").glob("*.yml"):
        for numero, linha in enumerate(
                workflow.read_text(encoding="utf-8").splitlines(), 1):
            encontrado = re.match(r"\s*-?\s*uses:\s*([^#\s]+)", linha)
            if not encontrado:
                continue
            acao = encontrado.group(1)
            if acao.startswith("./"):
                continue
            referencia = acao.rsplit("@", 1)[-1]
            assert re.fullmatch(r"[0-9a-f]{40}", referencia), (
                f"{workflow.name}:{numero} usa Action sem SHA imutavel")

    app = "\n".join(
        arquivo.read_text(encoding="utf-8", errors="ignore")
        for arquivo in (RAIZ / "app").rglob("*") if arquivo.is_file()
    )
    assert "SUPABASE_SERVICE_ROLE_KEY" not in app
    assert "OPENAI_API_KEY" not in app
    print("Seguranca: HTTPS, headers, imports fixos, Actions e segredos protegidos")


if __name__ == "__main__":
    main()
