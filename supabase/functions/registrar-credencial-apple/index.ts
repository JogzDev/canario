// A50 — troca o authorization code de Sign in with Apple no servidor e guarda
// somente o refresh token necessário para a futura revogação REST.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { trocarCodigoApple } from "../_shared/apple-sign-in.ts";

const json = (corpo: Record<string, unknown>, status = 200) => new Response(
  JSON.stringify(corpo), { status, headers: { "content-type": "application/json" } },
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "missing_session" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceRole) return json({ error: "service_not_configured" }, 503);

  const corpo = await req.json().catch(() => null) as { authorization_code?: unknown } | null;
  const codigo = typeof corpo?.authorization_code === "string"
    ? corpo.authorization_code.trim() : "";
  // Código de autorização é credencial de uso único; limite evita que a função
  // vire um proxy arbitrário e nunca o devolvemos nem o registramos em logs.
  if (codigo.length < 8 || codigo.length > 8192) return json({ error: "invalid_code" }, 400);

  const scoped = createClient(url, publishable, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await scoped.auth.getUser();
  if (error || !data.user) return json({ error: "invalid_session" }, 401);

  const providers = Array.isArray(data.user.app_metadata?.providers)
    ? data.user.app_metadata.providers : [];
  if (!providers.includes("apple")) return json({ error: "not_apple_account" }, 403);

  const trocado = await trocarCodigoApple(codigo).catch(() => ({ error: "exchange_failed" }));
  if (!("refreshToken" in trocado)) {
    const admin = createClient(url, serviceRole, { auth: { persistSession: false } });
    // A Apple pode não repetir `refresh_token` em uma reautorização. Se já
    // temos um, a garantia de revogação permanece e o login não deve falhar.
    const { data: existente } = await admin
      .from("apple_refresh_tokens")
      .select("user_id")
      .eq("user_id", data.user.id)
      .maybeSingle();
    if (existente) return json({ stored: true, reused: true });
    return json({ error: trocado.error === "not_configured"
      ? "apple_revocation_not_configured" : "apple_code_exchange_failed" }, 503);
  }

  const admin = createClient(url, serviceRole, { auth: { persistSession: false } });
  const { error: storeError } = await admin.from("apple_refresh_tokens").upsert({
    user_id: data.user.id,
    refresh_token: trocado.refreshToken,
    atualizado_em: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (storeError) return json({ error: "credential_store_failed" }, 503);
  return json({ stored: true, reused: false });
});
