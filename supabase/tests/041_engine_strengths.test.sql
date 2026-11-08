-- Tests pgTAP : forces du moteur poisson-3.0 (LOT 28).
begin;
select plan(6);

select ok(not has_table_privilege('authenticated', 'public.engine_strengths', 'select'), 'forces : invisibles pour les utilisateurs');
select ok(not has_table_privilege('anon', 'public.engine_strengths', 'select'), 'forces : invisibles pour les visiteurs');
select ok(not has_function_privilege('authenticated', 'app_private.invoke_engine_strengths()', 'execute'), 'calcul réservé au serveur');
select ok(not has_function_privilege('authenticated', 'app_private.invoke_engine_evaluation_for(text)', 'execute'), 'évaluation ciblée réservée au serveur');
select throws_ok($$ select app_private.invoke_engine_evaluation_for('x') $$, '22023', null, 'nom de moteur contrôlé');
select throws_ok($$ insert into public.engine_strengths (engine_version, matches, data) values ('poisson-3.0', -1, '{}') $$, '23514', null, 'nombre de matchs positif');

select * from finish();
rollback;
