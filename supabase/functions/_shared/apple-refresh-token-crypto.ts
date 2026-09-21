// Cifragem de aplicacao para a unica credencial Apple que precisa sobreviver
// ao login: o refresh token usado exclusivamente na exclusao da conta.
//
// A chave nunca vai para o banco nem para o cliente. O numero da versao fica
// ao lado do texto cifrado para permitir rotacao: mantenha as versoes antigas
// durante a transicao e aponte APPLE_REFRESH_TOKEN_KEY_VERSION para a nova.

const CODIFICADOR = new TextEncoder();
const DECODIFICADOR = new TextDecoder("utf-8", { fatal: true });
const ALGORITMO = "aes-256-gcm-v1";
const TAMANHO_CHAVE = 32;
const TAMANHO_NONCE = 12;

export type ChaveDeTokenApple = {
  versao: number;
  material: Uint8Array<ArrayBuffer>;
};

export type TokenAppleCifrado = {
  refresh_token_cifrado: string;
  nonce_cifragem: string;
  versao_chave: number;
  algoritmo_cifragem: typeof ALGORITMO;
};

export type LinhaDeTokenApple = Partial<TokenAppleCifrado> & {
  refresh_token?: string | null;
};

export class ConfiguracaoDeTokenAppleInvalida extends Error {}

function bytesDeBase64(valor: string): Uint8Array<ArrayBuffer> {
  let binario: string;
  try {
    binario = atob(valor);
  } catch {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_base64");
  }
  return Uint8Array.from(binario, (caractere) => caractere.charCodeAt(0));
}

function base64DeBytes(valor: Uint8Array): string {
  return btoa(String.fromCharCode(...valor));
}

function conferirChave(chave: ChaveDeTokenApple): void {
  if (
    !Number.isSafeInteger(chave.versao) || chave.versao < 1 ||
    chave.versao > 32767
  ) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_key_version");
  }
  if (chave.material.byteLength !== TAMANHO_CHAVE) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_key_length");
  }
}

function dadosAssociados(userId: string): Uint8Array<ArrayBuffer> {
  if (!userId) throw new ConfiguracaoDeTokenAppleInvalida("missing_user_id");
  // Vincula o texto cifrado ao dono: copiar colunas entre usuarios faz a
  // autenticacao do AES-GCM falhar, em vez de revogar a credencial errada.
  return CODIFICADOR.encode(`datadrobe:apple-refresh-token:v1:${userId}`);
}

async function importar(
  chave: ChaveDeTokenApple,
  uso: KeyUsage,
): Promise<CryptoKey> {
  conferirChave(chave);
  return crypto.subtle.importKey(
    "raw",
    chave.material,
    { name: "AES-GCM" },
    false,
    [uso],
  );
}

export function carregarChaveDeTokenApple(versao: number): ChaveDeTokenApple {
  if (!Number.isSafeInteger(versao) || versao < 1 || versao > 32767) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_key_version");
  }
  const codificada = Deno.env.get(`APPLE_REFRESH_TOKEN_KEY_V${versao}`)?.trim();
  if (!codificada) throw new ConfiguracaoDeTokenAppleInvalida("missing_key");
  const chave = { versao, material: bytesDeBase64(codificada) };
  conferirChave(chave);
  return chave;
}

export function carregarChaveAtivaDeTokenApple(): ChaveDeTokenApple {
  const texto = Deno.env.get("APPLE_REFRESH_TOKEN_KEY_VERSION")?.trim();
  if (!texto || !/^[1-9][0-9]*$/.test(texto)) {
    throw new ConfiguracaoDeTokenAppleInvalida("missing_active_key_version");
  }
  return carregarChaveDeTokenApple(Number(texto));
}

export async function cifrarTokenAppleComChave(
  token: string,
  userId: string,
  chave: ChaveDeTokenApple,
  nonceForcado?: Uint8Array<ArrayBufferLike>,
): Promise<TokenAppleCifrado> {
  if (token.length < 16 || token.length > 4096) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_token_length");
  }
  const nonce: Uint8Array<ArrayBuffer> = nonceForcado
    ? Uint8Array.from(nonceForcado)
    : crypto.getRandomValues(new Uint8Array(TAMANHO_NONCE));
  if (nonce.byteLength !== TAMANHO_NONCE) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_nonce_length");
  }
  const cryptoKey = await importar(chave, "encrypt");
  const cifrado = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: dadosAssociados(userId),
      tagLength: 128,
    },
    cryptoKey,
    CODIFICADOR.encode(token),
  );
  return {
    refresh_token_cifrado: base64DeBytes(new Uint8Array(cifrado)),
    nonce_cifragem: base64DeBytes(nonce),
    versao_chave: chave.versao,
    algoritmo_cifragem: ALGORITMO,
  };
}

export async function decifrarTokenAppleComChave(
  linha: TokenAppleCifrado,
  userId: string,
  chave: ChaveDeTokenApple,
): Promise<string> {
  if (
    linha.algoritmo_cifragem !== ALGORITMO ||
    linha.versao_chave !== chave.versao
  ) {
    throw new ConfiguracaoDeTokenAppleInvalida("unsupported_ciphertext");
  }
  const nonce = bytesDeBase64(linha.nonce_cifragem);
  if (nonce.byteLength !== TAMANHO_NONCE) {
    throw new ConfiguracaoDeTokenAppleInvalida("invalid_nonce_length");
  }
  const cryptoKey = await importar(chave, "decrypt");
  const aberto = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: dadosAssociados(userId),
      tagLength: 128,
    },
    cryptoKey,
    bytesDeBase64(linha.refresh_token_cifrado),
  );
  return DECODIFICADOR.decode(aberto);
}

export async function cifrarTokenApple(
  token: string,
  userId: string,
): Promise<TokenAppleCifrado> {
  return cifrarTokenAppleComChave(
    token,
    userId,
    carregarChaveAtivaDeTokenApple(),
  );
}

export async function recuperarTokenApple(
  linha: LinhaDeTokenApple,
  userId: string,
  carregarChave: (versao: number) => ChaveDeTokenApple =
    carregarChaveDeTokenApple,
): Promise<string> {
  // Compatibilidade transitória com A50. Nenhuma nova gravação usa este ramo;
  // o próximo login Apple regrava a linha cifrada com a chave ativa.
  if (
    typeof linha.refresh_token === "string" && linha.refresh_token.length >= 16
  ) {
    return linha.refresh_token;
  }
  if (
    typeof linha.refresh_token_cifrado !== "string" ||
    typeof linha.nonce_cifragem !== "string" ||
    typeof linha.versao_chave !== "number" ||
    linha.algoritmo_cifragem !== ALGORITMO
  ) {
    throw new ConfiguracaoDeTokenAppleInvalida("incomplete_ciphertext");
  }
  return decifrarTokenAppleComChave(
    linha as TokenAppleCifrado,
    userId,
    carregarChave(linha.versao_chave),
  );
}
