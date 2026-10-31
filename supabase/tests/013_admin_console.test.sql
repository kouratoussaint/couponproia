-- Tests pgTAP du LOT 11 (console) : permissions, tableau de bord, utilisateurs, réglages, journal.
begin;
select plan(14);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{"display_name": "Admin"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{"display_name": "Bob"}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ select public.admin_dashboard(7) $$, '42501', null, '1. tableau de bord refusé à un utilisateur');
select throws_ok($$ select public.admin_users() $$, '42501', null, '2. liste des utilisateurs refusée');
select throws_ok($$ select public.admin_set_setting('pricing.annual_discount_percent', '20') $$, '42501', null, '3. réglages refusés');
select is((public.my_admin_rights() ->> 'access')::boolean, false, '4. aucun droit d''administration');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok((public.admin_dashboard(7) -> 'users' ->> 'total')::int >= 2, '5. tableau de bord : utilisateurs comptés');
select is(jsonb_array_length(public.admin_dashboard(7) -> 'daily'), 7, '6. série quotidienne sur 7 jours');
select is((select count(*)::int from jsonb_array_elements(public.admin_users('bob'))), 1, '7. recherche par e-mail');
select is(public.admin_user_detail('22222222-2222-2222-2222-222222222222') ->> 'plan', 'FREE', '8. fiche utilisateur');
select lives_ok($$ select public.admin_set_setting('pricing.annual_discount_percent', '20') $$, '9. réglage modifié');
select throws_ok($$ select public.admin_set_setting('pricing.annual_discount_percent', '"vingt"') $$, '22023', null, '10. type contrôlé');
select throws_ok($$ select public.admin_set_setting('pricing.plans', '[{"code": "STARTER", "name": "S", "monthly_xof": 2000, "ai_credits": 10}]') $$,
                 '22023', null, '11. grille sans FREE refusée');
select throws_ok($$ select public.admin_set_setting('pricing.plans', '[{"code": "FREE", "name": "F", "monthly_xof": 0, "ai_credits": 2}, {"code": "STARTER", "name": "S", "monthly_xof": 2003, "ai_credits": 10}]') $$,
                 '22023', null, '12. prix non multiple de 5 refusé');
select is((select count(*)::int from jsonb_array_elements(public.admin_audit(10, 'settings.'))), 1, '13. modification journalisée');
select throws_ok($$ select public.admin_set_setting('cle.inconnue', '1') $$, 'P0002', null, '14. réglage inconnu refusé');
reset role;

select * from finish();
rollback;
