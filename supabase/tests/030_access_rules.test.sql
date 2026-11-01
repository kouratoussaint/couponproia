-- Tests pgTAP : règles d'accès du 01/11 et fin de forfait.
begin;
select plan(12);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'free@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'starter@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');
insert into public.subscriptions (user_id, plan_code, period_start, period_end, source, note) values
  ('22222222-2222-2222-2222-222222222222', 'STARTER', now() - interval '1 day', now() + interval '29 days', 'admin', 't'),
  ('22222222-2222-2222-2222-222222222222', 'STARTER', now() + interval '29 days', now() + interval '59 days', 'admin', 't');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', x.ref, c.id, 2026, x.k, 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a,
     (values ('m-futur', now() + interval '3 hours'), ('m-passe', now() - interval '3 hours')) as x(ref, k)
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Du jour', 'd', 'equilibre', 2, 0.4, 'published', now(), now(),
   now() + interval '3 hours', now() + interval '3 hours', 'v', 'f1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Prudent', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() - interval '4 hours', now() - interval '3 hours', 'v', 'f2'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'prudent', 'En cours', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() - interval '1 hour', now() - interval '1 hour', 'v', 'f3');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select c.id, 1, m.id, '1X2', 'HOME', '1X2.HOME', 2, now(), 0.5, 'bonne', 'j'
from public.coupons c, public.matches m where m.provider_ref = 'm-futur';

insert into public.match_analyses (match_id, engine_version, prompt_key, prompt_version, status, stats, analysis, source_updated_at)
select id, 'v', 'match_analysis', 1, 'ok', '{}', '{}', now() from public.matches where provider_ref = 'm-futur';
insert into public.analysis_access (user_id, match_id, source)
select '22222222-2222-2222-2222-222222222222', id, 'plan' from public.matches where provider_ref = 'm-futur';

set local role authenticated;
-- FREE
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1,
          '1. FREE : coupon du jour gratuit, à tout moment');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000003'), 0,
          '2. FREE : coupon en cours masqué');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000002'), 1,
          '3. FREE : visible après les matchs');
select is((select count(*)::int from public.match_analyses), 0, '4. FREE : analyse d''un autre invisible');
-- STARTER
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.coupon_selections), 3, '5. forfait payant : tous les coupons à tout moment');
select is((select count(*)::int from public.match_analyses), 1, '6. analyse visible par son auteur');
-- Super administrateur
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.match_analyses), 1, '7. super administrateur : toutes les analyses');
select throws_ok($$ select public.admin_end_subscription('11111111-1111-1111-1111-111111111111', 'test') $$,
                 '22023', null, '8. déjà au forfait FREE');
select throws_ok($$ select public.admin_end_subscription('22222222-2222-2222-2222-222222222222', '') $$,
                 '22023', null, '9. motif obligatoire');
select is(public.admin_end_subscription('22222222-2222-2222-2222-222222222222', 'Remboursement'), 2,
          '10. forfait en cours et prolongation arrêtés');
reset role;
select is(app_private.plan_of('22222222-2222-2222-2222-222222222222'), 'FREE', '11. retour au forfait FREE');
select is((select plan_code from public.credit_accounts where user_id = '22222222-2222-2222-2222-222222222222'), 'FREE',
          '12. crédits du forfait FREE');

select * from finish();
rollback;
