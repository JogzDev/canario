/**
 * Concorrência real entre duas conexões `datadrobe_lab_writer`.
 *
 * POR QUE ISTO EXISTE
 * ===================
 *
 * O `teste_admissao.sql` roda numa sessão só. Ele prova que chamar a admissão
 * duas vezes seguidas devolve o mesmo recibo — e não prova nada sobre duas
 * chamadas AO MESMO TEMPO, que é o caso que acontece de verdade quando um job
 * é reexecutado antes de o anterior terminar. Idempotência sequencial e
 * idempotência concorrente são propriedades diferentes: a primeira sai de um
 * `select` antes do `insert`, a segunda exige que o banco serialize as duas
 * transações. A lacuna 8 da própria blueprint diz isso com todas as letras:
 * *"testes estáticos de SQL não demonstram transações, permissões ou
 * concorrência"*.
 *
 * Este harness é a parte que faltava do P1. Ele NÃO repete o que o SQL já
 * cobre; ele exercita exatamente o que uma sessão só não alcança.
 *
 * A ORDEM IMPORTA, E ELA É DELIBERADA
 * ===================================
 *
 * 1. **Antes** da suíte, com o banco limpo: duas escritas simultâneas do mesmo
 *    manifesto. A segunda tem de FICAR BLOQUEADA na trava consultiva enquanto a
 *    primeira estiver aberta. As duas terminam em `rollback`, e o banco
 *    continua vazio — é isso que permite a suíte SQL seguir afirmando
 *    "exatamente um recibo".
 * 2. A suíte SQL inteira (`executar_testes_admissao_v1`).
 * 3. **Depois** dela, com um recibo já commitado: duas escritas simultâneas do
 *    mesmo manifesto devolvem `reused` e nenhum recibo novo nasce.
 * 4. Uma transação interrompida no meio (conexão derrubada sem commit) não
 *    deixa linha nenhuma para trás.
 *
 * Nada aqui usa `sleep` para decidir se algo bloqueou: o teste consulta
 * `pg_locks` e espera a trava aparecer como NÃO concedida. Espera por tempo é
 * como um teste de concorrência vira intermitente e, depois, ignorado.
 */

/** Espera até que exista uma trava consultiva pendente, sem dormir às cegas. */
async function esperarTravaPendente(admin, tetoMs = 5000) {
  const limite = Date.now() + tetoMs;
  for (;;) {
    const { rows } = await admin.query(
      "select count(*)::int as n from pg_locks where locktype = 'advisory' and not granted");
    if (rows[0].n > 0) return;
    if (Date.now() > limite) {
      throw new Error('a segunda escrita não bloqueou: a admissão não serializa');
    }
    await new Promise(resolve => setTimeout(resolve, 25));
  }
}

async function contarLinhas(admin) {
  const { rows } = await admin.query(`
    select
      (select count(*) from lab_radar.recibos_admissao)  as recibos,
      (select count(*) from public.execucoes_de_pesquisa) as execucoes,
      (select count(*) from public.itens_de_fonte)        as itens,
      (select count(*) from public.evidencias_de_sinal)   as evidencias,
      (select count(*) from public.leituras_de_mercado)   as leituras`);
  const linha = rows[0];
  return Object.fromEntries(
    Object.entries(linha).map(([chave, valor]) => [chave, Number(valor)]));
}

function exigir(condicao, nome) {
  if (!condicao) throw new Error(`lab_concurrency_failed:${nome}`);
}

const ADMITIR = 'select lab_radar.admitir_etiqueta_v1($1::jsonb) as recibo';

