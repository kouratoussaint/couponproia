-- Tests pgTAP du LOT 11 (3/3) : codes promo (contrôle, administration, comptage à l'exécution)
-- et remboursement enregistré (droits retirés, journal).
begin;
select plan(20);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ select public.admin_save_promo('BIENVENUE', 'x', 20, 'all', '{}', null, null, null, true) $$,
                 '42501', null, '1. création de code refusée à un utilisateur');
select throws_ok($$ select public.admin_refund_payment(gen_random_uuid(), 'x') $$, '42501', null, '2. remboursement refusé');
select is(public.check_promo('INCONNU', 'subscription', 'STARTER') ->> 'reason', 'unknown', '3. code inconnu');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.admin_save_promo('bienvenue', 'Offre de lancement', 20, 'subscription', '{STARTER}', null, null, 10, true) $$,
                '4. code créé (mis en majuscules)');
select throws_ok($$ select public.admin_save_promo('X', 'x', 20, 'all', '{}', null, null, null, true) $$, '22023', null, '5. code trop court');
select throws_ok($$ select public.admin_save_promo('TROP', 'x', 95, 'all', '{}', null, null, null, true) $$, '22023', null, '6. réduction plafonnée à 90 %');
select throws_ok($$ select public.admin_save_promo('PLAN', 'x', 10, 'subscription', '{FREE}', null, null, null, true) $$, '22023', null, '7. forfait gratuit refusé');
select lives_ok($$ select public.admin_save_promo('FINI', 'x', 10, 'all', '{}', now() - interval '2 days', now() - interval '1 day', null, true) $$,
                '8. code expiré enregistré');
select is((select count(*)::int from jsonb_array_elements(public.admin_promo_codes())), 2, '9. liste des codes');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((public.check_promo(' bienvenue ', 'subscription', 'STARTER') ->> 'percent_off')::int, 20, '10. code valable pour STARTER');
select is(public.check_promo('BIENVENUE', 'subscription', null) ->> 'reason', 'not_applicable', '11 bis. forfait absent : non applicable');
select is(public.check_promo('BIENVENUE', 'subscription', 'PRO_TIPSTER') ->> 'reason', 'not_applicable', '11. autre forfait : non applicable');
select is(public.check_promo('BIENVENUE', 'credits') ->> 'reason', 'not_applicable', '12. packs de crédits : non applicable');
select is(public.check_promo('FINI', 'credits') ->> 'reason', 'expired', '13. code expiré');
select is(public.check_promo('BIENVENUE') -> 'plan_codes', '["STARTER"]'::jsonb, '13 bis. contrôle d''affichage : portée renvoyée');
reset role;

-- Paiement confirmé avec le code, puis exécution (comme le ferait le serveur).
insert into public.payments (id, user_id, provider, transaction_id, kind, plan_code, period, amount_xof, status, promo_code, discount_xof)
values ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'cinetpay', 'P1',
        'subscription', 'STARTER', 'monthly', 1600, 'succeeded', 'BIENVENUE', 400);
insert into public.payments (id, user_id, provider, transaction_id, kind, credits, amount_xof, status)
values ('bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'cinetpay', 'P2', 'credits', 10, 500, 'succeeded');
select public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000001');
select public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000002');
select is((select uses from public.promo_codes where code = 'BIENVENUE'), 1, '14. utilisation comptée à l''exécution');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.check_promo('BIENVENUE', 'subscription', 'STARTER') ->> 'reason', 'already_used', '15. une seule fois par utilisateur');
select is(public.my_entitlements() ->> 'plan', 'STARTER', '16. forfait actif avant remboursement');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select public.admin_refund_payment('bbbbbbbb-0000-0000-0000-000000000001', 'Erreur de forfait');
select public.admin_refund_payment('bbbbbbbb-0000-0000-0000-000000000002', 'Double paiement');
select throws_ok($$ select public.admin_refund_payment('bbbbbbbb-0000-0000-0000-000000000002', 'Encore') $$, '22023', null,
                 '17. pas de double remboursement');
reset role;

select ok(
  (select status from public.payments where id = 'bbbbbbbb-0000-0000-0000-000000000001') = 'refunded'
  and app_private.plan_of('22222222-2222-2222-2222-222222222222') = 'FREE'
  and (select extra_credits from public.credit_accounts where user_id = '22222222-2222-2222-2222-222222222222') = 0
  and (select count(*) from public.audit_logs where action = 'payment.refund') = 2,
  '18. droits retirés (forfait, crédits) et remboursements journalisés');

select * from finish();
rollback;
