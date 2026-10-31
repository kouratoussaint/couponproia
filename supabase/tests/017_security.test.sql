-- Tests pgTAP du LOT 12 : règles de sécurité structurelles, vérifiées sur toute la base.
begin;
select plan(8);

select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 0,
          '1. RLS activée sur toutes les tables publiques');

select is((select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'app_private') and p.prosecdef
             and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')), null,
          '2. toute fonction SECURITY DEFINER fixe son search_path');

select is((select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
             -- outils de test (pgTAP ou son substitut local) exclus
             and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
             and p.proname not in ('plan', 'ok', 'is', 'isnt', 'lives_ok', 'throws_ok', 'finish', 'diag', 'pass', 'fail')), null,
          '3. aucune fonction publique appelable sans connexion');

select is((select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app_private' and has_function_privilege('authenticated', p.oid, 'execute')
             and (p.prorettype = 'trigger'::regtype
                  or p.proname in ('refresh_plan_credits', 'credit_summary', 'active_subscription', 'credits_exempt',
                                   'notify', 'promo_check', 'bootstrap_super_admin', 'handle_new_user')
                  or p.proname like 'invoke\_%')), null,
          '4. fonctions internes sensibles fermées aux utilisateurs');

select is((select string_agg(distinct table_name || ':' || privilege_type, ', ') from information_schema.role_table_grants
           where grantee in ('anon', 'authenticated') and table_schema = 'public'
             and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')), null,
          '5. aucun droit TRUNCATE, REFERENCES ou TRIGGER pour l''API');

select is((select string_agg(distinct table_name, ', ') from information_schema.role_table_grants
           where grantee = 'anon' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')), null,
          '6. un visiteur ne peut rien écrire');

select is((select count(*)::int from pg_constraint c join pg_namespace n on n.oid = c.connamespace
           where c.contype = 'f' and n.nspname = 'public'
             and not exists (select 1 from pg_index i where i.indrelid = c.conrelid
                             and (string_to_array(i.indkey::text, ' ')::int2[])[1:cardinality(c.conkey)] = c.conkey)), 0,
          '7. toutes les clés étrangères sont indexées');

select ok((select bool_and(pg_get_functiondef('app_private.invoke_sports_sync(text)'::regprocedure) like '%''' || j || '''%')
           from unnest(array['daily', 'odds', 'live', 'matchday']) j),
          '8. toutes les tâches planifiées de synchronisation sont autorisées');

select * from finish();
rollback;
