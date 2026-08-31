// A26 — exclusão integral iniciada dentro do app.
// A função valida o JWT recebido e usa service role somente no servidor.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { revogarTokenApple } from "../_shared/apple-sign-in.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "missing_session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceRole) {
    return new Response(JSON.stringify({ error: "service_not_configured" }), {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  }

  const scoped = createClient(url, publishable, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await scoped.auth.getUser();
  if (error || !data.user) {
    return new Response(JSON.stringify({ error: "invalid_session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, serviceRole, { auth: { persistSession: false } });

  const providers = Array.isArray(data.user.app_metadata?.providers)
    ? data.user.app_metadata.providers : [];
  const usaApple = providers.includes("apple");
  let revogacaoApple: "not_applicable" | "revoked" | "manual_required" = "not_applicable";
  if (usaApple) {
    const { data: credencial, error: credentialError } = await admin
      .from("apple_refresh_tokens")
      .select("refresh_token")
      .eq("user_id", data.user.id)
      .maybeSingle();
    // Não interrompemos o direito de exclusão porque uma conta antiga pode
    // não ter token para a Apple revogar. Nesse caso o cliente abre o caminho
    // oficial manual depois de apagar os dados, como a Apple orienta.
    if (!credentialError && credencial?.refresh_token) {
      const revogado = await revogarTokenApple(credencial.refresh_token)
        .catch(() => false);
      revogacaoApple = revogado ? "revoked" : "manual_required";
    } else {
      revogacaoApple = "manual_required";
    }
  }

  // A44 ligou o Storage, e a linha abaixo era o aviso deixado quando ele ainda
  // não existia: apagar o usuário faz `closet_items` cair por ON DELETE CASCADE,
  // mas NÃO remove objeto de bucket. Sem esta limpeza, as miniaturas do Closet
  // sobreviveriam à exclusão da conta — inalcançáveis, porque a RLS as prende ao
  // `auth.uid()` que deixou de existir, e ainda assim armazenadas. A Apple exige
  // que excluir a conta remova os dados associados, e o plano gratuito tem 1 GB.
  //
  // A ordem importa: purgar ANTES de `deleteUser`. Se a purga falhar, a conta
  // continua de pé e a pessoa pode tentar de novo; o contrário deixaria arquivo
  // órfão sem dono para reclamar dele.
  const prefixo = data.user.id;
  const paraApagar: string[] = [];
  const porPagina = 100;
  for (let pagina = 0; ; pagina += 1) {
    const { data: objetos, error: listError } = await admin.storage
      .from("closet-thumbnails")
      .list(prefixo, { limit: porPagina, offset: pagina * porPagina });
    if (listError) {
      return new Response(JSON.stringify({ error: "thumbnail_cleanup_failed" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }
    if (!objetos || objetos.length === 0) break;
    for (const objeto of objetos) paraApagar.push(`${prefixo}/${objeto.name}`);
    if (objetos.length < porPagina) break;
  }
  if (paraApagar.length > 0) {
    const { error: removeError } = await admin.storage
      .from("closet-thumbnails")
      .remove(paraApagar);
    if (removeError) {
      return new Response(JSON.stringify({ error: "thumbnail_cleanup_failed" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id, false);
  if (deleteError) {
    return new Response(JSON.stringify({ error: "delete_failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  // `miniaturas_removidas` existe para a exclusão ser auditável: sem ela, "deu
  // certo" e "não havia nada para apagar" respondem exatamente igual.
  return new Response(JSON.stringify({
    deleted: true,
    miniaturas_removidas: paraApagar.length,
    apple_revocation: revogacaoApple,
  }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
