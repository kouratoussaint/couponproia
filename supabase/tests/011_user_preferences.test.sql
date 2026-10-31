-- Tests pgTAP : préférences du premier lancement (personnelles, compétitions existantes, sans doublon).
begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok($$ update public.user_preferences
                   set favorite_competitions = (select array[id, id] from public.competitions where provider_ref = '39'),
                       level = 'debutant', onboarded_at = now() $$, 'enregistrer ses préférences');
select is((select cardinality(favorite_competitions) from public.user_preferences), 1, 'doublons retirés');
select throws_ok($$ update public.user_preferences set favorite_competitions = array[-1::bigint] $$,
                 '22023', null, 'compétition inconnue refusée');
select throws_ok($$ update public.user_preferences set level = 'pro' $$, '23514', null, 'niveau inconnu refusé');
select is((select count(*)::int from public.user_preferences), 1, 'ne voit que ses préférences');
select is((select level from public.user_preferences where user_id = '22222222-2222-2222-2222-222222222222'), null,
          'les préférences d''un autre compte restent invisibles et intactes');
reset role;

select * from finish();
rollback;
