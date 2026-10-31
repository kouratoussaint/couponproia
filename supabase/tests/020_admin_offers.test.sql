-- Tests pgTAP : forfait et pack de crédits offerts par l'équipe, sans paiement.
begin;
select plan(12);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'super_admin');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ select public.admin_grant_credit_pack('22222222-2222-2222-2222-222222222222', 1, 'moi') $$,
                 '42501', null, '1. un utilisateur ne s''offre pas de pack');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ select public.admin_grant_credit_pack('22222222-2222-2222-2222-222222222222', 0, 'x') $$, '22023', null, '2. au moins un pack');
select throws_ok($$ select public.admin_grant_credit_pack('22222222-2222-2222-2222-222222222222', 2, ' ') $$, '22023', null, '3. motif obligatoire');
select is((public.admin_grant_credit_pack('22222222-2222-2222-2222-222222222222', 2, 'Partenaire') ->> 'credits')::int, 20,
          '4. 2 packs = 20 crédits (contenu lu par le serveur)');
select lives_ok($$ select public.admin_grant_subscription('22222222-2222-2222-2222-222222222222', 'PRO_TIPSTER', 3, 'Partenaire') $$,
                '5. forfait attribué sans paiement');
select lives_ok($$ select public.admin_set_setting('legal.editor', '{"name": "Coupon Pro IA SARL", "country": "Burkina Faso"}') $$,
                '9. identité de l''éditeur enregistrée');
select throws_ok($$ select public.admin_set_setting('legal.editor', '{"nom": "X"}') $$, '22023', null, '10. champ inconnu refusé');
select lives_ok($$ select public.admin_set_setting('app.support_email', '"contact@couponproia.com"') $$, '11. e-mail du support enregistré');
select throws_ok($$ select public.admin_set_setting('app.support_email', '"pas-un-email"') $$, '22023', null, '12. e-mail invalide refusé');
reset role;

select is((select extra_credits from public.credit_accounts where user_id = '22222222-2222-2222-2222-222222222222'), 20,
          '6. crédits supplémentaires ajoutés');
select is(app_private.plan_of('22222222-2222-2222-2222-222222222222'), 'PRO_TIPSTER', '7. forfait actif');
select is((select count(*)::int from public.audit_logs where action in ('credits.grant_pack', 'subscription.grant')), 2,
          '8. les deux gestes sont journalisés');

select * from finish();
rollback;
