import { withSupabase } from "npm:@supabase/server@1.7.0";
import {
  esquemaDaInterpretacao, esquemaDaRedacao, esquemaDaVerificacao, type Fato, type Frase,
  INTERPRETACAO, MODELOS, pedidoLimpo, REDACAO, termosDeBusca, VERIFICACAO, VERSAO,
  verificarFrases,
} from "./leitura.ts";

// Leitura específica de uma peça (2.0). O pedido chega como texto ("jaqueta
// napoleão"), como a análise de uma foto feita por `analisar-peca`, ou os
// dois; a resposta é uma leitura em frases, cada uma com os fatos que a
// provam, e as peças que a pessoa abre ao tocar numa frase.
//
// A chave da OpenAI e a chave de serviço nunca saem daqui. O limite de custo é
// o mesmo da leitura de foto (`_reservar_analise_visual`): uma leitura conta
// como uma reserva.

const OPENAI_URL = "https://api.openai.com/v1/responses";
const CANDIDATAS_PARA_VERIFICAR = 40;
const MINIMO_PARA_LER = 3;

function response(status: number, body: Record<string, unknown>) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", "Content-Type": "application/json", "X-Content-Type-Options": "nosniff" },
  });
}

function outputText(payload: any): string | null {
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") continue;
    for (const content of item.content ?? []) {
      if (content?.type === "output_text") return content.text ?? null;
      if (content?.type === "refusal") return null;
    }
  }
  return null;
}

