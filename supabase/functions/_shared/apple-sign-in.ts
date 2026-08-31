import { importPKCS8, SignJWT } from "https://deno.land/x/jose@v5.9.6/index.ts";

const APPLE_AUDIENCE = "https://appleid.apple.com";

type CredenciaisApple = {
  clientId: string;
  keyId: string;
  teamId: string;
  privateKey: string;
};

type RespostaDoTokenApple = {
  access_token?: string;
  refresh_token?: string;
  error?: string;
};

function credenciais(): CredenciaisApple | null {
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "br.com.canario.ch3.app";
  const keyId = Deno.env.get("APPLE_SIGN_IN_KEY_ID");
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const privateKey = Deno.env.get("APPLE_SIGN_IN_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (!clientId || !keyId || !teamId || !privateKey) return null;
  return { clientId, keyId, teamId, privateKey };
}

async function segredoDoCliente(credenciais: CredenciaisApple): Promise<string> {
  const chave = await importPKCS8(credenciais.privateKey, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: credenciais.keyId })
    .setIssuer(credenciais.teamId)
    .setSubject(credenciais.clientId)
    .setAudience(APPLE_AUDIENCE)
    .setIssuedAt()
    // A Apple limita esse JWT a seis meses. Uma hora reduz a exposição e a
    // função o cria sob demanda, sem persistir outro segredo.
    .setExpirationTime("1h")
    .sign(chave);
}

async function pedirToken(corpo: URLSearchParams): Promise<RespostaDoTokenApple> {
  const resposta = await fetch(`${APPLE_AUDIENCE}/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: corpo,
  });
  const json = await resposta.json().catch(() => ({})) as RespostaDoTokenApple;
  if (!resposta.ok) return { error: json.error ?? `http_${resposta.status}` };
  return json;
}

export async function trocarCodigoApple(codigo: string): Promise<
  { refreshToken: string } | { error: string }
> {
  const configuradas = credenciais();
  if (!configuradas) return { error: "not_configured" };
  const clientSecret = await segredoDoCliente(configuradas);
  const resposta = await pedirToken(new URLSearchParams({
    client_id: configuradas.clientId,
    client_secret: clientSecret,
    code: codigo,
    grant_type: "authorization_code",
  }));
  return resposta.refresh_token
    ? { refreshToken: resposta.refresh_token }
    : { error: resposta.error ?? "missing_refresh_token" };
}

/// O endpoint REST aceita refresh ou access token. Usamos somente o refresh
/// token, porque é o único que ainda existe quando a conta é excluída depois.
export async function revogarTokenApple(token: string): Promise<boolean> {
  const configuradas = credenciais();
  if (!configuradas) return false;
  const clientSecret = await segredoDoCliente(configuradas);
  const resposta = await fetch(`${APPLE_AUDIENCE}/auth/revoke`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: configuradas.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: "refresh_token",
    }),
  });
  return resposta.ok;
}
