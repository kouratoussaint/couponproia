-- Tests pgTAP du LOT 16 : carnet de paris, budget mensuel, alertes de cote, réglages.
begin;
select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'Marseille'), ('api_football', 't-b', 'Toulouse');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Coupon du jour · dimanche', 'd', 'equilibre', 2, 0.45,
        'published', now() - interval '2 hours', now() - interval '2 hours', now() + interval '1 day', now() + interval '1 day', 'v', 'f1');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select 'aaaaaaaa-0000-0000-0000-000000000001', 1, m.id, '1X2', 'HOME', '1X2.HOME', 2.00, now(), 0.5, 'bonne', 'j'
from public.matches m where m.provider_ref = 'm1';

select is(app_private.selection_label('OU.OVER.2.5', 'A', 'B'), 'Plus de 2,5 buts', '1. libellé d''une sélection');

-- Carnet d'Alice
update public.user_preferences set monthly_budget = 10000, stake_limit = 5000
where user_id = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok(format($$ select public.journal_add('match', null, 'Marseille – Toulouse', 7000, 2.1,
  '[{"match_id": %s, "key": "1X2.HOME", "odd": 2.0, "label": "Victoire Marseille"}]') $$,
  (select id from public.matches where provider_ref = 'm1')), '2. pari ajouté au carnet');
select throws_ok(format($$ select public.journal_add('match', null, 'X', 1000, 2,
  '[{"match_id": %s, "key": "CORNERS.OVER", "odd": 2.0}]') $$,
  (select id from public.matches where provider_ref = 'm1')), '22023', null, '3. issue inconnue refusée');
select throws_ok($$ select public.journal_add('match', null, 'X', 1000, 2, '[{"match_id": 999999999, "key": "1X2.HOME", "odd": 2.0}]') $$,
  '22023', null, '4. match inexistant refusé');
select is((select count(*)::int from public.notifications where kind = 'budget'), 0, '5. pas d''alerte sous 80 %');
select lives_ok(format($$ select public.journal_add('match', null, 'Encore', 1500, 2,
  '[{"match_id": %s, "key": "DC.1X", "odd": 1.3}]') $$, (select id from public.matches where provider_ref = 'm1')),
  '6. deuxième pari');
select is((select count(*)::int from public.notifications where kind = 'budget'), 1, '7. alerte à 80 % du budget');
select lives_ok($$ select public.journal_update((select id from public.bet_journal where title = 'Encore'), 2000, 1.35, 'cote obtenue') $$,
  '8. mise et cote corrigées');
select is((select total_odd from public.bet_journal where title = 'Encore'), 1.35::numeric, '9. cote corrigée');
select throws_ok($$ insert into public.bet_journal (user_id, source_type, title, stake, total_odd, legs, first_kickoff_at)
  values ('11111111-1111-1111-1111-111111111111', 'match', 'direct', 1, 2, '[{}]', now()) $$,
  '42501', null, '10. écriture directe interdite');

-- Bob ne voit pas le carnet d'Alice
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.bet_journal), 0, '11. carnet privé');

-- Alerte de cote sur un coupon suivi
select ok(public.set_coupon_watch('aaaaaaaa-0000-0000-0000-000000000001', true), '12. coupon suivi');
reset role;
insert into public.odds_snapshots (match_id, market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at)
select m.id, '1X2', 'HOME', null, 1.70, 1.75, 8, now() from public.matches m where m.provider_ref = 'm1';
select is(app_private.notify_odds_moves(), 1, '13. baisse de 15 % détectée');
select app_private.notify_odds_moves();
select is((select count(*)::int from public.notifications where kind = 'odds' and user_id = '22222222-2222-2222-2222-222222222222'),
          1, '14. une seule alerte par sélection et par sens');

-- Réglages
set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select throws_ok($$ select public.admin_set_setting('alerts.odds_move_percent', '1') $$, '22023', null, '15. seuil trop bas refusé');
reset role;

select ok(public.platform_performance(null) ? 'returned', '16. performances : retour cumulé publié');

select * from finish();
rollback;
