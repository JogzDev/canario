import {
  type ChaveDeTokenApple,
  cifrarTokenAppleComChave,
  ConfiguracaoDeTokenAppleInvalida,
  decifrarTokenAppleComChave,
  recuperarTokenApple,
} from "./apple-refresh-token-crypto.ts";

function exigir(condicao: boolean, mensagem: string): void {
  if (!condicao) throw new Error(mensagem);
}

async function exigirRejeicao(acao: () => Promise<unknown>): Promise<void> {
  let rejeitou = false;
  try {
    await acao();
  } catch {
    rejeitou = true;
  }
  exigir(rejeitou, "a operacao deveria ter falhado fechada");
}

const chave = (versao = 1, deslocamento = 0): ChaveDeTokenApple => ({
  versao,
  material: Uint8Array.from({ length: 32 }, (_, i) => (i + deslocamento) % 256),
});

Deno.test("AES-GCM recupera o token sem o guardar em claro", async () => {
  const token = "refresh-token-sintetico-com-tamanho-valido";
  const cifrado = await cifrarTokenAppleComChave(
    token,
    "usuario-a",
    chave(),
    new Uint8Array(12),
  );
  exigir(
    !cifrado.refresh_token_cifrado.includes(token),
    "token apareceu no texto cifrado",
  );
  exigir(cifrado.versao_chave === 1, "versao da chave nao acompanhou o token");
  const aberto = await decifrarTokenAppleComChave(
    cifrado,
    "usuario-a",
    chave(),
  );
  exigir(aberto === token, "round-trip alterou o token");
});

Deno.test("dados associados impedem trocar o token de dono", async () => {
  const cifrado = await cifrarTokenAppleComChave(
    "refresh-token-sintetico-com-tamanho-valido",
    "usuario-a",
    chave(),
    new Uint8Array(12),
  );
  await exigirRejeicao(() =>
    decifrarTokenAppleComChave(cifrado, "usuario-b", chave())
  );
});

Deno.test("chave errada e versao errada falham fechadas", async () => {
  const cifrado = await cifrarTokenAppleComChave(
    "refresh-token-sintetico-com-tamanho-valido",
    "usuario-a",
    chave(),
    new Uint8Array(12),
  );
  await exigirRejeicao(() =>
    decifrarTokenAppleComChave(cifrado, "usuario-a", chave(1, 17))
  );
  await exigirRejeicao(() =>
    decifrarTokenAppleComChave(cifrado, "usuario-a", chave(2))
  );
});

Deno.test("rotacao recifra com versao nova sem alterar o token", async () => {
  const token = "refresh-token-sintetico-com-tamanho-valido";
  const antiga = await cifrarTokenAppleComChave(
    token,
    "usuario-a",
    chave(1, 7),
  );
  const aberto = await decifrarTokenAppleComChave(
    antiga,
    "usuario-a",
    chave(1, 7),
  );
  const nova = await cifrarTokenAppleComChave(
    aberto,
    "usuario-a",
    chave(2, 19),
  );
  exigir(nova.versao_chave === 2, "versao da rotacao nao mudou");
  exigir(
    nova.refresh_token_cifrado !== antiga.refresh_token_cifrado,
    "rotacao manteve o mesmo texto cifrado",
  );
  exigir(
    await decifrarTokenAppleComChave(nova, "usuario-a", chave(2, 19)) === token,
    "rotacao alterou o token",
  );
  await exigirRejeicao(() =>
    decifrarTokenAppleComChave(nova, "usuario-a", chave(1, 7))
  );
});

Deno.test("nonce aleatorio produz textos diferentes para o mesmo token", async () => {
  const token = "refresh-token-sintetico-com-tamanho-valido";
  const primeiro = await cifrarTokenAppleComChave(token, "usuario-a", chave());
  const segundo = await cifrarTokenAppleComChave(token, "usuario-a", chave());
  exigir(
    primeiro.nonce_cifragem !== segundo.nonce_cifragem,
    "nonce foi reutilizado",
  );
  exigir(
    primeiro.refresh_token_cifrado !== segundo.refresh_token_cifrado,
    "texto cifrado repetiu com nonce diferente",
  );
});

Deno.test("linha legada so e aceita como transicao", async () => {
  const legado = "refresh-token-legado-com-tamanho-valido";
  exigir(
    await recuperarTokenApple({ refresh_token: legado }, "usuario-a") ===
      legado,
    "linha A50 deixou de ser legivel durante a transicao",
  );
  await exigirRejeicao(() => recuperarTokenApple({}, "usuario-a"));
});

Deno.test("recuperacao escolhe a chave gravada e falha se ela sumiu", async () => {
  const token = "refresh-token-sintetico-com-tamanho-valido";
  const cifrado = await cifrarTokenAppleComChave(
    token,
    "usuario-a",
    chave(2, 19),
  );
  let versaoSolicitada = 0;
  const aberto = await recuperarTokenApple(cifrado, "usuario-a", (versao) => {
    versaoSolicitada = versao;
    return chave(versao, 19);
  });
  exigir(
    aberto === token && versaoSolicitada === 2,
    "nao escolheu a chave da linha",
  );
  await exigirRejeicao(() =>
    recuperarTokenApple(cifrado, "usuario-a", () => {
      throw new ConfiguracaoDeTokenAppleInvalida("missing_key");
    })
  );
});

Deno.test("tamanhos invalidos sao recusados antes da cifra", async () => {
  await exigirRejeicao(() =>
    cifrarTokenAppleComChave("curto", "usuario-a", chave())
  );
  await exigirRejeicao(() =>
    cifrarTokenAppleComChave(
      "refresh-token-sintetico-com-tamanho-valido",
      "usuario-a",
      { versao: 1, material: new Uint8Array(31) },
    )
  );
  await exigirRejeicao(() =>
    cifrarTokenAppleComChave(
      "refresh-token-sintetico-com-tamanho-valido",
      "usuario-a",
      chave(),
      new Uint8Array(11),
    )
  );
  exigir(
    new ConfiguracaoDeTokenAppleInvalida("x") instanceof Error,
    "erro nao e tipado",
  );
});
