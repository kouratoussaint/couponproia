-- Tests pgTAP du LOT 8 : règlement possible sur un coupon publié (contenu toujours protégé),
-- statistiques de la plateforme (publiés seulement, mise théorique explicite), statistiques
-- personnelles et historique des règlements.
begin;
select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');

-- Données DE TEST (transaction annulée)
insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() - interval '1 day', 'finished', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint, result, settled_odd)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Gagné', 'd', 'equilibre', 3.2, 0.3, 'published',
   now() - interval '2 days', now() - interval '2 days', now() - interval '1 day', now() - interval '1 day', 'v', 'f1', 'won', 3.2),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'du_jour', 'Perdu', 'd', 'equilibre', 2.5, 0.3, 'published',
   now() - interval '2 days', now() - interval '2 days', now() - interval '1 day', now() - interval '1 day', 'v', 'f2', 'lost', 0),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'prudent', 'En attente', 'd', 'prudent', 1.8, 0.5, 'published',
   now() - interval '2 days', now() - interval '2 days', now() + interval '1 day', now() + interval '1 day', 'v', 'f3', null, null),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'audacieux', 'Retiré', 'd', 'audacieux', 9, 0.1, 'withdrawn',
   now() - interval '2 days', now() - interval '2 days', now() - interval '1 day', now() - interval '1 day', 'v', 'f4', 'lost', 0);
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification, result)
select 'aaaaaaaa-0000-0000-0000-000000000001', 1, id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.62, 'bonne', 'j', 'won'
from public.matches where provider_ref = 'm1';
insert into public.settlement_history (coupon_kind, coupon_id, new_result, selections)
values ('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'won', '[]'),
       ('user', 'dddddddd-0000-0000-0000-000000000002', 'lost', '[]');
insert into public.user_coupons (id, user_id, status, title, total_odd, combined_probability, risk_level, engine_version, fingerprint, result, settled_odd)
values ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'saved', 'A1', 2.0, 0.4, 'equilibre', 'v', 'x', 'won', 2.0),
       ('dddddddd-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'saved', 'B1', 2.0, 0.4, 'equilibre', 'v', 'y', 'lost', 0);

-- 1-3 : règlement d'un coupon publié
select lives_ok($$ update public.coupons set result = 'won', settled_odd = 1.8, settled_at = now()
                   where id = 'aaaaaaaa-0000-0000-0000-000000000003' $$, 'un coupon publié peut être réglé');
select throws_ok($$ update public.coupons set total_odd = 5 where id = 'aaaaaaaa-0000-0000-0000-000000000003' $$,
                 '42501', null, 'mais son contenu reste immuable');
update public.coupons set result = null, settled_odd = null, settled_at = null where id = 'aaaaaaaa-0000-0000-0000-000000000003';
select lives_ok($$ update public.coupon_selections set result = 'lost' where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
                'le résultat d''une sélection publiée peut être corrigé');
update public.coupon_selections set result = 'won' where coupon_id = 'aaaaaaaa-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 4-10 : statistiques et historique
select is((public.platform_performance() ->> 'coupons')::int, 3, 'statistiques : coupons publiés seulement');
select is((public.platform_performance() ->> 'withdrawn')::int, 1, 'les retraits sont comptés à part');
select is((public.platform_performance() ->> 'win_rate')::numeric, 0.5, 'taux de réussite sur les coupons réglés');
select is((public.platform_performance() ->> 'theoretical_return')::numeric, 0.6, 'rendement pour une mise théorique de 1 unité');
select is((public.platform_performance() -> 'by_market' -> 0 ->> 'hit_rate')::numeric, 1.0, 'réussite par marché (sélections)');
select is((public.my_performance() ->> 'won')::int, 1, 'statistiques personnelles : ses coupons seulement');
select is((select count(*)::int from public.settlement_history), 1, 'historique : celui des coupons publics et des siens');

reset role;
select * from finish();
rollback;
