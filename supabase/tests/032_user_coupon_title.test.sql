-- Tests pgTAP : renommer un de ses coupons (Mes coupons, 02/11).
begin;
select plan(5);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_coupons (id, user_id, status, title, total_odd, combined_probability, risk_level, engine_version, fingerprint)
values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'saved', 'Coupon manuel · 2 sélections',
        2, 0.5, 'prudent', 'v', 'fa');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ update public.user_coupons set title = '  Mon combiné du samedi ' where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  '1. renommer son coupon');
select is((select title from public.user_coupons where id = 'cccccccc-0000-0000-0000-000000000001'), 'Mon combiné du samedi',
  '2. espaces retirés');
select throws_ok($$ update public.user_coupons set title = ' ' where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  '22023', null, '3. nom vide refusé');
select throws_ok($$ update public.user_coupons set title = repeat('a', 81) where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  '22023', null, '4. 80 caractères au plus');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
update public.user_coupons set title = 'Pris' where id = 'cccccccc-0000-0000-0000-000000000001';
reset role;
select is((select title from public.user_coupons where id = 'cccccccc-0000-0000-0000-000000000001'), 'Mon combiné du samedi',
  '5. le coupon d''un autre reste intact');

select * from finish();
rollback;
