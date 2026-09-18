#!/usr/bin/env node
// Somente fixtures locais: valida SQL contra crypto/BigInt independentes do Node.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { digestTableSql, localCluster, SQL_DIGEST_METHOD } from './backup_nativo.mjs';

const bin = path.join(os.homedir(), '.local/share/datadrobe-tools/Postgres.app/Contents/Versions/17/bin');
const cluster = await localCluster(bin);
const table = {schema:'public',name:'fixture'};
const sqlModule = await readFile(new URL('./backup_nativo.mjs',import.meta.url),'utf8');

async function digestNode(name) {
  // O envelope hexadecimal evita que limites dos chunks UTF8 de stdout alterem
  // os bytes da fixture; o hash recebe o record UTF8 original, sem escapes COPY.
  const rows=(await cluster.exec(`SELECT encode(convert_to(r::text,'UTF8'),'hex') FROM ONLY public.${name} r;`)).trim();
  const hexRows=rows ? rows.split('\n') : [];
  const sums=[0n,0n,0n,0n], xors=[0n,0n,0n,0n];
  for(const hex of hexRows) {
    const hash=createHash('sha256').update(Buffer.from(hex,'hex')).digest('hex');
    for(let i=0;i<4;i++) {
      const part=BigInt.asIntN(64,BigInt('0x'+hash.slice(i*16,i*16+16)));
      sums[i]+=part; xors[i]^=part;
    }
  }
  return {method:SQL_DIGEST_METHOD,count:hexRows.length,sums:sums.map(String),xors:xors.map(String)};
}

