-- Tests pgTAP du LOT 3 : analyses partagées en lecture, écritures réservées au
-- serveur, journal IA visible par son auteur et les gestionnaires, prompts protégés.
begin;
select plan(11);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"display_name": "Alice"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local',   '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '{"display_name": "Admin"}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Données DE TEST (transaction annulée)
insert into public.teams (provider_id, provider_ref, name) values
  ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm-a', c.id, 2024, now(), 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.match_analyses (match_id, engine_version, status, stats, source_updated_at)
select id, 'poisson-1.0', 'stats_only', '{"model": null}', now() from public.matches where provider_ref = 'm-a';
insert into public.ai_requests (user_id, kind, status) values
  ('11111111-1111-1111-1111-111111111111', 'match_analysis', 'success'),
  ('22222222-2222-2222-2222-222222222222', 'match_analysis', 'success');

-- 1-3 : données de référence
select ok((select enabled from public.feature_flags where key = 'match_analysis'), 'module d''analyse activé');
select is((select count(*)::int from public.ai_prompts where key = 'match_analysis' and is_active), 1, 'un prompt actif');
select throws_ok($$ insert into public.match_analyses (match_id, engine_version, status, stats, source_updated_at)
                    select id, 'x', 'ok', '{}', now() from public.matches where provider_ref = 'm-a' $$,
                 '23514', null, 'une analyse « ok » exige un texte IA');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 4-8
select is((select count(*)::int from public.match_analyses), 0, 'une analyse n''est lisible que par son auteur (règle du 01/11)');
select is((select count(*)::int from public.ai_requests), 1, 'on ne voit que ses propres requêtes IA');
select is((select count(*)::int from public.ai_prompts), 0, 'les prompts sont réservés aux gestionnaires');
select throws_ok($$ insert into public.match_analyses (match_id, engine_version, status, stats, source_updated_at)
                    select id, 'x', 'stats_only', '{}', now() from public.matches where provider_ref = 'm-a' $$,
                 '42501', null, 'un utilisateur ne peut pas écrire d''analyse');
select throws_ok($$ insert into public.ai_requests (user_id, kind, status)
                    values ('11111111-1111-1111-1111-111111111111', 'match_analysis', 'success') $$,
                 '42501', null, 'un utilisateur ne peut pas écrire dans le journal IA');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
-- 9-10
select is((select count(*)::int from public.ai_requests), 2, 'le gestionnaire voit tout le journal IA');
select ok((select count(*) from public.ai_prompts) >= 1, 'le gestionnaire voit les prompts');

reset role;
set local role anon;
set local request.jwt.claims = '';
-- 11
select throws_ok($$ select count(*) from public.match_analyses $$, '42501', null, 'un visiteur ne lit pas les analyses');

reset role;
select * from finish();
rollback;
