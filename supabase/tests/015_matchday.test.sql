-- Tests pgTAP : compositions et absents lisibles par les utilisateurs connectés, jamais modifiables.
begin;
select plan(5);

insert into auth.users (id, email, raw_user_meta_data) values ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}');
insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '30 minutes', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.match_lineups (match_id, team_id, formation, start_xi)
select m.id, m.home_team_id, '4-3-3', '[{"name": "Joueur", "number": 9, "pos": "F"}]'
from public.matches m where m.provider_ref = 'm1';
insert into public.match_absences (match_id, team_id, player_name, absence_type, reason)
select m.id, m.away_team_id, 'Absent', 'Missing Fixture', 'Knee Injury' from public.matches m where m.provider_ref = 'm1';

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.match_lineups), 1, 'compositions lisibles');
select is((select count(*)::int from public.match_absences), 1, 'absents lisibles');
select throws_ok($$ insert into public.match_absences (match_id, team_id, player_name) select match_id, team_id, 'X' from public.match_absences $$,
                 '42501', null, 'aucune écriture par un utilisateur');
select throws_ok($$ delete from public.match_lineups $$, '42501', null, 'aucune suppression par un utilisateur');
reset role;
set local role anon;
select throws_ok($$ select count(*) from public.match_lineups $$, '42501', null, 'invisible sans connexion');
reset role;

select * from finish();
rollback;
