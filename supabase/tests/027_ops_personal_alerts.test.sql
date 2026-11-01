-- Tests pgTAP du LOT 17 : alertes personnalisées, plantages remontés, alertes d'exploitation.
begin;
select plan(18);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'Lille'), ('api_football', 't-b', 'Lens');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', x.ref, c.id, 2026, x.k, x.s, h.id, a.id
from public.competitions c, public.teams h, public.teams a,
     (values ('m-later', now() + interval '1 day', 'scheduled'), ('m-soon', now() + interval '15 minutes', 'scheduled'),
             ('m-live', now() - interval '30 minutes', 'live')) as x(ref, k, s)
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

-- 1-2. Sélection au score courant
select ok(app_private.outcome_at('OU.OVER.2.5', 2, 1) and not app_private.outcome_at('OU.UNDER.2.5', 2, 1),
          '1. plus / moins de buts au score courant');
select ok(app_private.outcome_at('DC.1X', 1, 1) and not app_private.outcome_at('1X2.AWAY', 1, 1), '2. double chance et 1X2');

-- 3. Équipe suivie analysée
insert into public.user_favorites (user_id, team_id)
select '11111111-1111-1111-1111-111111111111', id from public.teams where provider_ref = 't-a';
insert into public.match_analyses (match_id, engine_version, prompt_key, prompt_version, status, stats, analysis, source_updated_at)
select id, 'v', 'match_analysis', 1, 'ok', '{}', '{}', now() from public.matches where provider_ref = 'm-later';
select is((select count(*)::int from public.notifications where kind = 'analysis'
           and user_id = '11111111-1111-1111-1111-111111111111'), 1, '3. équipe suivie analysée : alerte');

-- 4-5. Rappel avant un pari du carnet, puis but en direct
set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select lives_ok(format($$ select public.journal_add('match', null, 'Lille – Lens', 1000, 2.1,
  '[{"match_id": %s, "key": "1X2.HOME", "odd": 2.0}]') $$, (select id from public.matches where provider_ref = 'm-soon')),
  '4. pari noté');
select lives_ok(format($$ select public.journal_add('match', null, 'Lille – Lens en direct', 1000, 1.9,
  '[{"match_id": %s, "key": "OU.OVER.2.5", "odd": 1.9}]') $$, (select id from public.matches where provider_ref = 'm-live')),
  '5. pari en direct noté');
reset role;
select is(app_private.notify_bet_reminders(), 1, '6. rappel 15 minutes avant');
update public.matches set home_goals = 1, away_goals = 0 where provider_ref = 'm-live';
select is((select title from public.notifications where kind = 'live'), 'But ! Lille 1–0 Lens', '7. but en direct notifié');
select ok((select body like 'Plus de 2,5 buts : compromis à ce score%' from public.notifications where kind = 'live'),
          '8. état de la sélection au score courant');
update public.matches set home_goals = 1, away_goals = 0, status = 'live' where provider_ref = 'm-live';
select is((select count(*)::int from public.notifications where kind = 'live'), 1, '9. pas de doublon sans changement de score');

-- 10. Types de coupons préférés : aucun type choisi = tous
update public.user_preferences set coupon_categories = '{prudent}' where user_id = '22222222-2222-2222-2222-222222222222';
select throws_ok($$ update public.user_preferences set coupon_categories = '{inconnu}'
                    where user_id = '22222222-2222-2222-2222-222222222222' $$, '23514', null, '10. type inconnu refusé');

-- 11-14. Plantages remontés par l'application
set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select lives_ok($$ select public.report_client_error('dart', 'Null check operator used on a null value', E'#0 Foo.bar (package:x/a.dart:12)\n#1 main', 'Accueil', '0.24.0', 129, 'android 14') $$,
                '11. plantage remonté');
select lives_ok($$ select public.report_client_error('dart', 'Null check operator used on a null value', E'#0 Foo.bar (package:x/a.dart:12)\n#1 main', 'Accueil', '0.24.0', 129, 'android 14') $$,
                '12. même plantage');
select is((select count(*)::int from public.client_errors), 0, '13. invisible pour un utilisateur');
reset role;
select is((select occurrences from public.client_errors), 2, '14. regroupé par empreinte');

-- 15-18. Alertes d'exploitation
insert into public.payments (user_id, provider, transaction_id, kind, plan_code, period, amount_xof, status, created_at)
values ('22222222-2222-2222-2222-222222222222', 'ligdicash', 'T-stuck', 'subscription', 'STARTER', 'monthly', 2000, 'pending',
        now() - interval '3 hours');
select ok(public.ops_run_scan() -> 'opened' @> '[{"title": "Paiements en attente depuis plus de 2 h"}]',
          '15. alerte ouverte');
select is((select count(*)::int from public.notifications where kind = 'system'
           and user_id = '33333333-3333-3333-3333-333333333333' and title like '%Paiements en attente%'), 1,
          '16. super administrateur prévenu');
select is(jsonb_array_length(public.ops_run_scan() -> 'opened'), 0, '17. pas de seconde alerte pour le même problème');
update public.payments set status = 'failed' where transaction_id = 'T-stuck';
select ok((public.ops_run_scan() ->> 'resolved')::int >= 1, '18. alerte close quand le problème disparaît');

select * from finish();
rollback;
