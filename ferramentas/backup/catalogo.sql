-- Catálogo estrutural canônico usado pelo ensaio de backup/restauração.
-- Execute com psql -X -qAt -v ON_ERROR_STOP=1 -f catalogo.sql.
--
-- A consulta é somente leitura e devolve exatamente um JSONB. OIDs não entram
-- na saída. ACLs são expandidas e ordenadas por nomes para que origem e
-- restauração possam ser comparadas mesmo quando seus OIDs forem diferentes.
-- Objetos pertencentes a extensões são excluídos: as extensões são verificadas
-- separadamente pelo bootstrap de backup_nativo.mjs.

with
escopo(schema_name) as (
  values ('public'::name), ('auth'::name), ('storage'::name),
         ('supabase_migrations'::name)
),
relacoes_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_class'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
funcoes_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
tipos_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_type'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
constraints_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_constraint'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
triggers_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_trigger'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
politicas_extensao as materialized (
  select d.objid
  from pg_catalog.pg_depend d
  where d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
    and d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
    and d.deptype = 'e'
),
schemas_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'name', n.nspname,
      'owner', pg_catalog.pg_get_userbyid(n.nspowner),
      'acl', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantor', pg_catalog.pg_get_userbyid(a.grantor),
            'grantee', case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            a.privilege_type, a.is_grantable,
            pg_catalog.pg_get_userbyid(a.grantor)
        )
        from pg_catalog.aclexplode(coalesce(
          n.nspacl, pg_catalog.acldefault('n'::"char", n.nspowner)
        )) a
      ), '[]'::jsonb)
    ) order by n.nspname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_namespace n
  join escopo s on s.schema_name = n.nspname
),
relacoes_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'name', c.relname,
      'kind', case c.relkind
        when 'r' then 'table'
        when 'p' then 'partitioned_table'
        when 'm' then 'materialized_view'
        when 'v' then 'view'
        when 'S' then 'sequence'
      end,
      'owner', pg_catalog.pg_get_userbyid(c.relowner),
      'persistence', c.relpersistence,
      'row_security', c.relrowsecurity,
      'force_row_security', c.relforcerowsecurity,
      'replica_identity', c.relreplident,
      'partition_key', case when c.relkind = 'p'
        then pg_catalog.pg_get_partkeydef(c.oid) end,
      'options', coalesce((
        select pg_catalog.jsonb_agg(x.option order by x.option)
        from pg_catalog.unnest(coalesce(c.reloptions, '{}'::text[])) x(option)
      ), '[]'::jsonb),
      'acl', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantor', pg_catalog.pg_get_userbyid(a.grantor),
            'grantee', case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            a.privilege_type, a.is_grantable,
            pg_catalog.pg_get_userbyid(a.grantor)
        )
        from pg_catalog.aclexplode(coalesce(
          c.relacl,
          pg_catalog.acldefault(
            (case when c.relkind = 'S' then 'S' else 'r' end)::"char",
            c.relowner
          )
        )) a
      ), '[]'::jsonb),
      'columns', case when c.relkind <> 'S' then coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'position', att.attnum,
            'name', att.attname,
            'type', pg_catalog.format_type(att.atttypid, att.atttypmod),
            'type_schema', tn.nspname,
            'nullable', not att.attnotnull,
            'default', pg_catalog.pg_get_expr(ad.adbin, ad.adrelid),
            'identity', nullif(att.attidentity, ''),
            'generated', nullif(att.attgenerated, ''),
            'collation', case when att.attcollation <> typ.typcollation then
              cn.nspname || '.' || coll.collname end,
            'acl', coalesce((
              select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                  'grantor', pg_catalog.pg_get_userbyid(ca.grantor),
                  'grantee', case when ca.grantee = 0 then 'PUBLIC'
                    else pg_catalog.pg_get_userbyid(ca.grantee) end,
                  'privilege', ca.privilege_type,
                  'grantable', ca.is_grantable
                ) order by
                  case when ca.grantee = 0 then 'PUBLIC'
                    else pg_catalog.pg_get_userbyid(ca.grantee) end,
                  ca.privilege_type, ca.is_grantable,
                  pg_catalog.pg_get_userbyid(ca.grantor)
              )
              from pg_catalog.aclexplode(att.attacl) ca
            ), '[]'::jsonb)
          ) order by att.attnum
        )
        from pg_catalog.pg_attribute att
        join pg_catalog.pg_type typ on typ.oid = att.atttypid
        join pg_catalog.pg_namespace tn on tn.oid = typ.typnamespace
        left join pg_catalog.pg_attrdef ad
          on ad.adrelid = att.attrelid and ad.adnum = att.attnum
        left join pg_catalog.pg_collation coll on coll.oid = att.attcollation
        left join pg_catalog.pg_namespace cn on cn.oid = coll.collnamespace
        where att.attrelid = c.oid
          and att.attnum > 0
          and not att.attisdropped
      ), '[]'::jsonb) end,
      'sequence', case when c.relkind = 'S' then (
        select pg_catalog.jsonb_build_object(
          'data_type', pg_catalog.format_type(seq.seqtypid, null),
          'start', seq.seqstart,
          'increment', seq.seqincrement,
          'minimum', seq.seqmin,
          'maximum', seq.seqmax,
          'cache', seq.seqcache,
          'cycle', seq.seqcycle
        ) from pg_catalog.pg_sequence seq where seq.seqrelid = c.oid
      ) end
    ) order by n.nspname, c.relname, c.relkind
  ), '[]'::jsonb) as value
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join escopo s on s.schema_name = n.nspname
  where c.relkind in ('r', 'p', 'm', 'v', 'S')
    and not exists (
      select 1 from relacoes_extensao x where x.objid = c.oid
    )
),
tipos_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'name', t.typname,
      'owner', pg_catalog.pg_get_userbyid(t.typowner),
      'kind', case t.typtype
        when 'e' then 'enum'
        when 'd' then 'domain'
        when 'c' then 'composite'
        when 'r' then 'range'
        when 'm' then 'multirange'
      end,
      'enum_labels', case when t.typtype = 'e' then coalesce((
        select pg_catalog.jsonb_agg(en.enumlabel order by en.enumsortorder)
        from pg_catalog.pg_enum en where en.enumtypid = t.oid
      ), '[]'::jsonb) end,
      'base_type', case when t.typtype = 'd'
        then pg_catalog.format_type(t.typbasetype, t.typtypmod) end,
      'not_null', case when t.typtype = 'd' then t.typnotnull end,
      'default', case when t.typtype = 'd' then t.typdefault end,
      'range_subtype', case when t.typtype in ('r', 'm') then (
        select pg_catalog.format_type(r.rngsubtype, null)
        from pg_catalog.pg_range r
        where r.rngtypid = t.oid or r.rngmultitypid = t.oid
      ) end,
      'constraints', case when t.typtype = 'd' then coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', con.conname,
            'definition', pg_catalog.pg_get_constraintdef(con.oid, false),
            'validated', con.convalidated
          ) order by con.conname
        )
        from pg_catalog.pg_constraint con
        where con.contypid = t.oid
          and not exists (
            select 1 from constraints_extensao x where x.objid = con.oid
          )
      ), '[]'::jsonb) end,
      'attributes', case when t.typtype = 'c' then coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'position', a.attnum,
            'name', a.attname,
            'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull
          ) order by a.attnum
        )
        from pg_catalog.pg_attribute a
        where a.attrelid = t.typrelid and a.attnum > 0 and not a.attisdropped
      ), '[]'::jsonb) end,
      'acl', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantor', pg_catalog.pg_get_userbyid(a.grantor),
            'grantee', case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            a.privilege_type, a.is_grantable,
            pg_catalog.pg_get_userbyid(a.grantor)
        )
        from pg_catalog.aclexplode(coalesce(
          t.typacl, pg_catalog.acldefault('T'::"char", t.typowner)
        )) a
      ), '[]'::jsonb)
    ) order by n.nspname, t.typname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_type t
  join pg_catalog.pg_namespace n on n.oid = t.typnamespace
  join escopo s on s.schema_name = n.nspname
  left join pg_catalog.pg_class cr on cr.oid = t.typrelid
  where (t.typtype in ('e', 'd', 'r', 'm')
         or (t.typtype = 'c' and cr.relkind = 'c'))
    and not exists (
      select 1 from tipos_extensao x where x.objid = t.oid
    )
),
constraints_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'relation', c.relname,
      'name', con.conname,
      'type', con.contype,
      'definition', pg_catalog.pg_get_constraintdef(con.oid, false),
      'deferrable', con.condeferrable,
      'initially_deferred', con.condeferred,
      'validated', con.convalidated,
      'no_inherit', con.connoinherit
    ) order by n.nspname, c.relname, con.conname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class c on c.oid = con.conrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join escopo s on s.schema_name = n.nspname
  where not exists (
      select 1 from constraints_extensao x where x.objid = con.oid
    )
    and not exists (
      select 1 from relacoes_extensao x where x.objid = c.oid
    )
),
indices_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'relation', tab.relname,
      'name', idx.relname,
      'owner', pg_catalog.pg_get_userbyid(idx.relowner),
      'definition', pg_catalog.pg_get_indexdef(idx.oid),
      'unique', i.indisunique,
      'primary', i.indisprimary,
      'exclusion', i.indisexclusion,
      'valid', i.indisvalid,
      'ready', i.indisready,
      'live', i.indislive,
      'nulls_not_distinct', i.indnullsnotdistinct,
      'options', coalesce((
        select pg_catalog.jsonb_agg(x.option order by x.option)
        from pg_catalog.unnest(coalesce(idx.reloptions, '{}'::text[])) x(option)
      ), '[]'::jsonb)
    ) order by n.nspname, tab.relname, idx.relname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_index i
  join pg_catalog.pg_class idx on idx.oid = i.indexrelid
  join pg_catalog.pg_class tab on tab.oid = i.indrelid
  join pg_catalog.pg_namespace n on n.oid = tab.relnamespace
  join escopo s on s.schema_name = n.nspname
  where not exists (
      select 1 from relacoes_extensao x where x.objid = idx.oid
    )
    and not exists (
      select 1 from relacoes_extensao x where x.objid = tab.oid
    )
),
views_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'name', c.relname,
      'kind', case c.relkind when 'v' then 'view' else 'materialized_view' end,
      'definition', pg_catalog.pg_get_viewdef(c.oid, false),
      'populated', case when c.relkind = 'm' then c.relispopulated end
    ) order by n.nspname, c.relname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join escopo s on s.schema_name = n.nspname
  where c.relkind in ('v', 'm')
    and not exists (
      select 1 from relacoes_extensao x where x.objid = c.oid
    )
),
funcoes_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'name', p.proname,
      'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
      'kind', case p.prokind when 'f' then 'function' else 'procedure' end,
      'owner', pg_catalog.pg_get_userbyid(p.proowner),
      'security_definer', p.prosecdef,
      'leakproof', p.proleakproof,
      'strict', p.proisstrict,
      'volatility', p.provolatile,
      'parallel', p.proparallel,
      'config', coalesce((
        select pg_catalog.jsonb_agg(x.setting order by x.setting)
        from pg_catalog.unnest(coalesce(p.proconfig, '{}'::text[])) x(setting)
      ), '[]'::jsonb),
      'acl', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantor', pg_catalog.pg_get_userbyid(a.grantor),
            'grantee', case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            a.privilege_type, a.is_grantable,
            pg_catalog.pg_get_userbyid(a.grantor)
        )
        from pg_catalog.aclexplode(coalesce(
          p.proacl, pg_catalog.acldefault('f'::"char", p.proowner)
        )) a
      ), '[]'::jsonb),
      'definition', pg_catalog.pg_get_functiondef(p.oid)
    ) order by n.nspname, p.proname,
               pg_catalog.pg_get_function_identity_arguments(p.oid)
  ), '[]'::jsonb) as value
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  join escopo s on s.schema_name = n.nspname
  where p.prokind in ('f', 'p')
    and not exists (
      select 1 from funcoes_extensao x where x.objid = p.oid
    )
),
politicas_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'relation', c.relname,
      'name', p.polname,
      'permissive', p.polpermissive,
      'command', p.polcmd,
      'roles', coalesce((
        select pg_catalog.jsonb_agg(x.role_name order by x.role_name)
        from (
          select case when u.role_oid = 0 then 'PUBLIC'
            else pg_catalog.pg_get_userbyid(u.role_oid) end as role_name
          from pg_catalog.unnest(p.polroles) u(role_oid)
        ) x
      ), '[]'::jsonb),
      'using', pg_catalog.pg_get_expr(p.polqual, p.polrelid),
      'with_check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
    ) order by n.nspname, c.relname, p.polname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_policy p
  join pg_catalog.pg_class c on c.oid = p.polrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join escopo s on s.schema_name = n.nspname
  where not exists (
      select 1 from politicas_extensao x where x.objid = p.oid
    )
    and not exists (
      select 1 from relacoes_extensao x where x.objid = c.oid
    )
),
triggers_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'schema', n.nspname,
      'relation', c.relname,
      'name', t.tgname,
      'enabled', t.tgenabled,
      'function_schema', fn.nspname,
      'function', f.proname,
      'function_arguments', pg_catalog.pg_get_function_identity_arguments(f.oid),
      'definition', pg_catalog.pg_get_triggerdef(t.oid, false)
    ) order by n.nspname, c.relname, t.tgname
  ), '[]'::jsonb) as value
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join escopo s on s.schema_name = n.nspname
  join pg_catalog.pg_proc f on f.oid = t.tgfoid
  join pg_catalog.pg_namespace fn on fn.oid = f.pronamespace
  where not t.tgisinternal
    and not exists (
      select 1 from triggers_extensao x where x.objid = t.oid
    )
    and not exists (
      select 1 from relacoes_extensao x where x.objid = c.oid
    )
),
default_acl_catalogo as (
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(d.defaclrole),
      'schema', n.nspname,
      'object_type', d.defaclobjtype,
      'acl', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantor', pg_catalog.pg_get_userbyid(a.grantor),
            'grantee', case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            'privilege', a.privilege_type,
            'grantable', a.is_grantable
          ) order by
            case when a.grantee = 0 then 'PUBLIC'
              else pg_catalog.pg_get_userbyid(a.grantee) end,
            a.privilege_type, a.is_grantable,
            pg_catalog.pg_get_userbyid(a.grantor)
        ) from pg_catalog.aclexplode(d.defaclacl) a
      ), '[]'::jsonb)
    ) order by pg_catalog.pg_get_userbyid(d.defaclrole), n.nspname,
               d.defaclobjtype
  ), '[]'::jsonb) as value
  from pg_catalog.pg_default_acl d
  left join pg_catalog.pg_namespace n on n.oid = d.defaclnamespace
  where d.defaclnamespace = 0
     or n.nspname in (select schema_name from escopo)
)
select pg_catalog.jsonb_build_object(
  'schemas', (select value from schemas_catalogo),
  'relations', (select value from relacoes_catalogo),
  'types', (select value from tipos_catalogo),
  'constraints', (select value from constraints_catalogo),
  'indexes', (select value from indices_catalogo),
  'views', (select value from views_catalogo),
  'functions', (select value from funcoes_catalogo),
  'policies', (select value from politicas_catalogo),
  'triggers', (select value from triggers_catalogo),
  'default_acl', (select value from default_acl_catalogo)
) as catalogo;
