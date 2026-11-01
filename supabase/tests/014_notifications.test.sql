-- Tests pgTAP : notifications (préférences, droits du forfait, heures calmes, doublons, appareils).
begin;
select plan(13);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
update public.user_preferences set quiet_start = 0, quiet_end = 0;  -- pas d'heures calmes par défaut ici
update public.user_preferences set notify_coupons = false where user_id = '22222222-2222-2222-2222-222222222222';

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '30 minutes', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Coupon du jour', 'd', 'equilibre', 3, 0.3, 'ready', now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Coupon prudent', 'd', 'prudent', 2, 0.5, 'ready', now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f2');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select c.id, 1, m.id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.6, 'bonne', 'j'
from public.coupons c, public.matches m where m.provider_ref = 'm1';

update public.coupons set status = 'published', published_at = now();
select is((select count(*)::int from public.notifications where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'coupon'),
          1, '1. FREE : seul le coupon du jour est notifié (le prudent est réservé)');
select is((select count(*)::int from public.notifications where user_id = '22222222-2222-2222-2222-222222222222'),
          0, '2. préférence désactivée : rien');
select is((select route from public.notifications where kind = 'coupon'), '/coupon/aaaaaaaa-0000-0000-0000-000000000001', '3. lien vers le coupon');

update public.coupons set status = 'withdrawn' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
update public.coupons set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select count(*)::int from public.notifications where kind = 'coupon'), 1, '4. pas de doublon');

-- Équipe suivie : rappel avant le match
insert into public.user_favorites (user_id, team_id) select '22222222-2222-2222-2222-222222222222', id from public.teams where provider_ref = 't-a';
select is(app_private.notify_match_reminders(), 1, '5. rappel de match pour l''équipe suivie');
select is(app_private.notify_match_reminders(), 1, '6. relancé…');
select is((select count(*)::int from public.notifications where kind = 'match'), 1, '7. … sans doublon');

-- Heures calmes : envoi différé, notification bien présente
update public.user_preferences set quiet_start = 0, quiet_end = 23 where user_id = '11111111-1111-1111-1111-111111111111';
select app_private.notify('11111111-1111-1111-1111-111111111111', 'result', 'Test', 'Corps', null, 'calme');
select ok((select send_after > now() from public.notifications where dedupe_key = 'calme')
          or extract(hour from now() at time zone 'Africa/Ouagadougou') = 23, '8. heures calmes : envoi différé');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.notifications), 2, '9. ne voit que ses notifications');
select is(public.mark_notifications_read(null), 2, '10. tout marquer comme lu');
select lives_ok($$ select public.register_device(repeat('x', 40), 'android', '0.14.0') $$, '11. enregistrer un appareil');
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select lives_ok($$ select public.register_device(repeat('x', 40), 'android', '0.14.0') $$, '12. l''appareil passe au compte connecté');
reset role;
select is((select user_id::text from public.device_tokens), '22222222-2222-2222-2222-222222222222', '13. un seul propriétaire par appareil');

select * from finish();
rollback;
