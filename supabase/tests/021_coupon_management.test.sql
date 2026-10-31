-- Tests pgTAP : suppression définitive des coupons retirés (équipe uniquement, journalisée),
-- coupons publiés toujours protégés.
begin;
select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'prudent', 'Retiré', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Publié', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f2');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select c.id, 1, m.id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.6, 'bonne', 'j'
from public.coupons c, public.matches m where m.provider_ref = 'm1';

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select public.admin_withdraw_coupon('aaaaaaaa-0000-0000-0000-000000000001', 'Cote périmée');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ select public.admin_delete_withdrawn_coupons(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[], 'x') $$,
                 '42501', null, '1. suppression refusée à un utilisateur');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ select public.admin_delete_withdrawn_coupons(array['aaaaaaaa-0000-0000-0000-000000000002']::uuid[], 'x') $$,
                 '22023', null, '2. un coupon publié ne peut pas être supprimé');
select throws_ok($$ select public.admin_delete_withdrawn_coupons(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[], ' ') $$,
                 '22023', null, '3. motif obligatoire');
select throws_ok($$ select public.admin_delete_withdrawn_coupons(array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002']::uuid[], 'Nettoyage') $$,
                 '22023', null, '4. lot mélangé refusé en entier');
select is(public.admin_delete_withdrawn_coupons(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[], 'Nettoyage'), 1,
          '5. coupon retiré supprimé');
reset role;

select is((select count(*)::int from public.coupons where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, '6. coupon effacé');
select is((select count(*)::int from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0,
          '7. sélections effacées');
select ok((select details -> 'snapshot' ->> 'title' = 'Retiré' and details -> 'snapshot' -> 'withdrawal' ->> 'reason' = 'Cote périmée'
           from public.audit_logs where action = 'coupon.delete'), '8. contenu et motif du retrait conservés au journal');
select throws_ok($$ delete from public.coupon_selections where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
                 '42501', null, '9. sélections d''un coupon publié toujours protégées');

select * from finish();
rollback;