export async function executar({ admin, fixture, connectWriter }) {
  if (!fixture || typeof fixture !== 'object' || !fixture.manifest) {
    throw new Error('o harness precisa da fixture com o manifesto');
  }
  const manifesto = JSON.stringify(fixture.manifest);
  const checagens = [];

  const vazio = await contarLinhas(admin);
  exigir(Object.values(vazio).every(n => n === 0),
         'banco_comeca_vazio');

  // ---------------------------------------------------------------------
  // 1. Duas escritas simultâneas antes de existir qualquer recibo.
  // ---------------------------------------------------------------------
  const primeira = await connectWriter();
  const segunda = await connectWriter();
  try {
    await primeira.query('begin');
    await segunda.query('begin');

    const resultadoA = await primeira.query(ADMITIR, [manifesto]);
    exigir(resultadoA.rows[0].recibo.outcome === 'created',
           'primeira_escrita_cria');

    // A segunda entra AGORA, com a primeira ainda aberta. Ela não pode
    // devolver nada até a primeira terminar: se devolvesse, duas evidências
    // nasceriam do mesmo fato, que é a duplicação que a identidade lógica
    // existe para impedir.
    let segundaTerminou = false;
    const pendente = segunda.query(ADMITIR, [manifesto])
      .then(r => { segundaTerminou = true; return r; });
    await esperarTravaPendente(admin);
    exigir(!segundaTerminou, 'segunda_escrita_fica_bloqueada');
    checagens.push('escrita concorrente serializa na trava consultiva');

    // A primeira desiste. A segunda destrava e, como nada foi commitado,
    // ela é quem cria — provando que a transação abortada não deixou
    // resíduo nem "reservou" a identidade lógica.
    await primeira.query('rollback');
    const resultadoB = await pendente;
    exigir(resultadoB.rows[0].recibo.outcome === 'created',
           'rollback_da_primeira_libera_a_segunda');
    checagens.push('transação abortada não reserva identidade lógica');

    await segunda.query('rollback');
    const depois = await contarLinhas(admin);
    exigir(Object.values(depois).every(n => n === 0),
           'duas_transacoes_abortadas_nao_deixam_linha');
    checagens.push('duas transações abortadas deixam o banco intacto');
  } finally {
    await Promise.allSettled([primeira.end(), segunda.end()]);
  }

  // ---------------------------------------------------------------------
  // 1b. Escalada de privilégio, testada de onde ela seria tentada.
  // ---------------------------------------------------------------------
  //
  // Este caso morava no `teste_admissao.sql` e não podia falhar lá: o
  // PostgreSQL decide `SET ROLE` pelo `session_user`, e a sessão daquele
  // arquivo é a do administrador. `set local role datadrobe_lab_writer` troca
  // o papel corrente e deixa o `session_user` superusuário — então
  // `set role service_role` respondia SUCESSO e a suíte acusava o próprio
  // arranjo. Aqui a conexão É do escritor, e a pergunta finalmente é a certa.
  const escalador = await connectWriter();
  try {
    const { rows: quem } = await escalador.query(
      'select session_user as sessao, current_user as corrente');
    exigir(quem[0].sessao === 'datadrobe_lab_writer'
           && quem[0].corrente === 'datadrobe_lab_writer',
           'a_sessao_e_mesmo_do_escritor');
    for (const papel of ['service_role', 'datadrobe_lab_owner',
                         'datadrobe_lab_bootstrap']) {
      let subiu = false;
      try {
        await escalador.query(`set role ${papel}`);
        subiu = true;
      } catch (erro) {
        exigir(/permission denied|não é membro|is not a member/i.test(erro.message),
               `set_role_${papel}_negado_pelo_motivo_certo`);
      }
      exigir(!subiu, `escalada_para_${papel}_negada`);
    }
    checagens.push('escalada_por_set_role_negada');
  } finally {
    await escalador.end();
  }

  // ---------------------------------------------------------------------
  // 2. A suíte SQL inteira, com o banco no estado em que ela espera.
  // ---------------------------------------------------------------------
  const suite = await admin.query(
    'select lab_radar.executar_testes_admissao_v1($1::jsonb) as resultado',
    [JSON.stringify(fixture)]);
  const resultadoDaSuite = suite.rows[0].resultado;
  exigir(resultadoDaSuite.status === 'passed', 'suite_sql_passa');
  exigir(resultadoDaSuite.synthetic === true, 'suite_declara_sintetico');
  checagens.push(...resultadoDaSuite.checks);

  const comRecibo = await contarLinhas(admin);
  exigir(comRecibo.recibos === 1 && comRecibo.itens === 1
         && comRecibo.evidencias === 1 && comRecibo.leituras === 1
         && comRecibo.execucoes === 3, 'passagem_unica_com_cardinalidade_um');

  // ---------------------------------------------------------------------
  // 3. Agora COM recibo commitado: reexecução concorrente não duplica.
  // ---------------------------------------------------------------------
  const terceira = await connectWriter();
  const quarta = await connectWriter();
  try {
    const [a, b] = await Promise.all([
      terceira.query(ADMITIR, [manifesto]),
      quarta.query(ADMITIR, [manifesto]),
    ]);
    exigir(a.rows[0].recibo.outcome === 'reused'
           && b.rows[0].recibo.outcome === 'reused',
           'reexecucao_concorrente_reaproveita');
    // O mesmo recibo, campo a campo. E NÃO se compara `receipt_id` com a
    // contagem de recibos: sequência `generated always as identity` não volta
    // no rollback, então as duas transações abortadas do passo 1 já gastaram
    // números. O recibo é o de número 3 com apenas um recibo na tabela, e isso
    // está certo — id de sequência conta tentativas, não linhas.
    exigir(a.rows[0].recibo.receipt_id === b.rows[0].recibo.receipt_id,
           'reexecucao_concorrente_devolve_o_mesmo_recibo');
    exigir(JSON.stringify(a.rows[0].recibo) === JSON.stringify(b.rows[0].recibo),
           'reexecucao_concorrente_devolve_o_mesmo_conteudo');
    const aindaUm = await contarLinhas(admin);
    exigir(aindaUm.recibos === 1 && aindaUm.evidencias === 1
           && aindaUm.leituras === 1 && aindaUm.itens === 1,
           'reexecucao_concorrente_nao_duplica_nada');
    checagens.push('reexecução concorrente devolve o recibo existente');
  } finally {
    await Promise.allSettled([terceira.end(), quarta.end()]);
  }

  // ---------------------------------------------------------------------
  // 4. Conexão derrubada no meio da transação.
  // ---------------------------------------------------------------------
  // Uma identidade nova, ancorada pelo administrador: é assim que o processo
  // real funciona — o escritor restrito nunca cria a própria âncora.
  const outro = {
    ...fixture.manifest,
    manifest_id: 'c'.repeat(63) + '1',
    logical_key: 'c'.repeat(63) + '2',
    fact_id: 'c'.repeat(63) + '3',
    source_item_external_id: 'lab:interrupcao:0002',
  };
  await admin.query('select lab_radar.registrar_manifesto_v1($1::jsonb)',
                    [JSON.stringify(outro)]);
  const interrompida = await connectWriter();
  await interrompida.query('begin');
  const criada = await interrompida.query(ADMITIR, [JSON.stringify(outro)]);
  exigir(criada.rows[0].recibo.outcome === 'created', 'interrompida_criou_em_memoria');
  // Derruba a conexão sem commit. O PostgreSQL aborta a transação aberta.
  await interrompida.end();

  const depoisDaQueda = await contarLinhas(admin);
  exigir(depoisDaQueda.recibos === comRecibo.recibos
         && depoisDaQueda.itens === comRecibo.itens
         && depoisDaQueda.evidencias === comRecibo.evidencias
         && depoisDaQueda.leituras === comRecibo.leituras
         && depoisDaQueda.execucoes === comRecibo.execucoes,
         'conexao_derrubada_nao_deixa_linha');
  checagens.push('conexão derrubada no meio da transação não deixa linha');

  // A publicação continua fechada para todo mundo: a passagem inteira é
  // privada por construção, e este é o último portão antes de alguém supor
  // que "o P1 passou" significa "há leitura publicável".
  const { rows: publicadas } = await admin.query(
    "select count(*)::int as n from public.leituras_de_mercado where status <> 'draft'");
  exigir(publicadas[0].n === 0, 'nada_foi_publicado');
  checagens.push('nenhuma leitura saiu de draft');

  process.stdout.write(`${JSON.stringify({
    harness: 'teste_concorrencia',
    synthetic: true,
    checks: checagens,
  }, null, 2)}\n`);
}
