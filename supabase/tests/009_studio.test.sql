-- Tests pgTAP du LOT 7 : modèles selon le forfait, identité visuelle, mots interdits, quota d'exports,
-- aucun visuel d'un coupon réservé ou d'un coupon d'un autre utilisateur.
begin;
select plan(17);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values
  -- Matchs terminés : visible par tous, y compris le forfait FREE (règle du 01/11)
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Du jour', 'd', 'equilibre', 3, 0.3, 'published', now(), now(),
   now() - interval '4 hours', now() - interval '3 hours', 'v', 'f1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Prudent à venir', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f2');
insert into public.user_coupons (id, user_id, status, title, total_odd, combined_probability, risk_level, engine_version, fingerprint)
values ('cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'saved', 'Bob', 2, 0.5, 'prudent', 'v', 'fb');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

-- 1-4 : droits FREE
select is(public.my_studio() ->> 'branding', 'none', 'FREE : pas de personnalisation');
select is((public.my_studio() ->> 'watermark')::boolean, true, 'FREE : mention Coupon Pro IA imposée');
select is((select count(*)::int from jsonb_array_elements(public.my_studio() -> 'templates') t where (t ->> 'available')::boolean), 2,
          'FREE : 2 modèles accessibles');
select throws_ok($$ select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'ticket', 'square', 'png') $$,
                 '42501', null, 'FREE : modèle réservé refusé');

-- 5-9 : coupons
select is((public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'classique', 'square', 'png') ->> 'exports_today')::int, 1,
          'export du coupon du jour journalisé');
select throws_ok($$ select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000002', 'classique', 'story', 'png') $$,
                 '42501', null, 'pas de visuel d''un coupon réservé avant le coup d''envoi');
select throws_ok($$ select public.studio_export('user', 'cccccccc-0000-0000-0000-000000000001', 'classique', 'story', 'png') $$,
                 '42501', null, 'pas de visuel du coupon d''un autre utilisateur');
select throws_ok($$ select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'classique', 'banniere', 'png') $$,
                 '23514', null, 'format inconnu refusé');
select throws_ok($$ insert into public.generated_assets (user_id, source_kind, source_id, template_code, format, file_type)
                    values ('11111111-1111-1111-1111-111111111111', 'user', gen_random_uuid(), 'classique', 'square', 'png') $$,
                 '42501', null, 'le journal ne s''écrit que par studio_export');

-- 10-11 : quota (3 par jour en FREE)
select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'clair', 'story', 'jpg');
select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'clair', 'portrait', 'pdf');
select is((public.my_studio() ->> 'exports_today')::int, 3, 'trois exports comptés');
select throws_ok($$ select public.studio_export('platform', 'aaaaaaaa-0000-0000-0000-000000000001', 'clair', 'story', 'png') $$,
                 '42501', null, 'FREE : quatrième export du jour refusé');

-- 12-13 : identité visuelle FREE
select throws_ok($$ insert into public.user_branding (user_id, display_name) values ('11111111-1111-1111-1111-111111111111', 'Alice Tips') $$,
                 '42501', null, 'FREE : nom de Tipster réservé à STARTER');
select lives_ok($$ insert into public.user_branding (user_id) values ('11111111-1111-1111-1111-111111111111') $$,
                'FREE : une identité vide reste possible');
reset role;

-- STARTER pour Alice
insert into public.subscriptions (user_id, plan_code, period_start, period_end, source)
values ('11111111-1111-1111-1111-111111111111', 'STARTER', now(), now() + interval '1 month', 'admin');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
-- 14-17
select lives_ok($$ update public.user_branding set display_name = 'Alice Tips', primary_color = '#112233'
                   where user_id = '11111111-1111-1111-1111-111111111111' $$, 'STARTER : nom et couleurs');
select throws_ok($$ update public.user_branding set display_name = 'Gain sûr chaque jour'
                    where user_id = '11111111-1111-1111-1111-111111111111' $$,
                 '22023', null, 'mots interdits refusés dans le nom affiché');
select throws_ok($$ update public.user_branding set signature = 'Par Alice'
                    where user_id = '11111111-1111-1111-1111-111111111111' $$,
                 '42501', null, 'STARTER : signature réservée à PRO TIPSTER');
select is((select count(*)::int from jsonb_array_elements(public.my_studio() -> 'templates') t where (t ->> 'available')::boolean), 4,
          'STARTER : 4 modèles accessibles');
reset role;

select * from finish();
rollback;
