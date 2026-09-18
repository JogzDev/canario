#!/usr/bin/env node
// Testes unitários do diagnóstico: somente processos Node fictícios e arquivos temporários.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { run, resumirErro } from './backup_nativo.mjs';

const root = await mkdtemp(path.join(os.tmpdir(), 'dd-diagnostico-teste-'));
const node = process.execPath;
const segredoCopy = 'DADO_PRIVADO_COPY_FICTICIO_123';
const senhaFicticia = 'SENHA FICTICIA:@/?%';
const senhaCodificada = encodeURIComponent(senhaFicticia);

const lerJson = async file => JSON.parse(await readFile(file, 'utf8'));
const modo = async file => (await stat(file)).mode & 0o777;

try {
  const stderrCompleto = [
    'pg_dump: error: Dumping the contents of table "artigos" failed: PQgetCopyData() failed.',
    'pg_dump: detail: Error message from server: SSL connection has been closed unexpectedly.',
    'pg_dump: detail: Command was: COPY public.artigos (id, conteudo) TO stdout;',
    `CONTEXT: COPY artigos, line 42: "${segredoCopy}"`,
  ].join('\n');
  const resumo = resumirErro(stderrCompleto);
  assert.match(resumo, /conexão foi interrompida/i);
  assert.match(resumo, /transferência COPY não foi concluída/i);
  assert.doesNotMatch(resumo, /public\.artigos|line 42|DADO_PRIVADO|conteudo/i);
  console.log('ok 1: resumo considera todas as linhas e não expõe dados/SQL do COPY');

  const falhaLog = path.join(root, 'falha.json');
  let falha;
  try {
    await run(node, ['-e', String.raw`
      const senha = process.env.PGPASSWORD;
      process.stderr.write(${JSON.stringify(stderrCompleto + '\n')});
      process.stderr.write('senha=' + senha + '\n');
      process.stderr.write('senha_url=' + encodeURIComponent(senha) + '\n');
      process.stderr.write('uri=postgresql://postgres:' + encodeURIComponent(senha) + '@db.example.invalid:5432/postgres\n');
      process.exit(23);
    `], { env: { PGPASSWORD: senhaFicticia }, diagnosticsFile: falhaLog });
  } catch (error) { falha = error; }
  assert.ok(falha instanceof Error);
  assert.match(falha.message, /conexão foi interrompida/i);
  assert.match(falha.message, /transferência COPY não foi concluída/i);
  assert.match(falha.message, /Diagnóstico protegido:/);
  assert.doesNotMatch(falha.message, /public\.artigos|line 42|DADO_PRIVADO|SENHA FICTICIA/i);
  const falhaDiagnostico = await lerJson(falhaLog);
  assert.equal(await modo(falhaLog), 0o600);
  assert.equal(falhaDiagnostico.program, path.basename(node));
  assert.equal(falhaDiagnostico.exit_code, 23);
  assert.equal(falhaDiagnostico.signal, null);
  assert.equal(falhaDiagnostico.local_timeout, false);
  assert.equal(falhaDiagnostico.stderr_truncated, false);
  assert.match(falhaDiagnostico.stderr, /Command was: COPY public\.artigos/);
  assert.match(falhaDiagnostico.stderr, new RegExp(segredoCopy));
  assert.match(falhaDiagnostico.stderr, /\[credencial redigida\]/);
  assert.doesNotMatch(falhaDiagnostico.stderr, new RegExp(senhaFicticia.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(falhaDiagnostico.stderr, new RegExp(senhaCodificada.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(falhaDiagnostico.stderr, /postgresql:\/\/postgres:[^@\s]+@/);
  console.log('ok 2: log 0600 preserva contexto multilinha e redige senha fictícia crua/codificada/URI');

  const timeoutLog = path.join(root, 'timeout.json');
  await assert.rejects(
    run(node, ['-e', "process.on('SIGTERM', () => process.exit(0)); setInterval(() => {}, 1000)"],
      { timeout: 300, diagnosticsFile: timeoutLog }),
    error => {
      assert.match(error.message, /Limite local de 0\.3s atingido; processo interrompido/);
      assert.doesNotMatch(error.message, /statement_timeout|transação|servidor cancelou/i);
      return true;
    },
  );
  const timeoutDiagnostico = await lerJson(timeoutLog);
  assert.equal(timeoutDiagnostico.local_timeout, true);
  assert.equal(timeoutDiagnostico.exit_code, 0);
  assert.equal(timeoutDiagnostico.signal, null);
  assert.equal(await modo(timeoutLog), 0o600);
  console.log('ok 3: timeout local continua sendo falha mesmo quando o filho sai com código zero');

  const sigkillLog = path.join(root, 'sigkill.json');
  await assert.rejects(
    run(node, ['-e', String.raw`
      process.on('SIGTERM', () => process.stderr.write('SIGTERM fictício ignorado\n'));
      setInterval(() => {}, 1000);
    `], { timeout: 300, diagnosticsFile: sigkillLog }),
    error => {
      assert.match(error.message, /Limite local de 0\.3s atingido; processo interrompido/);
      return true;
    },
  );
  const sigkillDiagnostico = await lerJson(sigkillLog);
  assert.equal(sigkillDiagnostico.local_timeout, true);
  assert.equal(sigkillDiagnostico.exit_code, null);
  assert.equal(sigkillDiagnostico.signal, 'SIGKILL');
  assert.equal(sigkillDiagnostico.stderr, 'SIGTERM fictício ignorado\n');
  assert.equal(await modo(sigkillLog), 0o600);
  console.log('ok 3b: filho que ignora SIGTERM é encerrado por SIGKILL e diagnosticado');

  const sucessoLog = path.join(root, 'sucesso.json');
  const stdout = await run(node, ['-e', String.raw`
    process.stdout.write('resultado-ficticio');
    process.stderr.write('aviso ficticio preservado\n');
  `], { diagnosticsFile: sucessoLog });
  assert.equal(stdout, 'resultado-ficticio');
  const sucessoDiagnostico = await lerJson(sucessoLog);
  assert.equal(sucessoDiagnostico.exit_code, 0);
  assert.equal(sucessoDiagnostico.signal, null);
  assert.equal(sucessoDiagnostico.local_timeout, false);
  assert.equal(sucessoDiagnostico.stderr, 'aviso ficticio preservado\n');
  assert.equal(await modo(sucessoLog), 0o600);
  console.log('ok 4: execução bem-sucedida retorna stdout e também grava diagnóstico 0600');

  const spawnLog = path.join(root, 'spawn.json');
  await assert.rejects(
    run(path.join(root, 'programa-que-nao-existe'), [], { diagnosticsFile: spawnLog }),
    error => {
      assert.equal(error.code, 'ENOENT');
      assert.match(error.message, /spawn .*programa-que-nao-existe ENOENT/);
      return true;
    },
  );
  // Ler imediatamente após a rejeição prova que não há gravação tardia.
  const spawnDiagnostico = await lerJson(spawnLog);
  assert.equal(spawnDiagnostico.program, 'programa-que-nao-existe');
  assert.equal(spawnDiagnostico.spawn_error_code, 'ENOENT');
  assert.equal(spawnDiagnostico.local_timeout, false);
  assert.equal(spawnDiagnostico.stderr, '');
  assert.equal(await modo(spawnLog), 0o600);
  console.log('ok 5: falha de spawn rejeita com ENOENT e o log 0600 já está disponível');

  console.log('DIAGNÓSTICO VERDE — somente processos e credenciais fictícios.');
} finally {
  await rm(root, { recursive: true, force: true });
}
