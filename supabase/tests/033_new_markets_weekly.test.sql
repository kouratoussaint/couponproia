-- Tests pgTAP : nouveaux marchés (remboursé si nul, buts par équipe) et rapport hebdomadaire.
begin;
select plan(13);

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}', now()),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}', now()),
  ('44444444-4444-4444-4444-444444444444', 'non-confirme@test.local', '{}', null);

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'Lille'), ('api_football', 't-b', 'Lens');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

-- 1-3 : marchés
select is((select count(*)::int from public.markets where code in ('DNB', 'TTH', 'TTA')), 3, '1. trois nouveaux marchés');
select lives_ok(format($$ insert into public.odds_snapshots (match_id, market_code, outcome_code, line, odd_median, odd_best, bookmakers_count)
  values (%s, 'TTH', 'OVER', 1.5, 2.1, 2.2, 6), (%s, 'DNB', 'HOME', null, 1.5, 1.55, 6) $$,
  (select id from public.matches where provider_ref = 'm1'), (select id from public.matches where provider_ref = 'm1')),
  '2. cotes des nouveaux marchés enregistrables');
select is(app_private.ai_contradiction('DNB.HOME', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "1X2.AWAY"}]}'),
  '1X2.AWAY', '3. remboursé si nul domicile contredit une victoire extérieure');
select is(app_private.ai_contradiction('DNB.HOME', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "DC.1X"}]}'),
  null, '4. remboursé si nul domicile compatible avec « 1 ou nul »');

-- 5-6 : carnet
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok(format($$ select public.journal_add('match', null, 'Lille – Lens', 1000, 1.5,
  '[{"match_id": %s, "key": "DNB.HOME", "odd": 1.5}]') $$, (select id from public.matches where provider_ref = 'm1')),
  '5. pari « remboursé si nul » noté au carnet');
select lives_ok(format($$ select public.journal_add('match', null, 'Lille buts', 1000, 2.1,
  '[{"match_id": %s, "key": "TTH.OVER.1.5", "odd": 2.1}]') $$, (select id from public.matches where provider_ref = 'm1')),
  '6. pari « buts de l''équipe à domicile » noté au carnet');

-- 7-9 : rapport hebdomadaire (réglage personnel)
select lives_ok($$ update public.user_preferences set weekly_email = true where user_id = auth.uid() $$,
  '7. rapport hebdomadaire activable');
select throws_ok($$ update public.user_preferences set weekly_email_sent_at = now() where user_id = auth.uid() $$,
  '42501', null, '8. date d''envoi réservée au serveur');
select throws_ok($$ select public.svc_weekly_report(now() - interval '7 days') $$,
  '42501', null, '9. données du rapport réservées au serveur');
reset role;

-- 10-13 : destinataires
update public.user_preferences set weekly_email = true where user_id = '44444444-4444-4444-4444-444444444444';
select is(jsonb_array_length(public.svc_weekly_report(now() - interval '7 days') -> 'recipients'), 1,
  '10. seuls les comptes qui l''ont demandé, e-mail confirmé');
select is(public.svc_weekly_report(now() - interval '7 days') #>> '{recipients,0,email}', 'alice@test.local',
  '11. destinataire attendu');
update public.user_preferences set weekly_email_sent_at = now() - interval '1 day' where user_id = '11111111-1111-1111-1111-111111111111';
select is(jsonb_array_length(public.svc_weekly_report(now() - interval '7 days') -> 'recipients'), 0,
  '12. pas deux rapports dans la même semaine');
select is(jsonb_array_length(public.svc_weekly_report(now() - interval '7 days', '22222222-2222-2222-2222-222222222222') -> 'recipients'), 1,
  '13. aperçu pour un compte précis');

select * from finish();
rollback;
