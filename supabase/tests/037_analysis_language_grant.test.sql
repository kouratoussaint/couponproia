-- Tests pgTAP : la langue d'une analyse est lisible par l'app (correctif 0.32.0).
begin;
select plan(2);

select ok(has_column_privilege('authenticated', 'public.match_analyses', 'language', 'SELECT'),
  'colonne language lisible par un utilisateur connecté');

insert into auth.users (id, email, raw_user_meta_data) values
  ('37373737-3737-3737-3737-373737373737', 'lecteur@test.local', '{}');
set local role authenticated;
set local request.jwt.claims = '{"sub": "37373737-3737-3737-3737-373737373737", "role": "authenticated"}';
select lives_ok($$ select id, language from public.match_analyses where language = 'en' limit 1 $$,
  'filtre sur la langue accepté (ce que fait l''app)');

select * from finish();
rollback;
