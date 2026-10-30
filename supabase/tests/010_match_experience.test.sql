-- Tests pgTAP du LOT 9 bis : barre 1/N/2 du marché, match offert du jour, données de l'onglet Stats.
begin;
select plan(18);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}');

insert into public.teams (provider_id, provider_ref, name) values
  ('api_football', 't-a', 'Alpha'), ('api_football', 't-b', 'Bravo'), ('api_football', 't-c', 'Charlie');
update public.competitions set is_active = true where provider_ref = '39';

-- Historique : Alpha a marqué lors de ses 4 derniers matchs, Bravo a perdu ses 3 derniers.
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id, home_goals, away_goals)
select 'api_football', v.ref, c.id, 2026, now() - v.ago, 'finished', h.id, a.id, v.hg, v.ag
from public.competitions c,
     (values ('h1', interval '40 days', 't-a', 't-b', 2, 0),
             ('h2', interval '30 days', 't-b', 't-a', 1, 3),
             ('h3', interval '20 days', 't-a', 't-c', 1, 1),
             ('h4', interval '10 days', 't-c', 't-b', 2, 1),
             ('h5', interval '5 days',  't-a', 't-b', 2, 2)) as v(ref, ago, ht, at, hg, ag)
join public.teams h on h.provider_ref = v.ht
join public.teams a on a.provider_ref = v.at
where c.provider_ref = '39';
-- h5 : nul 2-2 → Bravo n'a pas « 3 défaites de suite » ; Alpha marque depuis 4 matchs.

-- Match à venir (dans 3 h) avec cotes 1/N/2, et un autre déjà commencé.
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', v.ref, c.id, 2026, now() + v.inn, 'scheduled', h.id, a.id
from public.competitions c,
     (values ('up', interval '3 hours', 't-a', 't-b'),
             ('soon', interval '20 minutes', 't-c', 't-a')) as v(ref, inn, ht, at)
join public.teams h on h.provider_ref = v.ht
join public.teams a on a.provider_ref = v.at
where c.provider_ref = '39';

insert into public.odds_snapshots (match_id, market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at)
select m.id, '1X2', v.o, null, v.odd, v.odd, 8, now()
from public.matches m, (values ('HOME', 2.0), ('DRAW', 3.5), ('AWAY', 4.0)) as v(o, odd)
where m.provider_ref in ('up', 'soon');

insert into public.standings (competition_id, season, team_id, rank, points, played, win, draw, lose, goals_for, goals_against, goal_diff, form, description)
select c.id, 2026, t.id, v.rk, v.pts, 4, 0, 0, 0, 0, 0, v.gd, 'WWDLW', v.descr
from public.competitions c,
     (values ('t-a', 1, 8, 4, 'Promotion - Champions League'), ('t-c', 2, 5, 1, null), ('t-b', 3, 1, -5, 'Relegation')) as v(ref, rk, pts, gd, descr)
join public.teams t on t.provider_ref = v.ref
where c.provider_ref = '39';

-- 1-3 : barre 1/N/2 (marge retirée : la somme vaut 1)
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select round(p_home + p_draw + p_away, 2) from public.match_1x2_market k
           join public.matches m on m.id = k.match_id where m.provider_ref = 'up'), 1.00, 'probabilités du marché normalisées');
select ok((select p_home > p_draw and p_draw > p_away from public.match_1x2_market k
           join public.matches m on m.id = k.match_id where m.provider_ref = 'up'), 'ordre des probabilités cohérent avec les cotes');
select is(public.featured_match_today(), null::bigint, 'aucun match offert tant qu''il n''est pas choisi');
select throws_ok($$ select public.svc_pick_featured_match() $$, '42501', null, 'le choix est réservé au serveur');
reset role;

-- 5-7 : choix du match offert (pas celui qui commence dans 20 minutes), stable
select is(public.svc_pick_featured_match(((select kickoff_at from public.matches where provider_ref = 'up') at time zone 'Africa/Ouagadougou')::date), (select id from public.matches where provider_ref = 'up'), 'match offert : à plus d''1 h du coup d''envoi');
update public.competitions set priority = 1 where provider_ref = '39';
select is(public.svc_pick_featured_match(((select kickoff_at from public.matches where provider_ref = 'up') at time zone 'Africa/Ouagadougou')::date), (select id from public.matches where provider_ref = 'up'), 'choix stable pour la journée');
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select match_id from public.featured_matches where day = ((select kickoff_at from public.matches where provider_ref = 'up') at time zone 'Africa/Ouagadougou')::date), (select id from public.matches where provider_ref = 'up'), 'match offert lisible par l''utilisateur');

-- 8-18 : onglet Stats
create temp table ins on commit drop as
select public.match_insights((select id from public.matches where provider_ref = 'up')) as j;
select is((select jsonb_array_length(j -> 'standings' -> 'rows') from ins), 3, 'classement complet');
select is((select j -> 'standings' -> 'rows' -> 0 ->> 'description' from ins), 'Promotion - Champions League', 'zones du classement');
select is((select jsonb_array_length(j -> 'form' -> 'home') from ins), 4, 'forme : matchs joués d''Alpha');
select is((select j -> 'form' -> 'home' -> 0 ->> 'result' from ins), 'D', 'forme : dernier match (nul 2-2) en premier');
select is((select (j -> 'season' -> 'home' ->> 'goals_for')::int from ins), 8, 'comparatif : buts marqués par Alpha');
select is((select (j -> 'season' -> 'away' ->> 'clean_sheets')::int from ins), 0, 'comparatif : matchs sans encaisser de Bravo');
select is((select (e ->> 'length')::int from ins, jsonb_array_elements(j -> 'streaks' -> 'home') e where e ->> 'key' = 'scored'),
          4, 'série : Alpha a marqué lors de ses 4 derniers matchs');
select ok((select (e ->> 'at_least')::boolean from ins, jsonb_array_elements(j -> 'streaks' -> 'home') e where e ->> 'key' = 'scored'),
          'série couvrant tout l''historique : « au moins »');
select is((select count(*)::int from ins, jsonb_array_elements(j -> 'streaks' -> 'away') e where e ->> 'key' = 'losses'),
          0, 'pas de série de défaites inventée pour Bravo');
select is((select (j -> 'h2h' ->> 'count')::int from ins), 3, 'confrontations directes');
select is((select (j -> 'h2h' ->> 'home_wins')::int || '-' || (j -> 'h2h' ->> 'draws') || '-' || (j -> 'h2h' ->> 'away_wins') from ins),
          '2-1-0', 'bilan des confrontations du point de vue du match');
reset role;

select * from finish();
rollback;
