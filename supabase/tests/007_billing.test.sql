-- Tests pgTAP du LOT 9 : accès aux coupons selon le forfait, exécution unique d'un paiement
-- confirmé (abonnement, crédits), dotation qui suit le forfait, confidentialité des paiements.
begin;
select plan(15);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');

-- Données DE TEST (transaction annulée)
insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Du jour', 'd', 'equilibre', 3, 0.3, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Prudent à venir', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f2'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'prudent', 'Prudent passé', 'd', 'prudent', 2, 0.5, 'published', now() - interval '3 days',
   now() - interval '3 days', now() - interval '2 days', now() - interval '2 days', 'v', 'f3');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select c.id, 1, m.id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.6, 'bonne', 'j'
from public.coupons c, public.matches m where m.provider_ref = 'm1';

insert into public.payments (id, user_id, provider, transaction_id, kind, plan_code, period, amount_xof, status) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'cinetpay', 'T1', 'subscription', 'STARTER', 'monthly', 2000, 'succeeded'),
  ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'cinetpay', 'T3', 'subscription', 'STARTER', 'monthly', 2000, 'pending'),
  ('bbbbbbbb-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'cinetpay', 'T4', 'subscription', 'STARTER', 'monthly', 2000, 'pending');
insert into public.payments (id, user_id, provider, transaction_id, kind, credits, amount_xof, status) values
  ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'cinetpay', 'T2', 'credits', 10, 500, 'succeeded');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 1-5 : forfait FREE
select is(public.my_entitlements() ->> 'plan', 'FREE', 'forfait par défaut : FREE');
select is((public.my_entitlements() -> 'credits' ->> 'plan_credits')::int, 2, 'dotation FREE');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1,
          'FREE : sélections du coupon du jour visibles');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000002'), 0,
          'FREE : sélections d''un coupon prudent à venir réservées');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000003'), 1,
          'après le coup d''envoi, tout est public');
select throws_ok($$ select public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 '42501', null, 'un utilisateur ne peut pas valider un paiement');
select is((select count(*)::int from public.payments), 3, 'ne voit que ses paiements');
reset role;

-- 8-12 : exécution des paiements (rôle service)
set local role service_role;
select is((public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000001') ->> 'fulfilled')::boolean, true, 'abonnement activé');
select is((public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000001') ->> 'already_fulfilled')::boolean, true,
          'même paiement : rien n''est accordé deux fois');
select is((public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000002') -> 'entitlements' ->> 'extra_credits')::int, 10,
          'pack de crédits ajouté');
select throws_ok($$ select public.svc_fulfill_payment('bbbbbbbb-0000-0000-0000-000000000003') $$,
                 '22023', null, 'paiement non confirmé : aucun droit');
select is((select count(*)::int from public.subscriptions where user_id = '11111111-1111-1111-1111-111111111111'), 1,
          'un seul abonnement créé');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 13-15 : forfait STARTER
select is(public.my_entitlements() ->> 'plan', 'STARTER', 'forfait STARTER actif');
select is((public.my_entitlements() -> 'credits' ->> 'plan_credits')::int, 10, 'dotation STARTER accordée tout de suite');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000002'), 1,
          'STARTER : tous les coupons à venir visibles');
reset role;

select * from finish();
rollback;
