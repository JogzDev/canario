-- A49 — a ordem das cores da peça salva, explícita.
--
-- POR QUE UMA COLUNA E NÃO A ORDEM DE `termo_ids`
-- ===============================================
-- `termo_ids` é `text[]`, e array do Postgres preserva ordem. Guardar a
-- prioridade ali sairia de graça: nenhuma coluna, nenhuma migration.
--
-- E é exatamente por isso que não foi feito assim. A ordem viraria significado
-- **escondido** dentro de uma lista que todo o resto do sistema trata como
-- conjunto — um `sorted()` inocente em qualquer ponto do caminho apagaria a
-- prioridade sem quebrar teste, sem erro e sem ninguém ver. Este projeto já
-- perdeu tardes com defeito silencioso; contrato implícito em lista é fábrica
-- deles.
--
-- Decisão do JP em 27/08, e ele tem uma razão que vai além da robustez: a
-- ordem tende a sair da tela e virar dado do motor. Saber que a peça é
-- **principalmente preta com um detalhe verde** é diferente de saber que ela
-- tem preto e verde — e é essa diferença que impede uma busca por verde de
-- devolver uma peça 80% rosa. Dado que vai alimentar cálculo não mora numa
-- convenção de ordenação; mora numa coluna com nome.
--
-- O QUE ELA ACEITA
-- ================
-- No máximo três ids, que é o mesmo teto que o prompt da Luna já impõe
-- (`maxItems: 3` em `colors`) e o que o JP fixou para a interface. A primeira
-- posição é a cor principal.
--
-- A coluna é anulável de propósito: peça criada antes desta migração, ou
-- sincronizada de um aparelho com app antigo, chega sem ordem — e a tela sabe
-- **não desenhar número** nesse caso, em vez de inventar uma ordem a partir da
-- taxonomia. Número errado sobre uma cor é pior que número nenhum.

begin;

alter table public.closet_items
  add column if not exists cores_prioridade text[];

-- Três, não mais. O teto vive aqui também, e não só no app: a checagem do
-- cliente protege quem usa a interface, e esta protege a tabela de qualquer
-- outro caminho que um dia escreva nela.
alter table public.closet_items
  drop constraint if exists closet_ordem_de_cor_limitada;
alter table public.closet_items
  add constraint closet_ordem_de_cor_limitada check (
    cores_prioridade is null or cardinality(cores_prioridade) <= 3
  );

-- A ordem descreve cores que a peça declara ter. Uma prioridade apontando
-- para um id que não está em `termo_ids` seria uma peça dizendo que sua cor
-- principal é uma cor que ela não tem.
alter table public.closet_items
  drop constraint if exists closet_ordem_de_cor_dentro_dos_termos;
alter table public.closet_items
  add constraint closet_ordem_de_cor_dentro_dos_termos check (
    cores_prioridade is null
    or termo_ids is null
    or cores_prioridade <@ termo_ids
  );

comment on column public.closet_items.cores_prioridade is
  'Cores da peça em ordem de prioridade; a primeira é a principal. Subconjunto ordenado de termo_ids, no máximo três (A49).';

-- A coluna sozinha não bastaria: o upsert do Closet passa por
-- `aplicar_mudancas_closet`, que lê o lote com `jsonb_to_recordset` e uma
-- lista de campos NOMEADA. Chave que não está nessa lista é ignorada em
-- silêncio -- então, sem esta parte, o app mandaria a ordem, a chamada
-- responderia sucesso e a coluna ficaria eternamente nula. É a pior forma de
-- falhar: a que parece ter funcionado.
create or replace function public.aplicar_mudancas_closet(p_mudancas jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if jsonb_typeof(coalesce(p_mudancas, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_mudancas, '[]'::jsonb)) > 250 then
        raise exception 'closet_batch_too_large';
    end if;

    delete from public.closet_items
    where user_id = auth.uid()
      and removido_em < now() - interval '180 days';

    insert into public.closet_items (
        user_id, id, apelido, termo_ids, cores_prioridade, preco_alvo, canal,
        criada_em, favorita, similares_rejeitados, miniatura_hash,
        miniatura_extensao, atualizado_em, removido_em
    )
    select
        auth.uid(), x.id, x.apelido, x.termo_ids, x.cores_prioridade,
        x.preco_alvo, x.canal, x.criada_em, x.favorita, x.similares_rejeitados,
        x.miniatura_hash, x.miniatura_extensao,
        x.atualizado_em, x.removido_em
    from jsonb_to_recordset(coalesce(p_mudancas, '[]'::jsonb)) as x(
        id uuid, apelido text, termo_ids text[], cores_prioridade text[],
        preco_alvo numeric, canal text, criada_em timestamptz,
        favorita boolean, similares_rejeitados boolean, miniatura_hash text,
        miniatura_extensao text, atualizado_em timestamptz,
        removido_em timestamptz
    )
    on conflict (user_id, id) do update set
        apelido = excluded.apelido,
        termo_ids = excluded.termo_ids,
        cores_prioridade = excluded.cores_prioridade,
        preco_alvo = excluded.preco_alvo,
        canal = excluded.canal,
        criada_em = excluded.criada_em,
        favorita = excluded.favorita,
        similares_rejeitados = excluded.similares_rejeitados,
        miniatura_hash = excluded.miniatura_hash,
        miniatura_extensao = excluded.miniatura_extensao,
        atualizado_em = excluded.atualizado_em,
        removido_em = excluded.removido_em
    where excluded.atualizado_em > closet_items.atualizado_em
       or (
           excluded.atualizado_em = closet_items.atualizado_em
           and excluded.miniatura_hash is distinct from closet_items.miniatura_hash
       );

    if (select count(*) from public.closet_items
        where user_id = auth.uid() and removido_em is null) > 200 then
        raise exception 'closet_active_item_limit';
    end if;
    if (select count(*) from public.closet_items
        where user_id = auth.uid()) > 400 then
        raise exception 'closet_total_item_limit';
    end if;
end;
$$;

revoke all on function public.aplicar_mudancas_closet(jsonb) from public, anon;
grant execute on function public.aplicar_mudancas_closet(jsonb) to authenticated;

commit;
