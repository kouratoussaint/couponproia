-- Tests pgTAP : fournisseur et modèle d'IA réservés au super administrateur ;
-- textes des notifications au vouvoiement.
begin;
select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values
  ('11111111-1111-1111-1111-111111111111', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'super_admin');

insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'A'), ('api_football', 't-b', 'B');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '1 day', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';
insert into public.match_analyses (match_id, engine_version, provider, model, status, stats, source_updated_at)
select id, 'poisson-1.1', 'gemini', 'gemini-test', 'stats_only', '{}', now() from public.matches where provider_ref = 'm1';
insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint, analysis)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Coupon du jour', 'd', 'equilibre', 2, 0.5, 'published',
        now(), now(), now() + interval '1 day', now() + interval '1 day', 'v', 'f1',
        '{"source": "ia", "summary": "s", "ai_provider": "gemini", "ai_model": "gemini-test"}');

select ok(exists (select 1 from public.role_permissions where role_id = 'super_admin' and permission_id = 'ai.providers')
          and not exists (select 1 from public.role_permissions where role_id = 'admin' and permission_id = 'ai.providers'),
          '1. ai.providers : super administrateur seulement');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select engine_version from public.match_analyses limit 1), 'poisson-1.1', '2. l''analyse reste lisible');
select throws_ok($$ select provider from public.match_analyses $$, '42501', null, '3. fournisseur illisible pour un utilisateur');
select ok((select (analysis ? 'summary') and not (analysis ? 'ai_model') and not (analysis ? 'ai_provider')
           from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[])),
          '4. analyse du coupon sans modèle d''IA pour un utilisateur');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select throws_ok($$ select model from public.match_analyses $$, '42501', null, '5. modèle illisible pour un administrateur');
select throws_ok($$ select public.analysis_tech((select id from public.match_analyses limit 1)) $$, '42501', null,
                 '6. détails techniques refusés à un administrateur');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.analysis_tech((select id from public.match_analyses limit 1)) ->> 'model', 'gemini-test',
          '7. le super administrateur voit le modèle');
select is((select analysis ->> 'ai_model' from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[])),
          'gemini-test', '8. et celui du coupon');
reset role;

select ok(pg_get_functiondef('app_private.on_credits_low()'::regprocedure) like '%Il vous reste%',
          '9. notification de crédits au vouvoiement');
select ok(pg_get_functiondef('app_private.notify_morning()'::regprocedure) like '%Votre rendez-vous du matin%',
          '10. rendez-vous du matin au vouvoiement');

select * from finish();
rollback;
