-- Tests pgTAP : cohérence des coupons avec l'analyse IA, modification par l'équipe.
begin;
select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('33333333-3333-3333-3333-333333333333', 'super@test.local', '{}');
insert into public.user_roles (user_id, role_id) values ('33333333-3333-3333-3333-333333333333', 'super_admin');
insert into public.teams (provider_id, provider_ref, name) values ('api_football', 't-a', 'Lecce'), ('api_football', 't-b', 'Genoa');
insert into public.matches (provider_id, provider_ref, competition_id, season, kickoff_at, status, home_team_id, away_team_id)
select 'api_football', 'm1', c.id, 2026, now() + interval '5 hours', 'scheduled', h.id, a.id
from public.competitions c, public.teams h, public.teams a
where c.provider_ref = '39' and h.provider_ref = 't-a' and a.provider_ref = 't-b';

select is(app_private.ai_contradiction('DC.1X', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "1X2.AWAY"}]}'),
          '1X2.AWAY', '1. « Lecce ou nul » contredit « Victoire Genoa »');
select is(app_private.ai_contradiction('DC.X2', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "1X2.AWAY"}]}'),
          null, '2. « Nul ou Genoa » est cohérent');
select is(app_private.ai_contradiction('OU.OVER.2.5', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "1X2.AWAY"}]}'),
          null, '3. marché non tranché');
select is(app_private.ai_contradiction('OU.UNDER.2.5', '{"recommandation_possible": true, "marches_envisageables": [{"cle": "OU.OVER.2.5"}]}'),
          'OU.OVER.2.5', '4. moins de buts contre plus de buts');
select is(app_private.ai_contradiction('1X2.HOME', '{"recommandation_possible": false, "marches_envisageables": [{"cle": "1X2.AWAY"}]}'),
          null, '5. sans recommandation : pas de contrainte');

insert into public.coupons (id, category, title, description, risk_level, total_odd, combined_probability,
  status, publish_at, first_kickoff_at, last_kickoff_at, engine_version, fingerprint)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'equilibre', 'Coupon équilibré · dimanche', 'd', 'equilibre', 1.57, 0.6,
        'pending_review', now() + interval '1 hour', now() + interval '5 hours', now() + interval '5 hours', 'v', 'f1');
insert into public.coupon_selections (coupon_id, position, match_id, market_code, outcome_code, selection_key, odd,
  odds_captured_at, model_probability, reliability, justification)
select 'aaaaaaaa-0000-0000-0000-000000000001', 1, id, 'DC', '1X', 'DC.1X', 1.57, now(), 0.6, 'bonne', 'j'
from public.matches where provider_ref = 'm1';
insert into public.match_analyses (match_id, engine_version, prompt_key, prompt_version, status, stats, analysis, source_updated_at)
select id, 'v', 'match_analysis', 1, 'ok', '{}',
       '{"recommandation_possible": true, "marches_envisageables": [{"cle": "1X2.AWAY", "justification": "Genoa"}]}', now()
from public.matches where provider_ref = 'm1';

select ok((select count(*) from app_private.ops_issues() where code = 'coupon_vs_ai') = 1, '6. alerte : coupon contraire à l''IA');
select ok((select body like '%« Lecce ou nul » contre le pronostic « Victoire Genoa »%' from app_private.ops_issues()
           where code = 'coupon_vs_ai'), '7. détail lisible');

-- Validation humaine : le choix de l'équipe prime, plus d'alerte
set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select public.admin_review_coupon('aaaaaaaa-0000-0000-0000-000000000001', true, null);
reset role;
select ok((select ai_override from public.coupons where id = 'aaaaaaaa-0000-0000-0000-000000000001'), '8. validation humaine notée');
select is((select count(*)::int from app_private.ops_issues() where code = 'coupon_vs_ai'), 0, '9. plus d''alerte après validation');

select * from finish();
rollback;
