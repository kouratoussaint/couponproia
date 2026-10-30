-- Tests pgTAP du LOT 4 : visibilité des coupons, immuabilité après publication,
-- anti-doublon, historique des statuts, RPC d'administration.
begin;
select plan(17);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Données DE TEST (transaction annulée)
insert into public.teams (provider_id, provider_ref, name) values
  ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B'), ('api_football', 't-c', 'C'), ('api_football', 't-d', 'D');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', x.ref, c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from (values ('m1', 't-a', 't-b'), ('m2', 't-c', 't-d')) as x(ref, h, a)
join public.competitions c on c.provider_ref = '39'
join public.teams h on h.provider_ref = x.h
join public.teams a on a.provider_ref = x.a;

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Publié', 'd', 'equilibre', 3.2, 0.3,
   'published', now(), now(), now() + interval '1 day', now() + interval '1 day', 'poisson-1.0', 'fp-1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Prêt', 'd', 'prudent', 2.1, 0.45,
   'ready', now() + interval '1 hour', null, now() + interval '1 day', now() + interval '1 day', 'poisson-1.0', 'fp-2'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'audacieux', 'À valider', 'd', 'audacieux', 9.5, 0.1,
   'pending_review', now() + interval '1 hour', null, now() + interval '1 day', now() + interval '1 day', 'poisson-1.0', 'fp-3');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select c.id, 1, m.id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.55, 'bonne', 'Bon bilan à domicile.'
from public.coupons c, public.matches m
where m.provider_ref = 'm1' and c.id in ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002');

-- 1-6 : données de référence, historique, contraintes
select is((select count(*)::int from public.coupon_profiles), 6, 'six profils par défaut');
select ok((select enabled from public.feature_flags where key = 'platform_coupons'), 'onglet Coupons activé');
select is((select count(*)::int from public.coupon_status_history), 3, 'statut initial historisé');
select throws_ok($$ insert into public.coupons (category, title, description, risk_level, total_odd, combined_probability,
                      status, publish_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
                    values ('du_jour', 'Doublon', 'd', 'prudent', 2, 0.5, 'ready', now(), now(), now(), 'v', 'fp-1') $$,
                 '23505', null, 'pas deux coupons identiques en circulation');
select throws_ok($$ insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code,
                      selection_key, odd, odds_captured_at, model_probability, reliability, justification)
                    select 'aaaaaaaa-0000-0000-0000-000000000002', 2, id, 'DC', '1X', 'DC.1X', 1.3, now(), 0.7, 'bonne', 'x'
                    from public.matches where provider_ref = 'm1' $$,
                 '23505', null, 'jamais deux sélections du même match');
select lives_ok($$ update public.coupons set title = 'Corrigé' where id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
                'un coupon non publié reste modifiable');

-- 7-9 : immuabilité
select throws_ok($$ update public.coupons set total_odd = 5 where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
                 '42501', null, 'cote d''un coupon publié immuable');
select throws_ok($$ update public.coupon_selections set odd = 2.5
                    where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
                 '42501', null, 'sélection d''un coupon publié immuable');
select throws_ok($$ delete from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
                 '42501', null, 'sélection d''un coupon publié non supprimable');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 10-13 : utilisateur
select is((select count(*)::int from public.coupons), 1, 'un utilisateur ne voit que les coupons publiés');
select is((select count(*)::int from public.coupon_selections), 1, 'et seulement leurs sélections');
select is((select count(*)::int from public.coupon_profiles), 0, 'profils réservés aux gestionnaires');
select throws_ok($$ select public.admin_review_coupon('aaaaaaaa-0000-0000-0000-000000000003', true) $$,
                 '42501', null, 'un utilisateur ne valide pas de coupon');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
-- 14-17 : administrateur
select is((select count(*)::int from public.coupons), 3, 'le gestionnaire voit tous les coupons');
select is(public.admin_review_coupon('aaaaaaaa-0000-0000-0000-000000000003', true, 'OK'), 'ready',
          'validation humaine : coupon prêt à publier');
select throws_ok($$ select public.admin_update_coupon_profile(
                      (select id from public.coupon_profiles where key = 'du_jour'), '{"generate_times": ["25:00"]}') $$,
                 '22023', null, 'heure invalide refusée');
select is((public.admin_update_coupon_profile(
             (select id from public.coupon_profiles where key = 'du_jour'),
             '{"criteria": {"min_total_odd": 3}, "generate_times": ["12:00", "06:30"]}')).generate_times,
          '{06:30,12:00}'::text[], 'profil modifié, critères fusionnés, horaires triés');

reset role;
select * from finish();
rollback;
