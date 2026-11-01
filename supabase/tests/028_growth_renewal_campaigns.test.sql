-- Tests pgTAP du LOT 18 : renouvellement, activité, conversion, notifications ciblées.
begin;
select plan(15);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');

-- Alice : forfait STARTER payé, qui se termine dans 2 jours et demi
insert into public.payments (id, user_id, provider, transaction_id, kind, plan_code, period, amount_xof, status, paid_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'ligdicash', 'T1',
        'subscription', 'STARTER', 'monthly', 2000, 'succeeded', now() - interval '27 days');
insert into public.subscriptions (user_id, plan_code, period_start, period_end, source, payment_id)
values ('11111111-1111-1111-1111-111111111111', 'STARTER', now() - interval '27 days', now() + interval '60 hours',
        'payment', 'bbbbbbbb-0000-0000-0000-000000000001');

select is(app_private.notify_renewals(), 1, '1. rappel 3 jours avant la fin');
select is((select route from public.notifications where kind = 'billing'), '/abonnement?renouveler=STARTER&periode=monthly',
          '2. renouvellement en un geste (forfait et durée)');
select is(app_private.notify_renewals(), 1, '3. relancé…');
select is((select count(*)::int from public.notifications where kind = 'billing'), 1, '4. … sans doublon');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.my_renewal() ->> 'plan_code', 'STARTER', '5. forfait à renouveler');
select lives_ok($$ select public.touch_activity() $$, '6. activité du jour notée');
select lives_ok($$ select public.touch_activity() $$, '7. une fois par jour');
select throws_ok($$ select public.admin_growth(30) $$, '42501', null, '8. conversion réservée');
select throws_ok($$ select public.admin_send_campaign('all', 'Titre', 'Message', '/accueil') $$, '42501', null,
                 '9. envoi réservé au super administrateur');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select ok((public.admin_growth(30) -> 'funnel' ->> 'signed_up')::int >= 3, '10. entonnoir : inscrits');
select is((public.admin_growth(30) -> 'funnel' ->> 'first_purchase')::int, 1, '11. entonnoir : premier achat');
select is(public.admin_campaign_audience('paying'), 1, '12. segment « forfait payant »');
select throws_ok($$ select public.admin_send_campaign('all', 'Gain assuré ce soir', 'Venez voir', '/accueil') $$,
                 '22023', null, '13. mots interdits refusés');
select throws_ok($$ select public.admin_send_campaign('all', 'Nouveautés', 'Venez voir', 'https://exemple.com') $$,
                 '22023', null, '14. destination libre refusée');
select is(public.admin_send_campaign('expiring', 'Votre forfait', 'Pensez à le renouveler', '/abonnement'), 1,
          '15. envoi au segment « se termine sous 7 jours »');
reset role;

select * from finish();
rollback;
