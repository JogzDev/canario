#!/usr/bin/env python3
"""Contrato estático da rota paga de visão, sem rede e sem consumir tokens."""

from pathlib import Path


RAIZ = Path(__file__).resolve().parents[1]
FUNCAO = RAIZ / "supabase/functions/analisar-peca/index.ts"
CONFIG = RAIZ / "supabase/config.toml"
MIGRACAO = RAIZ / "supabase/migrations/20260814150000_p6_limite_da_analise_visual.sql"
APP = RAIZ / "app/Canario/Rede/Supabase.swift"


def exigir(texto, trechos, nome):
    for trecho in trechos:
        assert trecho in texto, "{} não garante {!r}".format(nome, trecho)


def main():
    funcao = FUNCAO.read_text(encoding="utf-8")
    config = CONFIG.read_text(encoding="utf-8")
    migracao = MIGRACAO.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")

    exigir(funcao, [
        'withSupabase({ auth: "publishable" }',
        'const MODEL = "gpt-5.6-luna"',
        'const PROMPT_VERSION = "alvo-estrutura-motivos-cintura-v10"',
        'print_motifs',
        'tomate_print',
        'conversacional',
        'cintura_baixa',
        'A pullover, sweatshirt, hoodie or quarter-zip fleece is upper_other',
        'store: false',
        'detail: "high"',
        'strict: true',
        'MAX_IMAGE_BYTES = 3_000_000',
        'target_hint',
        'targetHint.length > 160',
        'never let it override visible pixels',
        '"_reservar_analise_visual"',
        'Deno.env.get("OPENAI_API_KEY")',
        'Deno.env.get("AI_RATE_LIMIT_SALT")',
        'Cache-Control": "no-store"',
    ], "Edge Function")
    exigir(config, [
        "[functions.analisar-peca]",
        "verify_jwt = false",
    ], "config da função")
    exigir(migracao.lower(), [
        "enable row level security",
        "pg_advisory_xact_lock",
        "grant execute on function public._reservar_analise_visual",
        "to service_role",
        "revoke all on table public._limites_analise_visual",
    ], "limite de custo")
    exigir(app, [
        'req.setValue(chave, forHTTPHeaderField: "apikey")',
        'url.appendingPathComponent("functions/v1/analisar-peca")',
        'dados.base64EncodedString()',
        '"target_hint"',
    ], "cliente iOS")
    assert "OPENAI_API_KEY" not in app, "chave da OpenAI apareceu no binário"
    print("Edge Luna: auth, privacidade, contrato e limite de custo presentes")


if __name__ == "__main__":
    main()
