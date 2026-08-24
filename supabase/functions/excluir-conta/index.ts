// A26 — exclusão integral iniciada dentro do app.
// A função valida o JWT recebido e usa service role somente no servidor.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  // `closet_items` usa ON DELETE CASCADE. Se Storage for ligado no futuro,
  // seus objetos precisam ser removidos antes desta linha.
  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id, false);
  if (deleteError) {
    return new Response(JSON.stringify({ error: "delete_failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