/** Uma chamada estruturada, com a reserva de modelo da leitura de foto. */
async function luna(apiKey: string, nome: string, instrucoes: string, entrada: string,
                    esquema: Record<string, unknown>): Promise<{ dados: any; modelo: string } | null> {
  for (const model of MODELOS) {
    try {
      const r = await fetch(OPENAI_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model, store: false, reasoning: { effort: "low" }, max_output_tokens: 3000,
          instructions: instrucoes,
          input: [{ role: "user", content: [{ type: "input_text", text: entrada }] }],
          text: { format: { type: "json_schema", name: nome, strict: true, schema: esquema } },
        }),
      });
      if (!r.ok) continue;
      const texto = outputText(await r.json());
      if (!texto) continue;
      return { dados: JSON.parse(texto), modelo: model };
    } catch {
      continue;
    }
  }
  return null;
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export default {
  fetch: withSupabase({ auth: "publishable" }, async (req, ctx) => {
    if (req.method !== "POST") return response(405, { error: "method_not_allowed" });
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const salt = Deno.env.get("AI_RATE_LIMIT_SALT");
    if (!apiKey || !salt || salt.length < 24) return response(503, { error: "reading_not_configured" });

    let body: any;
    try { body = await req.json(); } catch { return response(400, { error: "invalid_json" }); }
    const texto = pedidoLimpo(body?.texto);
    const refinamento = pedidoLimpo(body?.refinamento);
    const analise = body?.analise && typeof body.analise === "object" ? body.analise : null;
    const preco = typeof body?.preco_da_pessoa === "number" && body.preco_da_pessoa > 0 &&
      body.preco_da_pessoa < 100000 ? body.preco_da_pessoa : null;
    if (!texto && !analise) return response(400, { error: "empty_request" });

    const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
    const { data: reserva, error: erroDaReserva } = await ctx.supabaseAdmin.rpc(
      "_reservar_analise_visual",
      { p_origem_hash: await sha256(`${salt}:${forwarded}`), p_limite_origem: 12, p_limite_global: 120 },
    );
    if (erroDaReserva) return response(503, { error: "rate_limit_unavailable" });
    const vaga = Array.isArray(reserva) ? reserva[0] : reserva;
    if (!vaga?.permitida) return response(429, { error: vaga?.motivo || "rate_limited" });

    // 1. Interpretação. Só campos conhecidos da análise de foto seguem: o
    // resto do objeto nunca chega à Luna.
    const analiseSegura = analise ? {
      category: analise.category, pattern: analise.pattern, length: analise.length,
      colors: analise.colors, fabrics: analise.fabrics, silhouette: analise.silhouette,
      additional_visual_attributes: analise.additional_visual_attributes,
    } : null;
    const entrada = [
      `Categories: ${JSON.stringify(["vestido", "macacao", "saia", "short", "calca", "camisa", "casaco_jaqueta", "blusa_top"])}`,
      texto ? `Typed request: <request>${texto}</request>` : "",
      refinamento ? `Chosen follow-up answer: <answer>${refinamento}</answer>` : "",
      analiseSegura ? `Visual analysis of the person's photo: ${JSON.stringify(analiseSegura)}` : "",
    ].filter(Boolean).join("\n");
    const interpretacao = await luna(apiKey, "interpretacao_da_peca", INTERPRETACAO, entrada, esquemaDaInterpretacao());
    if (!interpretacao) return response(502, { error: "reading_provider_error" });
    const peca = interpretacao.dados;
    if (peca.fora_de_escopo) {
      return response(200, { versao: VERSAO, fora_de_escopo: true, nome: peca.nome, explicacao: peca.explicacao });
    }
    const sinais = termosDeBusca(peca.sinais, 12);
    const vetos = termosDeBusca(peca.vetos, 12);
    if (!sinais.length) return response(502, { error: "reading_without_signals" });

    // 2. Candidatas ativas do painel publicado (A64).
    const { data: candidatas, error: erroDasCandidatas } = await ctx.supabaseAdmin.rpc(
      "candidatas_da_leitura",
      { p_categorias: peca.categorias ?? [], p_sinais: sinais, p_vetos: vetos, p_limite: CANDIDATAS_PARA_VERIFICAR },
    );
    if (erroDasCandidatas) return response(503, { error: "panel_unavailable" });
    const lista: any[] = candidatas?.pecas ?? [];
    const base = {
      versao: VERSAO, nome: peca.nome, explicacao: peca.explicacao, perguntas: peca.perguntas ?? [],
      painel_observado_em: candidatas?.painel_observado_em ?? null,
      busca: { categorias: peca.categorias, sinais, vetos, candidatas: candidatas?.total ?? 0 },
    };
    if (!lista.length) {
      return response(200, { ...base, frases: [], fatos: {}, pecas: [], modelo: interpretacao.modelo });
    }

    // 3. Verificação pelo título. Id que a Luna invente não entra: o esquema
    // só aceita os ids das candidatas.
    const ids = lista.map((p) => Number(p.id));
    const verificacao = await luna(
      apiKey, "verificacao_das_candidatas", VERIFICACAO,
      JSON.stringify({ peca: { nome: peca.nome, explicacao: peca.explicacao },
                       candidatas: lista.map((p) => ({ id: p.id, titulo: p.titulo })) }),
      esquemaDaVerificacao(ids));
    if (!verificacao) return response(502, { error: "reading_provider_error" });
    const veredito = new Map<number, string>();
    for (const v of verificacao.dados.veredictos ?? []) veredito.set(Number(v.id), v.veredito);
    const confirmadas = ids.filter((id) => veredito.get(id) === "e_a_peca");
    const parecidas = ids.filter((id) => veredito.get(id) === "parecida");
    // Com menos de três iguais, a leitura olha também as parecidas, e diz isso.
    const ampliada = confirmadas.length < MINIMO_PARA_LER;
    const lidas = ampliada ? [...confirmadas, ...parecidas] : confirmadas;
    const pecas = lista.filter((p) => lidas.includes(Number(p.id)))
      .map((p) => ({ ...p, veredito: veredito.get(Number(p.id)) }));
    if (!lidas.length) {
      return response(200, { ...base, frases: [], fatos: {}, pecas: [], ampliada, modelo: verificacao.modelo });
    }

    // 4. Fatos das verificadas (A64).
    const { data: fatosBrutos, error: erroDosFatos } = await ctx.supabaseAdmin.rpc(
      "fatos_da_leitura", { p_ids: lidas, p_preco_da_pessoa: preco });
    if (erroDosFatos) return response(503, { error: "panel_unavailable" });
    const fatos: Record<string, Fato> = {};
    for (const f of fatosBrutos?.fatos ?? []) fatos[f.id] = f;

    // 5. Redação, e o verificador corta toda frase sem prova.
    const redacao = await luna(
      apiKey, "leitura_da_peca", REDACAO,
      JSON.stringify({ peca: { nome: peca.nome, explicacao: peca.explicacao },
                       ampliada_com_parecidas: ampliada, fatos }),
      esquemaDaRedacao(Object.keys(fatos)));
    if (!redacao) return response(502, { error: "reading_provider_error" });
    const { aceitas, recusadas } = verificarFrases((redacao.dados.frases ?? []) as Frase[], fatos);

    return response(200, {
      ...base,
      ampliada,
      frases: aceitas,
      frases_recusadas: recusadas.length,
      fatos,
      pecas,
      modelo: redacao.modelo,
    });
  }),
};
