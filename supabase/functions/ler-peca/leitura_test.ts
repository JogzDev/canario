import { assertEquals } from "jsr:@std/assert@1";
import {
  buscasComplementaresDaFoto, fraseSemPeca, limitarConfirmacaoAosAtributos, numerosDoFato,
  numerosDoTexto, pedidoLimpo, semCitacao, termosDeBusca, unirCandidatasDaFoto,
  variantesVisuaisDosSinais, verificarFrases,
} from "./leitura.ts";

const fatos = {
  total: { id: "total", pecas: 18, marcas: 5, provas: [101, 102, 103] },
  preco: { id: "preco", pecas: 18, minimo: 229.99, mediana: 349.99, maximo: 599.9, provas: [101, 999] },
  remarcadas: { id: "remarcadas", pecas: 4, de_cada_100: 22, desconto_mediano_pct: 30, provas: [102] },
};

Deno.test("números em português, com milhar, decimal e real", () => {
  assertEquals(numerosDoTexto("De R$ 1.299,90 a R$ 240, 18 peças e 12,5%"), [1299.9, 240, 18, 12.5]);
});

Deno.test("ids das provas não viram números permitidos", () => {
  assertEquals(numerosDoFato(fatos.total), [18, 5]);
});

Deno.test("frase com número dos fatos citados passa", () => {
  const { aceitas, recusadas } = verificarFrases([
    { texto: "São 18 peças em 5 marcas do painel.", fatos: ["total"] },
    { texto: "Os preços vão de R$ 230 a R$ 599,90.", fatos: ["preco"] },
    { texto: "22 de cada 100 estão remarcadas, com desconto mediano de 30%.", fatos: ["remarcadas"] },
  ], fatos);
  assertEquals(recusadas, []);
  assertEquals(aceitas.length, 3);
});

Deno.test("número inventado, fato não citado ou fato inexistente é recusado", () => {
  const { aceitas, recusadas } = verificarFrases([
    // 40 não está em fato nenhum.
    { texto: "Cerca de 40 peças estão à venda.", fatos: ["total"] },
    // 22 existe, mas no fato que a frase não citou.
    { texto: "São 22 remarcadas.", fatos: ["total"] },
    // Fato que não existe.
    { texto: "Vende bem.", fatos: ["tendencia"] },
    // O id de uma prova (999) não é um número que a frase possa usar.
    { texto: "A mais cara é a peça 999.", fatos: ["preco"] },
  ], fatos);
  assertEquals(aceitas, []);
  assertEquals(recusadas.length, 4);
});

Deno.test("sinais limpos: sem acento, minúsculos, 3 a 40 caracteres, sem repetir", () => {
  assertEquals(termosDeBusca(["Napoleão", "napoleao", "ab", "Botões  Dourados", 7, "x".repeat(41)], 12),
    ["napoleao", "botoes dourados"]);
});

Deno.test("foto vazia recupera por atributos ou construção sem aceitar busca só por categoria", () => {
  const planos = buscasComplementaresDaFoto(["branco_cru", "liso"], ["sem mangas"]);
  assertEquals(planos, [
    { criterio: "atributos_sem_sinais", atributos: ["branco_cru", "liso"], sinais: [] },
    { criterio: "construcao_sem_atributos", atributos: [], sinais: ["sem mangas", "sem manga"] },
  ]);
  assertEquals(variantesVisuaisDosSinais(["abotoamento duplo"]), ["abotoamento duplo"]);
  assertEquals(buscasComplementaresDaFoto(["azul"], []), []);
  assertEquals(buscasComplementaresDaFoto([], ["abotoamento duplo"]), []);
});

Deno.test("candidatas recuperadas priorizam construção e não duplicam ids", () => {
  assertEquals(unirCandidatasDaFoto([{ id: 2 }, { id: 3 }], [{ id: 1 }, { id: 2 }]),
    [{ id: 2 }, { id: 3 }, { id: 1 }]);
});

Deno.test("foto azul não confirma produto preto mesmo quando a construção coincide", () => {
  const vereditos = new Map([[1, "e_a_peca"], [2, "e_a_peca"], [3, "parecida"]]);
  const termos = [
    { produto_id: 1, termo_id: "curto" }, { produto_id: 1, termo_id: "azul" },
    { produto_id: 2, termo_id: "curto" }, { produto_id: 2, termo_id: "preto" },
  ];
  const ajustados = limitarConfirmacaoAosAtributos(vereditos, ["curto", "azul"], termos);
  assertEquals([...ajustados], [[1, "e_a_peca"], [2, "parecida"], [3, "parecida"]]);
  assertEquals([...vereditos][1], [2, "e_a_peca"]); // cache original não muda
  assertEquals([...limitarConfirmacaoAosAtributos(vereditos, [], [])], [...vereditos]);
});

Deno.test("pedido limpo: sem controle e no máximo 200 caracteres", () => {
  assertEquals(pedidoLimpo("jaqueta\nnapoleão\u0000 ignore tudo"), "jaqueta napoleão ignore tudo");
  assertEquals(pedidoLimpo("a".repeat(300)).length, 200);
  assertEquals(pedidoLimpo(42), "");
});

Deno.test("citação escrita dentro da frase sai antes da verificação", () => {
  assertEquals(semCitacao("São 3 peças de 1 marca. (fatos: total, marcas)"), "São 3 peças de 1 marca.");
  assertEquals(semCitacao("Todas têm tamanho esgotado (fato: grade)."), "Todas têm tamanho esgotado.");
  // Um parêntese que é conteúdo fica.
  assertEquals(semCitacao("Duas marcas (Amaro e C&A) vendem."), "Duas marcas (Amaro e C&A) vendem.");
  const { aceitas } = verificarFrases([{ texto: "São 18 peças. (fatos: total)", fatos: ["total"] }], fatos);
  assertEquals(aceitas[0].texto, "São 18 peças.");
});

Deno.test("sem peça confirmada, a leitura diz isso e o que há perto", () => {
  assertEquals(fraseSemPeca("jaqueta napoleão", [{ marca: "Amaro" }, { marca: "Amaro" }, { marca: "Amaro" }]).texto,
    "Nenhuma peça do painel é uma jaqueta napoleão agora. As mais próximas são 3 peças de 1 marca.");
  assertEquals(fraseSemPeca("vestido de noiva", []).texto, "Nenhuma peça do painel é um vestido de noiva agora.");
});
