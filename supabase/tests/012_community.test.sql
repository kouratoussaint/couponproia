-- Tests pgTAP du LOT 10 : profils Tipsters, publication immuable, visibilité, abonnements,
-- commentaires, réactions, blocages, signalements, modération, statistiques vérifiées.
begin;
select plan(32);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"display_name": "Alice"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{"display_name": "Bob"}'),
  ('33333333-3333-3333-3333-333333333333', 'carol@test.local', '{"display_name": "Carol"}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'moderator');
insert into public.subscriptions (user_id, plan_code, period_start, period_end, source)
values ('11111111-1111-1111-1111-111111111111', 'PRO_TIPSTER', now(), now() + interval '1 month', 'admin');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', x.ref, c.id, 2026, x.k, 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a,
     (values ('m-futur', now() + interval '1 day'), ('m-passe', now() - interval '1 hour')) as x(ref, k)
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

insert into public.user_coupons (id, user_id, status, title, total_odd, combined_probability, risk_level, engine_version, fingerprint) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'saved', 'Mon coupon', 1.8, 0.55, 'prudent', 'v', 'f1'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'saved', 'Privé', 1.8, 0.55, 'prudent', 'v', 'f2'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'saved', 'Trop tard', 1.8, 0.55, 'prudent', 'v', 'f3');
insert into public.user_coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select x.c::uuid, 1, m.id, '1X2', 'HOME', '1X2.HOME', 1.8, now(), 0.55, 'bonne', 'j'
from public.matches m,
     (values ('cccccccc-0000-0000-0000-000000000001', 'm-futur'), ('cccccccc-0000-0000-0000-000000000002', 'm-futur'),
             ('cccccccc-0000-0000-0000-000000000003', 'm-passe')) as x(c, ref)
where m.provider_ref = x.ref;

set local role authenticated;

-- Bob (FREE) ----------------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select throws_ok($$ insert into public.tipster_profiles (user_id, handle, display_name) values ('22222222-2222-2222-2222-222222222222', 'bob', 'Bob') $$,
                 '42501', null, '1. FREE : pas de profil Tipster');
select is((public.my_community() ->> 'can_publish')::boolean, false, '2. FREE : ne peut pas publier');

-- Alice (PRO TIPSTER) -------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ insert into public.tipster_profiles (user_id, handle, display_name, bio) values ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice', 'Gain sûr tous les jours') $$,
                 '22023', null, '3. bio : mots interdits refusés');
select lives_ok($$ insert into public.tipster_profiles (user_id, handle, display_name, bio) values ('11111111-1111-1111-1111-111111111111', 'Alice_Tips', 'Alice', 'Analyses de Premier League') $$,
                '4. PRO TIPSTER : profil créé');
select is((select handle from public.tipster_profiles), 'alice_tips', '5. identifiant en minuscules');
select throws_ok($$ update public.tipster_profiles set status = 'suspended' $$, '42501', null, '6. statut réservé à la modération');
select ok(public.publish_user_coupon('cccccccc-0000-0000-0000-000000000001', 'Ma sélection du jour') > 0, '7. coupon publié');
select throws_ok($$ select public.publish_user_coupon('cccccccc-0000-0000-0000-000000000001') $$, '22023', null, '8. pas deux fois');
select throws_ok($$ select public.publish_user_coupon('cccccccc-0000-0000-0000-000000000003') $$, '22023', null, '9. trop tard après le coup d''envoi');
select throws_ok($$ select public.publish_user_coupon('cccccccc-0000-0000-0000-000000000002', '100% garanti') $$, '22023', null, '10. commentaire : mots interdits');
select throws_ok($$ update public.user_coupons set title = 'Autre' where id = 'cccccccc-0000-0000-0000-000000000001' $$, '42501', null, '11. coupon publié : titre figé');
select throws_ok($$ update public.user_coupons set status = 'archived' where id = 'cccccccc-0000-0000-0000-000000000001' $$, '42501', null, '12. coupon publié : pas d''archivage');
select throws_ok($$ delete from public.user_coupons where id = 'cccccccc-0000-0000-0000-000000000001' $$, '42501', null, '13. coupon publié : pas de suppression');
select ok(public.create_text_post('Le week-end s''annonce serré en Premier League.') > 0, '14. publication texte');
select ok((public.tipster_stats('11111111-1111-1111-1111-111111111111') -> 'all_time' ->> 'published')::int = 1, '15. statistiques : 1 coupon publié');
reset role;

-- Le serveur règle : modification autorisée du seul résultat.
select throws_ok($$ update public.user_coupon_selections set odd = 3 where coupon_id = 'cccccccc-0000-0000-0000-000000000001' $$,
                 '42501', null, '16. sélections publiées figées');
select lives_ok($$ update public.user_coupon_selections set result = 'won' where coupon_id = 'cccccccc-0000-0000-0000-000000000001';
                   update public.user_coupons set result = 'won', settled_odd = 1.8, settled_at = now() where id = 'cccccccc-0000-0000-0000-000000000001' $$,
                '17. règlement accepté');

set local role authenticated;
-- Bob lit, suit, réagit, commente -----------------------------------------------------------
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.user_coupons), 1, '18. Bob voit le coupon publié, pas le privé');
select is((select count(*)::int from public.user_coupon_selections), 1, '19. … et ses sélections');
select lives_ok($$ insert into public.tipster_followers (follower_id, tipster_id) values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111') $$, '20. suivre');
select lives_ok($$ insert into public.post_reactions (post_id, user_id) select id, '22222222-2222-2222-2222-222222222222' from public.posts where kind = 'coupon' $$, '21. réagir');
select lives_ok($$ insert into public.comments (post_id, author_id, body) select id, '22222222-2222-2222-2222-222222222222', 'Bien vu' from public.posts where kind = 'coupon' $$, '22. commenter');
select throws_ok($$ insert into public.comments (post_id, author_id, body) select id, '22222222-2222-2222-2222-222222222222', 'Gain sûr' from public.posts where kind = 'coupon' $$,
                 '22023', null, '23. commentaire : mots interdits');
select is((select jsonb_array_length(public.community_feed('following'))), 2, '24. fil des abonnements : 2 publications');
select is((select (p ->> 'reactions')::int + (p ->> 'comments')::int from jsonb_array_elements(public.community_feed('following')) p where p ->> 'kind' = 'coupon'),
          2, '25. compteurs réaction et commentaire');
select is(((public.tipster_stats('11111111-1111-1111-1111-111111111111') -> 'all_time') ->> 'won')::int, 1, '26. statistiques : coupon gagné compté');
select lives_ok($$ insert into public.reports (reporter_id, target_type, target_id, reason) select '22222222-2222-2222-2222-222222222222', 'post', id::text, 'spam' from public.posts where kind = 'text' $$, '27. signaler');
select throws_ok($$ select public.moderation_queue() $$, '42501', null, '28. file de modération réservée');

-- Carol (modératrice) -------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select lives_ok($$ select public.moderate('post', (select id::text from public.posts where kind = 'text'), 'hide', 'Hors sujet',
                                         (select id from public.reports limit 1)) $$, '29. masquer une publication');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select jsonb_array_length(public.community_feed('all'))), 1, '30. publication masquée invisible');

-- Alice bloque Bob ----------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
insert into public.user_blocks (blocker_id, blocked_id) values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.posts), 2, '31. l''auteur voit encore toutes ses publications');
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.user_coupons), 0, '32. bloqué : plus rien de visible');
reset role;

select * from finish();
rollback;
