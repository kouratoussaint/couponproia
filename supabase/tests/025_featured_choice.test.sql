-- Tests pgTAP : choix de l'analyse offerte (super administrateur), réglages du 01/11.
begin;
select plan(8);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values
  ('11111111-1111-1111-1111-111111111111', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'super_admin');
-- Fuseau choisi pour que « aujourd'hui à 23 h » soit toujours à venir, quelle que soit l'heure
-- du test (après 21 h UTC, on passe sur un fuseau UTC+14 où il est encore la mi-journée).
create temporary table tz_test as
select case when extract(hour from now() at time zone 'UTC') >= 21 then 'Pacific/Kiritimati'
            else 'Africa/Ouagadougou' end as tz;
insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', x.ref, c.id, 2026, x.k, 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a, tz_test t,
     lateral (values ('m-tard', (date_trunc('day', now() at time zone t.tz) + interval '23 hours') at time zone t.tz),
                     ('m-bientot', now() + interval '10 minutes')) as x(ref, k)
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
update public.app_settings set value = to_jsonb((select tz from tz_test)) where key = 'app.timezone';

select is((select value from public.app_settings where key = 'featured.auto_pick_hour'), '9'::jsonb,
          '1. choix automatique à 9 h par défaut');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ select public.admin_set_featured((select id from public.matches where provider_ref = 'm-tard')) $$,
                 '42501', null, '2. réservé au super administrateur');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select throws_ok($$ select public.admin_set_featured((select id from public.matches where provider_ref = 'm-bientot')) $$,
                 '22023', null, '3. match trop proche refusé');
select is(public.admin_set_featured((select id from public.matches where provider_ref = 'm-tard')) ->> 'match_id',
          (select id::text from public.matches where provider_ref = 'm-tard'), '4. match choisi');
select ok((select chosen_by = '33333333-3333-3333-3333-333333333333' from public.featured_matches
           where day = app_private.local_today()), '5. choix attribué au super administrateur');
select lives_ok($$ select public.admin_set_setting('featured.auto_pick_hour', '7') $$, '6. heure réglable');
select throws_ok($$ select public.admin_set_setting('featured.auto_pick_hour', '25') $$, '22023', null, '7. heure invalide refusée');
select lives_ok($$ select public.admin_set_setting('bookmaker.link', '{"name": "Mon bookmaker", "url": "https://exemple.com"}') $$,
                '8. lien du bookmaker réglable');
reset role;

select * from finish();
rollback;
