-- Tests pgTAP : agrégateurs de paiement (ordre réglable, jeton LigdiCash non lisible).
begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');
insert into public.payments (user_id, provider, transaction_id, kind, credits, amount_xof, provider_ref)
values ('22222222-2222-2222-2222-222222222222', 'ligdicash', 'CPITEST1', 'credits', 10, 500, 'JETON-SECRET');

select is((select value from public.app_settings where key = 'payments.providers'), '["ligdicash", "cinetpay"]'::jsonb,
          '1. LigdiCash en priorité par défaut');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select status from public.payments where transaction_id = 'CPITEST1'), 'pending', '2. le client voit son paiement');
select throws_ok($$ select provider_ref from public.payments $$, '42501', null, '3. jeton de facture illisible');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_setting('payments.providers', '["cinetpay", "ligdicash"]') $$, '4. ordre modifiable');
select throws_ok($$ select public.admin_set_setting('payments.providers', '["ligdicash", "ligdicash"]') $$, '22023', null,
                 '5. doublon refusé');
select throws_ok($$ select public.admin_set_setting('payments.providers', '["paypal"]') $$, '22023', null,
                 '6. agrégateur inconnu refusé');
reset role;

select * from finish();
rollback;
