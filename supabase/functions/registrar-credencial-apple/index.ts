// A50 — troca o authorization code de Sign in with Apple no servidor e guarda
// somente o refresh token necessário para a futura revogação REST.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
import { trocarCodigoApple } from "../_shared/apple-sign-in.ts";
import {
  carregarChaveAtivaDeTokenApple,
  cifrarTokenAppleComChave,
  type LinhaDeTokenApple,
  recuperarTokenApple,
} from "../_shared/apple-refresh-token-crypto.ts";

const JSON_HEADERS = {
  "content-type": "application/json",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

const json = (corpo: Record<string, unknown>, status = 200) =>
  new Response(
    JSON.stringify(corpo),
    { status, headers: JSON_HEADERS },
  );

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "missing_session" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceRole) {
    return json({ error: "service_not_configured" }, 503);
  }

  const corpo = await req.json().catch(() => null) as {
    authorization_code?: unknown;
  } | null;
  const codigo = typeof corpo?.authorization_code === "string"
    ? corpo.authorization_code.trim()
    : "";
  // Código de autorização é credencial de uso único; limite evita que a função
  // vire um proxy arbitrário e nunca o devolvemos nem o registramos em logs.
  if (codigo.length < 8 || codigo.length > 8192) {
    return json({ error: "invalid_code" }, 400);
  }

  const scoped = createClient(url, publishable, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await scoped.auth.getUser();
  if (error || !data.user) return json({ error: "invalid_session" }, 401);

  const providers = Array.isArray(data.user.app_metadata?.providers)
    ? data.user.app_metadata.providers
    : [];
  if (!providers.includes("apple")) {
    return json({ error: "not_apple_account" }, 403);
  }

  // Confere a chave ANTES de consumir o authorization code de uso unico. Uma
  // implantacao incompleta falha sem perder a unica oportunidade de troca.
  let chaveAtiva;
  try {
    chaveAtiva = carregarChaveAtivaDeTokenApple();
  } catch {
    return json({ error: "apple_revocation_not_configured" }, 503);
  }

  const trocado = await trocarCodigoApple(codigo).catch(() => ({
    error: "exchange_failed",
  }));
  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false },
  });
  let token: string;
  let reutilizado = false;
  if (!("refreshToken" in trocado)) {
    // A Apple pode não repetir `refresh_token` em uma reautorização. Se já
    // temos um, abrimos a linha antiga e a regravamos com a chave ativa. Assim
    // cada novo login também avança a migração e a rotação, mesmo sem token
    // novo emitido pela Apple.
    const { data: existente, error: existingError } = await admin
      .from("apple_refresh_tokens")
      .select(
        "refresh_token,refresh_token_cifrado,nonce_cifragem,versao_chave,algoritmo_cifragem",
      )
      .eq("user_id", data.user.id)
      .maybeSingle();
    if (existingError || !existente) {
      return json({
        error: trocado.error === "not_configured"
          ? "apple_revocation_not_configured"
          : "apple_code_exchange_failed",
      }, 503);
    }
    try {
      token = await recuperarTokenApple(
        existente as LinhaDeTokenApple,
        data.user.id,
      );
      reutilizado = true;
    } catch {
      return json({ error: "credential_store_failed" }, 503);
    }
  } else {
    token = trocado.refreshToken;
  }

  let protegida;
  try {
    protegida = await cifrarTokenAppleComChave(token, data.user.id, chaveAtiva);
  } catch {
    return json({ error: "credential_store_failed" }, 503);
  }
  const { error: storeError } = await admin.from("apple_refresh_tokens").upsert(
    {
      user_id: data.user.id,
      refresh_token: null,
      ...protegida,
      atualizado_em: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
  if (storeError) return json({ error: "credential_store_failed" }, 503);
  return json({ stored: true, reused: reutilizado });
});
