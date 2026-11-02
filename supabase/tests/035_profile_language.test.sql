-- Tests pgTAP : langue de l'interface enregistrée sur le profil (D5).
begin;
select plan(4);

insert into auth.users (id, email, raw_user_meta_data) values
  ('35353535-3535-3535-3535-353535353535', 'langue@test.local', '{}');

select is((select locale from public.profiles where id = '35353535-3535-3535-3535-353535353535'), 'fr',
  'français par défaut');

set local role authenticated;
set local request.jwt.claims = '{"sub": "35353535-3535-3535-3535-353535353535", "role": "authenticated"}';
select lives_ok($$ update public.profiles set locale = 'en' where id = '35353535-3535-3535-3535-353535353535' $$,
  'anglais choisi depuis l''app');
select is((select locale from public.profiles where id = '35353535-3535-3535-3535-353535353535'), 'en',
  'langue enregistrée');
select throws_ok($$ update public.profiles set locale = 'de' where id = '35353535-3535-3535-3535-353535353535' $$,
  '23514', null, 'langue non proposée refusée');

select * from finish();
rollback;