try {
  await cluster.exec(`
    CREATE TABLE public.fixture (id integer, removida text, texto text, bytes bytea,
      j json, jb jsonb, numero numeric, criado_em timestamptz, vetor text[]);
    ALTER TABLE public.fixture DROP COLUMN removida;
    INSERT INTO public.fixture SELECT g, E'ação🎨\\nbarra\\\\tab\\t'||g, decode('00ff5c','hex'),
      '{ "a":1, "a":2 }', '{"z":3,"a":[null,1]}', 90071992547409931234567890.00001,
      '2020-01-02 03:04:05.123456+03', ARRAY['ç',NULL,'x'] FROM generate_series(1,3000) g;
    INSERT INTO public.fixture SELECT * FROM public.fixture WHERE id=1;
    INSERT INTO public.fixture VALUES (NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
    CREATE TABLE public.vazia (id integer, texto text);
  `);
  const expected=await digestNode('fixture');
  const actual=await digestTableSql(bin,cluster.c,table);
  assert.deepEqual(actual,expected);
  assert.ok(actual.sums.some(value=>BigInt(value)>BigInt(Number.MAX_SAFE_INTEGER) || BigInt(value)<BigInt(Number.MIN_SAFE_INTEGER)));
  assert.ok(actual.xors.some(value=>BigInt(value)<0n));
  assert.deepEqual(await digestTableSql(bin,cluster.c,{schema:'public',name:'vazia'}),await digestNode('vazia'));
  console.log(`ok 1: SHA256 SQL igual a crypto/BigInt Node em ${actual.count} linhas; precisão >53 bits, NULL, Unicode, escapes, bytea, json/jsonb, coluna excluída, duplicatas e vazio.`);

  await cluster.exec(`CREATE TYPE public.composto AS (texto text, numero integer);
    CREATE TABLE public.limites (j jsonb, a text[], c public.composto);
    INSERT INTO public.limites VALUES (NULL,ARRAY['a','b'],NULL);`);
  const edgeTable={schema:'public',name:'limites'};
  const beforeJsonNull=await digestTableSql(bin,cluster.c,edgeTable);
  await cluster.exec("UPDATE public.limites SET j='null'::jsonb;");
  const afterJsonNull=await digestTableSql(bin,cluster.c,edgeTable);
  assert.notDeepEqual(afterJsonNull,beforeJsonNull);
  assert.deepEqual(afterJsonNull,await digestNode('limites'));
  await cluster.exec("UPDATE public.limites SET a='[0:1]={a,b}'::text[];");
  const afterBounds=await digestTableSql(bin,cluster.c,edgeTable);
  assert.notDeepEqual(afterBounds,afterJsonNull);
  assert.deepEqual(afterBounds,await digestNode('limites'));
  await cluster.exec('UPDATE public.limites SET c=ROW(NULL,NULL)::public.composto;');
  const afterComposite=await digestTableSql(bin,cluster.c,edgeTable);
  assert.notDeepEqual(afterComposite,afterBounds);
  assert.deepEqual(afterComposite,await digestNode('limites'));
  console.log('ok 1b: record distingue SQL NULL de JSON null, limites de arrays e composite NULL de composite com campos NULL.');

  // Extrai apenas o gerador SQL para EXPLAIN local da consulta usada realmente.
  // O módulo permanece intacto, e a captura substitui somente o executor json.
  const start=sqlModule.indexOf('export async function digestTableSql(');
  const end=sqlModule.indexOf('\nexport async function verifyExisting(',start);
  assert.ok(start>=0 && end>start);
  const fn=sqlModule.slice(start,end).replace(/^export /,'');
  const captureSql=new Function('json','qid','lit','SQL_DIGEST_METHOD',`${fn}; return digestTableSql;`)(
    async (_bin,_c,query)=>query,
    s=>'"'+s.replaceAll('"','""')+'"',
    s=>"'"+s.replaceAll("'","''")+"'",
    SQL_DIGEST_METHOD,
  );
  const query=await captureSql(bin,cluster.c,table);
  const plan=JSON.parse(await cluster.exec(`SET work_mem='64kB'; SET temp_file_limit=0;
    SET max_parallel_workers_per_gather=0; EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) ${query}`));
  const nodes=[];
  const walk=node=>{nodes.push(node); for(const child of node.Plans||[])walk(child);};
  walk(plan[0].Plan);
  assert.ok(nodes.every(node=>!['Sort','Incremental Sort','Materialize','CTE Scan','Memoize'].includes(node['Node Type'])));
  assert.ok(nodes.every(node=>!node['Temp Read Blocks']&&!node['Temp Written Blocks']));
  console.log(`ok 2: plano ${nodes.map(node=>node['Node Type']).join(' → ')} sem sort/materialização/temp writes, work_mem=64kB e temp_file_limit=0; payload ${Buffer.byteLength(JSON.stringify(actual))} bytes.`);

  await cluster.exec("UPDATE public.fixture SET texto='alterada' WHERE id=2;");
  assert.notDeepEqual(await digestTableSql(bin,cluster.c,table),actual);
  assert.deepEqual(await digestTableSql(bin,cluster.c,table),await digestNode('fixture'));
  console.log('ok 3: uma linha alterada muda assinatura, mantendo equivalência com Node.');

  const utc=await cluster.exec("SET timezone='UTC'; SET bytea_output='hex'; SELECT encode(convert_to(r::text,'UTF8'),'hex') FROM public.fixture r WHERE id=2;");
  const otherZone=await cluster.exec("SET timezone='America/Sao_Paulo'; SET bytea_output='hex'; SELECT encode(convert_to(r::text,'UTF8'),'hex') FROM public.fixture r WHERE id=2;");
  const otherBytea=await cluster.exec("SET timezone='UTC'; SET bytea_output='escape'; SELECT encode(convert_to(r::text,'UTF8'),'hex') FROM public.fixture r WHERE id=2;");
  assert.notEqual(utc,otherZone);
  assert.notEqual(utc,otherBytea);
  console.log('ok 4: timezone e bytea_output afetam representação; sessões origem/restore precisam definições canônicas iguais.');
  console.log('ASSINATURA SQL VERDE — somente fixture local, sem produção.');
} finally { await cluster.close(); }
