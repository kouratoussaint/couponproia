-- Tests pgTAP : suivi en direct toutes les 30 secondes, sans appel inutile.
begin;
select plan(3);

select is(app_private.invoke_live_sync(), null, '1. aucun match en cours : pas d''appel');
select ok(not has_function_privilege('authenticated', 'app_private.invoke_live_sync()', 'execute'),
  '2. réservé au serveur');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm-live', c.id, 2026, now() - interval '30 minutes', 'live', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.sync_runs (provider_id, job, status) values ('api_football', 'live', 'running');
select is(app_private.invoke_live_sync(), null, '3. passage précédent encore en cours : pas de second appel');

select * from finish();
rollback;
