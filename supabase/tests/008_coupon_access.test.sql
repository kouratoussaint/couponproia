-- Tests pgTAP : l'analyse et l'empreinte d'un coupon réservé ne sont pas lisibles avant le coup d'envoi.
begin;
select plan(8);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}');

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint, analysis)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'du_jour', 'Du jour', 'd', 'equilibre', 3, 0.3, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f1', '{"analyse_generale": "texte du jour", "source": "calcul"}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'prudent', 'Prudent à venir', 'd', 'prudent', 2, 0.5, 'published', now(), now(),
   now() + interval '1 day', now() + interval '1 day', 'v', 'f2', '{"analyse_generale": "équipe A gagne", "source": "ia"}'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'prudent', 'Prudent passé', 'd', 'prudent', 2, 0.5, 'published', now() - interval '3 days',
   now() - interval '3 days', now() - interval '2 days', now() - interval '2 days', 'v', 'f3', '{"analyse_generale": "passé"}'),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'prudent', 'Brouillon', 'd', 'prudent', 2, 0.5, 'pending_review', now(), null,
   now() + interval '1 day', now() + interval '1 day', 'v', 'f4', '{"analyse_generale": "brouillon"}');

set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select throws_ok($$ select analysis from public.coupons limit 1 $$, '42501', null, 'colonne analysis non lisible directement');
select throws_ok($$ select fingerprint from public.coupons limit 1 $$, '42501', null, 'colonne fingerprint non lisible directement');
select is((select count(*)::int from public.coupons), 3, 'les autres colonnes restent lisibles (coupons publiés)');
select is((select analysis ->> 'analyse_generale' from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000001'::uuid])),
          'texte du jour', 'FREE : analyse du coupon du jour visible');
select is((select analysis ->> 'analyse_generale' from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000002'::uuid])),
          null, 'FREE : analyse d''un coupon réservé masquée avant le coup d''envoi');
select is((select locked from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000002'::uuid])), true, 'coupon signalé comme réservé');
select is((select analysis ->> 'analyse_generale' from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000003'::uuid])),
          'passé', 'après le coup d''envoi, l''analyse est publique');
select is((select count(*)::int from public.coupon_analyses(array['aaaaaaaa-0000-0000-0000-000000000004'::uuid])), 0,
          'un coupon non publié reste invisible');
reset role;

select * from finish();
rollback;
