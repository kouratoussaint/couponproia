-- Tests pgTAP du LOT 1 : création des profils, RLS, privilèges de colonnes,
-- RPC d'administration. Lancer avec `supabase test db` (ou scripts/local-db/test.sh).
begin;
select plan(30);

-- Comptes de test -------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"display_name": "Alice"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local',   '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '{"display_name": "Admin"}'),
  ('44444444-4444-4444-4444-444444444444', 'root@test.local',  '{"display_name": "Root"}');

-- 1-4 : création automatique à l'inscription
select is((select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
          'Alice', 'profil créé avec le nom choisi');
select is((select display_name from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
          'bob', 'nom par défaut = début de l''email');
select ok(exists (select 1 from public.user_roles
                  where user_id = '11111111-1111-1111-1111-111111111111' and role_id = 'user'),
          'rôle user attribué à l''inscription');
select is((select theme_mode from public.user_preferences where user_id = '11111111-1111-1111-1111-111111111111'),
          'system', 'préférences créées avec le thème système');

select app_private.bootstrap_super_admin('root@test.local');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Utilisateur ordinaire : Alice -------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

-- 5-10 : lecture limitée à ses propres données
select is((select count(*)::int from public.profiles), 1, 'Alice ne voit que son profil');
select is((select count(*)::int from public.user_roles), 1, 'Alice ne voit que ses rôles');
select is((select count(*)::int from public.user_preferences), 1, 'Alice ne voit que ses préférences');
select is((select count(*)::int from public.audit_logs), 0, 'Alice ne voit pas le journal d''audit');
select is((select count(*)::int from public.app_settings where not is_public), 0, 'réglages privés invisibles');
select is((select count(*)::int from public.my_permissions()), 0, 'Alice n''a aucune permission');

-- 11-14 : écritures autorisées ou non sur son profil
select lives_ok($$ update public.profiles set display_name = 'Alice B'
                   where id = '11111111-1111-1111-1111-111111111111' $$,
                'Alice modifie son nom');
select throws_ok($$ update public.profiles set is_suspended = false
                    where id = '11111111-1111-1111-1111-111111111111' $$,
                 '42501', null, 'colonne is_suspended non modifiable par l''utilisateur');
select lives_ok($$ update public.user_preferences set theme_mode = 'dark'
                   where user_id = '11111111-1111-1111-1111-111111111111' $$,
                'Alice change son thème');
select throws_ok($$ update public.user_preferences set theme_mode = 'rose'
                    where user_id = '11111111-1111-1111-1111-111111111111' $$,
                 '23514', null, 'valeur de thème invalide refusée');

-- tentative de modifier le profil de Bob : filtrée par la RLS (vérifiée plus bas)
update public.profiles set display_name = 'Pirate' where id = '22222222-2222-2222-2222-222222222222';

-- 15-18 : escalade de privilèges impossible
select throws_ok($$ insert into public.user_roles (user_id, role_id)
                    values ('11111111-1111-1111-1111-111111111111', 'admin') $$,
                 '42501', null, 'Alice ne peut pas s''attribuer un rôle');
select throws_ok($$ select public.admin_set_user_role('11111111-1111-1111-1111-111111111111', 'admin', true) $$,
                 '42501', null, 'RPC de rôle refusée sans permission');
select throws_ok($$ update public.feature_flags set enabled = true where key = 'assistant_ia' $$,
                 '42501', null, 'flags non modifiables directement');
select throws_ok($$ select public.admin_set_feature_flag('assistant_ia', true) $$,
                 '42501', null, 'RPC de flag refusée sans permission');

-- Administrateur ---------------------------------------------------------------
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';

-- 19-24
select is((select count(*)::int from public.profiles), 4, 'l''admin voit tous les profils');
select lives_ok($$ select public.admin_set_user_role('22222222-2222-2222-2222-222222222222', 'tipster', true) $$,
                'l''admin attribue le rôle tipster');
select throws_ok($$ select public.admin_set_user_role('22222222-2222-2222-2222-222222222222', 'admin', true) $$,
                 '42501', null, 'l''admin ne peut pas nommer un administrateur');
select lives_ok($$ select public.admin_set_feature_flag('maintenance_mode', true) $$,
                'l''admin bascule un flag');
select is((select count(*)::int from public.audit_logs where actor_id = '33333333-3333-3333-3333-333333333333'),
          2, 'les deux actions de l''admin sont auditées');
select throws_ok($$ select public.admin_set_user_suspended('44444444-4444-4444-4444-444444444444', true) $$,
                 '42501', null, 'l''admin ne peut pas suspendre un super administrateur');

-- Super administrateur ---------------------------------------------------------
set local request.jwt.claims = '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';

-- 25-26
select lives_ok($$ select public.admin_set_user_role('22222222-2222-2222-2222-222222222222', 'admin', true) $$,
                'le super admin nomme un administrateur');
select lives_ok($$ select public.admin_set_user_suspended('33333333-3333-3333-3333-333333333333', true) $$,
                'le super admin suspend un administrateur');

-- 27 : un compte suspendu perd toutes ses permissions
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.my_permissions()), 0, 'admin suspendu : plus aucune permission');

-- Visiteur non connecté --------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '';

-- 28-29
select ok((select count(*) from public.feature_flags) > 0, 'un visiteur lit les feature flags');
select throws_ok($$ select count(*) from public.profiles $$,
                 '42501', null, 'un visiteur ne lit pas les profils');

-- 30 : la tentative d'Alice sur le profil de Bob n'a rien changé
reset role;
select is((select display_name from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
          'bob', 'Alice n''a pas pu modifier le profil de Bob');

select * from finish();
rollback;
