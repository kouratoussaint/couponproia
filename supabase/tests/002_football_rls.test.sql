-- Tests pgTAP du LOT 2 : données football lisibles par les connectés, écritures
-- réservées au serveur, journal de synchronisation réservé aux gestionnaires.
begin;
select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"display_name": "Alice"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '{"display_name": "Admin"}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Données de démonstration DE TEST (jamais en production : transaction annulée)
insert into public.teams (provider_id, provider_ref, name) values
  ('api_football', 't-home', 'Équipe A'), ('api_football', 't-away', 'Équipe B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status,
                            home_team_id, away_team_id)
select 'api_football', 'm-1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-home' and a.provider_ref = 't-away';
insert into public.odds_snapshots (match_id, market_code, outcome_code, odd_median, odd_best, bookmakers_count, captured_at)
select m.id, '1X2', 'HOME', 2.10, 2.25, 12, now() - interval '6 hours' from public.matches m where m.provider_ref = 'm-1';
insert into public.odds_snapshots (match_id, market_code, outcome_code, odd_median, odd_best, bookmakers_count, captured_at)
select m.id, '1X2', 'HOME', 1.95, 2.05, 14, now() from public.matches m where m.provider_ref = 'm-1';
insert into public.sync_runs (provider_id, job, status, requests_used) values ('api_football', 'daily', 'success', 27);

-- 1-4 : données de référence
select is((select count(*)::int from public.competitions where is_active), 9, '9 compétitions actives au départ');
select is((select count(*)::int from public.markets), 7, '7 marchés normalisés (dont remboursé si nul et buts par équipe)');
select ok((select enabled from public.feature_flags where key = 'matches'), 'module Matchs activé');
select is((select count(*)::int from public.app_settings where key like 'sports.%' and not is_public), 7,
          'réglages de synchronisation privés');

-- 5-6 : contraintes
select throws_ok($$ insert into public.odds_snapshots (match_id, market_code, outcome_code, odd_median, odd_best, bookmakers_count)
                    select id, '1X2', 'AWAY', 3.0, 2.5, 3 from public.matches where provider_ref = 'm-1' $$,
                 '23514', null, 'meilleure cote inférieure à la médiane refusée');
select throws_ok($$ insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
                    select 'api_football', 'm-x', c.id, 2026, now(), 'scheduled', t.id, t.id
                    from public.competitions c, public.teams t where c.provider_ref = '39' and t.provider_ref = 't-home' $$,
                 '23514', null, 'une équipe ne peut pas jouer contre elle-même');

-- Utilisateur ordinaire --------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

-- 7-13
select is((select count(*)::int from public.matches where provider_ref = 'm-1'), 1, 'un connecté lit les matchs');
select is((select odd_median from public.latest_odds where outcome_code = 'HOME'), 1.950::numeric(7,3),
          'latest_odds renvoie le relevé le plus récent');
select is((select count(*)::int from public.sync_runs), 0, 'journal de synchronisation invisible');
select is((select count(*)::int from public.data_providers), 0, 'fournisseurs invisibles');
select throws_ok($$ insert into public.teams (provider_id, provider_ref, name) values ('api_football', 'x', 'X') $$,
                 '42501', null, 'un utilisateur ne peut pas créer d''équipe');
select throws_ok($$ update public.matches set home_goals = 9 where provider_ref = 'm-1' $$,
                 '42501', null, 'un utilisateur ne peut pas modifier un score');
select throws_ok($$ select app_private.invoke_sports_sync('daily') $$,
                 '42501', null, 'un utilisateur ne peut pas lancer la synchronisation');

-- Gestionnaire -----------------------------------------------------------------
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
-- 14
select is((select count(*)::int from public.sync_runs), 1, 'l''admin voit le journal de synchronisation');

-- Visiteur ---------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '';
-- 15-16
select throws_ok($$ select count(*) from public.matches $$, '42501', null, 'un visiteur ne lit pas les matchs');
select throws_ok($$ select count(*) from public.latest_odds $$, '42501', null, 'un visiteur ne lit pas les cotes');

reset role;
select * from finish();
rollback;
