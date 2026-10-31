-- Tests pgTAP du LOT 12 (coûts) : accès, calculs, contrôle des réglages de coûts.
begin;
select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');

insert into public.ai_requests (user_id, kind, model, status, cost_usd)
values ('22222222-2222-2222-2222-222222222222', 'match_analysis', 'm', 'success', 0.01);
insert into public.payments (user_id, provider, transaction_id, kind, credits, amount_xof, status)
values ('22222222-2222-2222-2222-222222222222', 'cinetpay', 'C1', 'credits', 10, 2000, 'succeeded');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ select public.admin_costs(30) $$, '42501', null, '1. coûts refusés à un utilisateur');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_setting('costs.fixed_monthly_xof', '{"Supabase": 15000}') $$, '2. abonnement fixe enregistré');
select lives_ok($$ select public.admin_set_setting('costs.payment_fee_percent', '2') $$, '3. commission enregistrée');
select throws_ok($$ select public.admin_set_setting('costs.payment_fee_percent', '35') $$, '22023', null, '4. commission plafonnée');
select throws_ok($$ select public.admin_set_setting('costs.fixed_monthly_xof', '{"Supabase": "beaucoup"}') $$, '22023', null,
                 '5. montant non numérique refusé');
select throws_ok($$ select public.admin_set_setting('costs.usd_to_xof', '0') $$, '22023', null, '6. taux nul refusé');

select is((public.admin_costs(30) -> 'ai' ->> 'cost_xof')::numeric, 6::numeric, '7. coût IA converti (0,01 USD × 600)');
select is((public.admin_costs(30) ->> 'total_xof')::numeric, (6 + 15000 + 40)::numeric, '8. total : IA + fixes + commissions');
select is((public.admin_costs(30) ->> 'per_active_user_xof')::numeric, (6 + 15000 + 40)::numeric, '9. coût par utilisateur actif (Bob, actif par son analyse)');
reset role;

select * from finish();
rollback;
