-- Tests pgTAP : coût en crédits du laboratoire (réglage public, borné dans la console).
begin;
select plan(7);

insert into auth.users (id, email, raw_user_meta_data) values
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');

select is((select value from public.app_settings where key = 'lab.credit_cost'), '1'::jsonb,
  'laboratoire : 1 crédit par calcul par défaut');
select ok((select is_public from public.app_settings where key = 'lab.credit_cost'),
  'coût du laboratoire lisible par l''app');

set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_setting('lab.credit_cost', '2'::jsonb) $$, 'coût réglable dans la console');
select lives_ok($$ select public.admin_set_setting('lab.credit_cost', '0'::jsonb) $$, 'laboratoire gratuit possible');
select throws_ok($$ select public.admin_set_setting('lab.credit_cost', '1.5'::jsonb) $$, '22023', null,
  'coût entier seulement');
select throws_ok($$ select public.admin_set_setting('analysis.credit_cost', '51'::jsonb) $$, '22023', null,
  'coût de l''analyse plafonné à 50');
select throws_ok($$ select public.admin_set_setting('assistant.cost_per_action', '0'::jsonb) $$, '22023', null,
  'assistant : au moins 1 crédit');

select * from finish();
rollback;
