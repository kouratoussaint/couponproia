-- Tests pgTAP du LOT 5 : crédits (dotation, débit unique après succès, solde insuffisant,
-- exemption de l'équipe, expiration mensuelle, ajustement admin) et confidentialité de l'assistant.
begin;
select plan(18);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Données DE TEST (transaction annulée)
insert into public.assistant_conversations (id, user_id, title) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Alice'),
  ('cccccccc-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Bob');
insert into public.assistant_messages (conversation_id, user_id, role, content) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'user', 'Bonjour'),
  ('cccccccc-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'user', 'Salut');
insert into public.user_coupons (id, user_id, title, total_odd, combined_probability, risk_level, engine_version, fingerprint) values
  ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Proposition', 3.1, 0.3, 'equilibre', 'v', 'fp');

-- 1-8 : crédits (rôle service)
set local role service_role;
select is((public.svc_credit_summary('11111111-1111-1111-1111-111111111111') ->> 'total')::int, 2, 'forfait FREE : 2 crédits par mois');
select is((public.svc_consume_credits('11111111-1111-1111-1111-111111111111', 'eeeeeeee-0000-0000-0000-000000000001', 1, 'assistant') ->> 'total')::int,
          1, 'débit après succès');
select is((public.svc_consume_credits('11111111-1111-1111-1111-111111111111', 'eeeeeeee-0000-0000-0000-000000000001', 1, 'assistant') ->> 'already_charged')::boolean,
          true, 'même opération : pas de second débit');
select is((select count(*)::int from public.credit_ledger where reason = 'consume' and user_id = '11111111-1111-1111-1111-111111111111'), 1,
          'un seul débit journalisé');
select throws_ok($$ select public.svc_consume_credits('11111111-1111-1111-1111-111111111111', 'eeeeeeee-0000-0000-0000-000000000002', 2, 'assistant') $$,
                 'P0001', null, 'solde insuffisant : refus');
select is((public.svc_credit_summary('11111111-1111-1111-1111-111111111111') ->> 'total')::int, 1, 'refus sans débit partiel');
select is((public.svc_consume_credits('33333333-3333-3333-3333-333333333333', 'eeeeeeee-0000-0000-0000-000000000003', 1, 'assistant') ->> 'charged')::int,
          0, 'équipe : opération journalisée sans débit');
update public.credit_accounts set plan_period = '2000-01' where user_id = '11111111-1111-1111-1111-111111111111';
select is((public.svc_credit_summary('11111111-1111-1111-1111-111111111111') ->> 'plan_credits')::int, 2,
          'nouveau mois : dotation renouvelée, reliquat expiré');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 9-16 : utilisatrice
select is((public.my_credits() ->> 'total')::int, 2, 'my_credits : son solde');
select throws_ok($$ select public.svc_consume_credits('11111111-1111-1111-1111-111111111111', gen_random_uuid(), 1, 'x') $$,
                 '42501', null, 'un utilisateur ne peut pas se débiter ni se créditer');
select throws_ok($$ select public.admin_adjust_credits('11111111-1111-1111-1111-111111111111', 100, 'cadeau') $$,
                 '42501', null, 'ajustement réservé aux gestionnaires');
select ok((select count(*) from public.credit_ledger) >= 3 and
          not exists (select 1 from public.credit_ledger where user_id <> '11111111-1111-1111-1111-111111111111'),
          'ne voit que son journal de crédits');
select is((select count(*)::int from public.assistant_conversations), 1, 'ne voit que ses conversations');
select is((select count(*)::int from public.assistant_messages), 1, 'ne voit que ses messages');
select throws_ok($$ insert into public.assistant_messages (conversation_id, user_id, role, content)
                    values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'assistant', 'faux') $$,
                 '42501', null, 'ne peut pas écrire de message à la place de l''assistant');
update public.user_coupons set status = 'saved' where id = 'dddddddd-0000-0000-0000-000000000001';
select is((select status from public.user_coupons where id = 'dddddddd-0000-0000-0000-000000000001'), 'saved', 'enregistre sa proposition');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
-- 17-18 : administrateur
select is((public.admin_adjust_credits('11111111-1111-1111-1111-111111111111', 10, 'Testeuse') ->> 'extra_credits')::int, 10,
          'ajustement admin : crédits supplémentaires');
select is((select count(*)::int from public.user_coupons), 0, 'les coupons personnels restent privés, même pour un admin');

reset role;
select * from finish();
rollback;
