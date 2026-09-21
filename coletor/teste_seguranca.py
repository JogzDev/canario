#!/usr/bin/env python3
"""Portoes locais para invariantes de seguranca que podem regredir em texto."""

import hashlib
import re
from pathlib import Path
from typing import Optional


RAIZ = Path(__file__).resolve().parents[1]
MIGRACOES = RAIZ / "supabase/migrations"
ULTIMA_MIGRACAO_INVENTARIADA = "20260917211000_a58_significado_da_capa_e_busca_editorial.sql"
# Impressao de `arquivo + GRANT normalizado` para todos os grants historicos
# destinados a anon/authenticated/PUBLIC ate a migration acima. Mudar uma
# migration ja aplicada ou alargar o legado sem atualizar a auditoria falha.
HASH_GRANTS_HISTORICOS = "112d46de216b0944e9809aacd09579bdf5d49b2e2a8873ca1c65d35c56b1a30f"
PADRAO_GRANT = re.compile(r"\bgrant\b.*?;", re.IGNORECASE | re.DOTALL)
PADRAO_PAPEL_PUBLICO = re.compile(
    r"\bto\s+(?:public|anon|authenticated)"
    r"(?:\s*,\s*(?:public|anon|authenticated))*\s*;",
    re.IGNORECASE,
)
PADRAO_JUSTIFICATIVA = re.compile(r"--\s*acesso-publico:\s*(\S.*)", re.IGNORECASE)


def ler(caminho: str) -> str:
    return (RAIZ / caminho).read_text(encoding="utf-8")


def sem_comentarios_sql(texto: str) -> str:
    """Oculta comentarios sem mudar linhas/posicoes dos comandos seguintes."""
    def apagar(match: re.Match) -> str:
        return "".join("\n" if caractere == "\n" else " "
                       for caractere in match.group(0))

    texto = re.sub(r"/\*.*?\*/", apagar, texto, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", apagar, texto)


def grants_publicos(texto: str) -> list[tuple[int, str]]:
    """Devolve linha e forma canonica dos GRANTs para papeis do cliente."""
    encontrados = []
    limpo = sem_comentarios_sql(texto)
    for match in PADRAO_GRANT.finditer(limpo):
        declaracao = match.group(0)
        if not PADRAO_PAPEL_PUBLICO.search(declaracao):
            continue
        linha = texto.count("\n", 0, match.start()) + 1
        canonica = re.sub(r"\s+", " ", declaracao).strip().lower()
        encontrados.append((linha, canonica))
    return encontrados


def justificativa_anterior(texto: str, linha: int) -> Optional[str]:
    """Exige a justificativa na ultima linha nao vazia antes do GRANT."""
    anteriores = texto.splitlines()[:linha - 1]
    while anteriores and not anteriores[-1].strip():
        anteriores.pop()
    if not anteriores:
        return None
    encontrada = PADRAO_JUSTIFICATIVA.fullmatch(anteriores[-1].strip())
    if not encontrada:
        return None
    motivo = encontrada.group(1).strip()
    return motivo if len(motivo) >= 30 else None


def conferir_inventario_de_acesso() -> None:
    historicos = []
    sem_justificativa = []
    for arquivo in sorted(MIGRACOES.glob("*.sql")):
        texto = arquivo.read_text(encoding="utf-8")
        grants = grants_publicos(texto)
        if arquivo.name <= ULTIMA_MIGRACAO_INVENTARIADA:
            historicos.extend(
                f"{arquivo.name}\t{declaracao}" for _, declaracao in grants)
        else:
            for linha, declaracao in grants:
                if justificativa_anterior(texto, linha) is None:
                    sem_justificativa.append(
                        f"{arquivo.name}:{linha}: {declaracao}")

    assinatura = hashlib.sha256("\n".join(historicos).encode()).hexdigest()
    assert assinatura == HASH_GRANTS_HISTORICOS, (
        "GRANT historico para papel publico mudou sem nova migration e auditoria: "
        f"{assinatura}")
    assert not sem_justificativa, (
        "novo GRANT para anon/authenticated/PUBLIC exige imediatamente antes "
        "`-- acesso-publico: <motivo com pelo menos 30 caracteres>`:\n"
        + "\n".join(sem_justificativa))

    # Prova o proprio detector: service_role nao e superficie publica, e uma
    # justificativa vaga ou ausente nao libera um endpoint por engano.
    fixture_ok = (
        "-- acesso-publico: leitura da projecao minima consumida pelo aplicativo\n"
        "grant select on public.exemplo to anon, authenticated;"
    )
    assert len(grants_publicos(fixture_ok)) == 1
    assert justificativa_anterior(fixture_ok, 2)
    assert not grants_publicos(
        "grant execute on function public.interna() to service_role;")
    fixture_ruim = "-- acesso-publico: necessario\ngrant select on x to anon;"
    assert justificativa_anterior(fixture_ruim, 2) is None


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
    conferir_inventario_de_acesso()
    print("Seguranca: HTTPS, headers, imports fixos, Actions, segredos e grants protegidos")


if __name__ == "__main__":
    main()
