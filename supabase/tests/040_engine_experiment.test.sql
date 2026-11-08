-- Tests pgTAP : lancement d'une expérience du moteur (laboratoire, 08/11/2026).
begin;
select plan(3);

select ok(not has_function_privilege('authenticated', 'app_private.invoke_engine_experiment(text)', 'execute'),
  'réservé au serveur (pas aux utilisateurs connectés)');
select ok(not has_function_privilege('anon', 'app_private.invoke_engine_experiment(text)', 'execute'),
  'réservé au serveur (pas aux visiteurs)');
select throws_ok($$ select app_private.invoke_engine_experiment('x; drop') $$, '22023', null, 'nom d''expérience contrôlé');

select * from finish();
rollback;
