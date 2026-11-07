-- Tests pgTAP : sélection des championnats (LOT 25).
begin;
select plan(26);

insert into auth.users (id, email, raw_user_meta_data) values
  ('38383838-3838-3838-3838-383838383801', 'admin25@test.local', '{}'),
  ('38383838-3838-3838-3838-383838383802', 'user25@test.local', '{}'),
  ('38383838-3838-3838-3838-383838383803', 'super25@test.local', '{}');
insert into public.user_roles (user_id, role_id) values
  ('38383838-3838-3838-3838-383838383801', 'admin'),
  ('38383838-3838-3838-3838-383838383803', 'super_admin');

-- État et colonne dérivée -------------------------------------------------------
select is((select count(*)::int from public.competitions where status = 'active'), 9, 'les 9 compétitions suivies passent en active');
select ok((select bool_and(is_active = (status <> 'inactive')) from public.competitions), 'is_active = observation ou active');
update public.competitions set is_active = false where provider_ref = '61';
select is((select status from public.competitions where provider_ref = '61'), 'inactive', 'ancien chemin : is_active false → inactive');
update public.competitions set status = 'observation' where provider_ref = '61';
select ok((select is_active from public.competitions where provider_ref = '61'), 'observation : données synchronisées');
update public.competitions set status = 'active', country = 'France' where provider_ref = '61';
select ok((select quality_override from public.competitions where provider_ref = '6'), 'CAN : forçage de qualité');

-- Catalogue et nom affiché -------------------------------------------------------
insert into public.provider_leagues (provider_id, provider_ref, name, type, country, country_code, current_season, coverage) values
  ('api_football', '423', 'Ligue 1', 'league', 'Burkina-Faso', 'BF', 2025, '{"odds": true}'),
  ('api_football', '386', 'Ligue 1', 'league', 'Ivory-Coast', 'CI', 2025, '{"odds": true}');
select is((select display_name from public.competitions where provider_ref = '61'), 'Ligue 1', 'nom seul sans doublon');

set local role authenticated;
set local request.jwt.claims = '{"sub": "38383838-3838-3838-3838-383838383802", "role": "authenticated"}';
select throws_ok($$ select public.admin_competitions() $$, '42501', null, 'liste réservée à sports.configure');
select throws_ok($$ select public.admin_add_competition('423') $$, '42501', null, 'ajout réservé à sports.configure');
select throws_ok($$ select count(*) from public.provider_leagues $$, '42501', null, 'catalogue illisible directement');

set local request.jwt.claims = '{"sub": "38383838-3838-3838-3838-383838383801", "role": "authenticated"}';
select is(jsonb_array_length(public.admin_search_league_catalog('ligue 1') -> 'results'), 2, 'recherche par nom dans le catalogue');
select is((public.admin_search_league_catalog('burkina') -> 'results' -> 0 ->> 'provider_ref'), '423', 'recherche par pays');
select is((public.admin_add_competition('423') ->> 'status'), 'observation', 'ajout en observation');
select throws_ok($$ select public.admin_add_competition('423') $$, '22023', null, 'pas d''ajout en double');
select throws_ok($$ select public.admin_add_competition('999999') $$, 'P0002', null, 'absente du catalogue');
select is((select display_name from public.competitions where provider_ref = '61'), 'Ligue 1 (France)', 'doublon : pays ajouté (France)');
select is((select display_name from public.competitions where provider_ref = '423'), 'Ligue 1 (Burkina-Faso)', 'doublon : pays ajouté (Burkina)');
select ok((select bool_or((c ->> 'provider_ref') = '423' and c ->> 'status' = 'observation')
           from jsonb_array_elements(public.admin_competitions()) c), 'liste de la console');

-- Passage en active sans verdict : accepté, avec avertissement ; tracé.
select ok((public.admin_set_competition_status((select id from public.competitions where provider_ref = '423'), 'active')
           ->> 'warning') is not null, 'avertissement sans verdict du moteur');
select is((select details ->> 'to' from public.audit_logs where action = 'competition.status' order by id desc limit 1), 'active',
  'changement d''état tracé');
select throws_ok($$ select public.admin_set_competition_status(1, 'archived') $$, '22023', null, 'état inconnu refusé');
select lives_ok($$ select public.admin_set_competition_priority((select id from public.competitions where provider_ref = '423'), 75) $$,
  'ordre modifié');
select throws_ok($$ select public.admin_set_competition_override(1, true) $$, '42501', null, 'forçage réservé au super administrateur');

-- Qualité par identifiant (dernière évaluation) : verdict positif → plus d'avertissement.
reset role;
insert into public.engine_evaluations (engine_version, scope, matches_evaluated, details)
select 'test', '{}', 150, jsonb_build_object('per_competition_ids', jsonb_build_object(
  id || ':2025', jsonb_build_object('matches', 90, 'brierModel', 0.60, 'brierBaseline', 0.65),
  id || ':2026', jsonb_build_object('matches', 30, 'brierModel', 0.62, 'brierBaseline', 0.64)))
from public.competitions where provider_ref = '423';
select is((select verdict from app_private.competition_quality() q join public.competitions c on c.id = q.competition_id
           where c.provider_ref = '423'), true, 'qualité regroupée par identifiant (120 matchs, verdict positif)');
update public.competitions set status = 'observation' where provider_ref = '423';
set local role authenticated;
set local request.jwt.claims = '{"sub": "38383838-3838-3838-3838-383838383801", "role": "authenticated"}';
select is((public.admin_set_competition_status((select id from public.competitions where provider_ref = '423'), 'active')
           ->> 'warning'), null, 'verdict positif : passage en active sans avertissement');

-- Plafond de compétitions suivies.
reset role;
update public.app_settings set value = '10'::jsonb where key = 'sports.max_tracked_competitions';
set local role authenticated;
set local request.jwt.claims = '{"sub": "38383838-3838-3838-3838-383838383801", "role": "authenticated"}';
select throws_ok($$ select public.admin_add_competition('386') $$, '54000', null, 'plafond sports.max_tracked_competitions');

set local request.jwt.claims = '{"sub": "38383838-3838-3838-3838-383838383803", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_competition_override((select id from public.competitions where provider_ref = '423'), true) $$,
  'forçage par le super administrateur');

select * from finish();
rollback;
