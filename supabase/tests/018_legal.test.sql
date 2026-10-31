-- Tests pgTAP du LOT 12 : documents légaux lisibles sans connexion, acceptation par version.
begin;
select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('11111111-1111-1111-1111-111111111111', 'admin');

set local role anon;
select is((select count(distinct code)::int from public.legal_documents), 3, '1. les 3 documents sont lisibles sans connexion');
select throws_ok($$ select public.my_legal_status() $$, '42501', null, '2. état d''acceptation refusé sans connexion');

set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(jsonb_array_length(public.my_legal_status() -> 'pending'), 2, '3. CGU et confidentialité à accepter');
select throws_ok($$ select public.admin_publish_legal('terms', '2026-11-01', 'CGU', repeat('x', 60)) $$, '42501', null,
                 '4. publication réservée à l''administration');
select is(jsonb_array_length(public.accept_legal(
            (select array_agg((p ->> 'id')::bigint) from jsonb_array_elements(public.my_legal_status() -> 'pending') p)) -> 'pending'), 0,
          '5. acceptation enregistrée');
select is((select count(*)::int from public.legal_acceptances), 2, '6. l''utilisateur voit ses acceptations');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.admin_publish_legal('terms', '2026-11-01', 'Conditions générales d''utilisation', repeat('Nouvelle version. ', 10)) $$,
                '7. nouvelle version des CGU publiée');
select is((select count(*)::int from public.legal_acceptances), 0, '8. un utilisateur ne voit pas les acceptations des autres');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.my_legal_status() #>> '{pending,0,version}', '2026-11-01', '9. la nouvelle version redemande l''acceptation');
select throws_ok($$ select public.accept_legal(array[(select id from public.legal_documents where code = 'terms' and version = '2026-10-31')]) $$,
                 '22023', null, '10. une version périmée ne peut plus être acceptée');
reset role;

select * from finish();
rollback;
