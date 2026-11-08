-- Tests pgTAP : lancement d'une expérience du moteur (laboratoire, 08/11/2026).
begin;
select plan(5);

select ok(not has_function_privilege('authenticated', 'app_private.invoke_engine_experiment(text)', 'execute'),
  'réservé au serveur (pas aux utilisateurs connectés)');
select ok(not has_function_privilege('anon', 'app_private.invoke_engine_experiment(text)', 'execute'),
  'réservé au serveur (pas aux visiteurs)');
select throws_ok($$ select app_private.invoke_engine_experiment('x; drop') $$, '22023', null, 'nom d''expérience contrôlé');

select ok(not has_function_privilege('authenticated', 'app_private.invoke_engine_experiment(text, jsonb)', 'execute'),
  'version avec options réservée au serveur');
select throws_ok($$ select app_private.invoke_engine_experiment('moteur-3', '[1]'::jsonb) $$, '22023', null, 'options : un objet');

select * from finish();
rollback;
