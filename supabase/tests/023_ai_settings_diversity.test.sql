-- Tests pgTAP : réglages IA réservés au super administrateur ; réglages de diversification.
begin;
select plan(8);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values
  ('11111111-1111-1111-1111-111111111111', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'super_admin');

select ok((select value = '0.7'::jsonb from public.app_settings where key = 'coupons.market_weight')
          and (select value = '2'::jsonb from public.app_settings where key = 'coupons.max_match_uses'),
          '1. mélange 30/70 et 2 coupons par match au plus par défaut');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ select public.admin_set_setting('ai.provider', '"groq"') $$, '42501', null,
                 '2. un administrateur ne change pas l''IA');
select throws_ok($$ select public.admin_set_setting('coupons.market_weight', '1.5') $$, '22023', null,
                 '3. part du marché bornée à 1');
select throws_ok($$ select public.admin_set_setting('coupons.max_match_uses', '2.5') $$, '22023', null,
                 '4. nombre entier de coupons');
select lives_ok($$ select public.admin_set_setting('coupons.market_weight', '0.6') $$, '5. réglage accepté');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_setting('ai.analysis_ttl_hours', '12') $$, '6. le super administrateur règle l''IA');
reset role;

select lives_ok($$ insert into public.ai_requests (kind, provider, model, status, quota)
                   values ('provider_test', 'groq', 'm', 'success', '{"requests_remaining": 990}') $$,
                '7. test de fournisseur journalisé avec son quota');
select ok((select value ? 'gemini' from public.app_settings where key = 'ai.models') is not false,
          '8. le modèle de la principale est conservé dans ai.models');

select * from finish();
rollback;
