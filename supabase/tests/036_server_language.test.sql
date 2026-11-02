-- Tests pgTAP : textes du serveur dans la langue du profil (D5 partie 2).
begin;
select plan(19);

insert into auth.users (id, email, raw_user_meta_data) values
  ('36363636-3636-3636-3636-363636363601', 'fr@test.local', '{}'),
  ('36363636-3636-3636-3636-363636363602', 'en@test.local', '{"locale": "en"}'),
  ('36363636-3636-3636-3636-363636363603', 'xx@test.local', '{"locale": "de"}');

select is((select locale from public.profiles where id = '36363636-3636-3636-3636-363636363602'), 'en',
  'inscription en anglais : langue du profil');
select is((select locale from public.profiles where id = '36363636-3636-3636-3636-363636363603'), 'fr',
  'langue inconnue : français');

-- Notification : texte anglais pour un profil anglais, français sinon, français si pas de version anglaise.
select app_private.notify('36363636-3636-3636-3636-363636363601', 'system', 'Bonjour', 'Texte', null, 't1', 'Hello', 'Text');
select app_private.notify('36363636-3636-3636-3636-363636363602', 'system', 'Bonjour', 'Texte', null, 't1', 'Hello', 'Text');
select app_private.notify('36363636-3636-3636-3636-363636363602', 'system', 'Bonjour', 'Texte', null, 't2');
select is((select title from public.notifications where user_id = '36363636-3636-3636-3636-363636363601' and dedupe_key = 't1'),
  'Bonjour', 'profil français : texte français');
select is((select title || ' / ' || body from public.notifications where user_id = '36363636-3636-3636-3636-363636363602' and dedupe_key = 't1'),
  'Hello / Text', 'profil anglais : texte anglais');
select is((select title from public.notifications where user_id = '36363636-3636-3636-3636-363636363602' and dedupe_key = 't2'),
  'Bonjour', 'sans version anglaise : français');

-- Libellés et nombres.
select is(app_private.selection_label('1X2.HOME', 'Lille', 'Lens', 'en'), 'Lille win', 'victoire en anglais');
select is(app_private.selection_label('OU.OVER.2.5', 'Lille', 'Lens', 'en'), 'Over 2.5 goals', 'plus de buts en anglais');
select is(app_private.selection_label('OU.OVER.2.5', 'Lille', 'Lens'), 'Plus de 2,5 buts', 'français inchangé');
select is(app_private.selection_label('DNB.AWAY', 'Lille', 'Lens'), 'Lens (remboursé si nul)', 'DNB en français');
select is(app_private.selection_label('TTH.OVER.0.5', 'Lille', 'Lens', 'en'), 'Lille: over 0.5 goal', 'but par équipe en anglais');
select is(app_private.fcfa(12500, 'en'), '12,500 FCFA', 'montant en anglais');
select is(app_private.odd_txt(1.95, 'en') || ' / ' || app_private.odd_txt(1.95), '1.95 / 1,95', 'cote selon la langue');
select is(app_private.title_en('Prudent · lundi 2 novembre'), 'Cautious · Monday 2 November', 'titre de coupon traduit');
select is(app_private.title_en('Coupon de l''assistant · 3 sélections'), 'Assistant coupon · 3 selections',
  'titre de l''assistant traduit');
select is(app_private.title_en('Mon combiné · 1 sélection'), 'Mon combiné · 1 selection', 'nom choisi gardé');

-- Mots interdits en anglais.
select ok(app_private.has_forbidden_words('A guaranteed win tonight') and app_private.has_forbidden_words('Big winnings'),
  'mots interdits anglais refusés');
select ok(not app_private.has_forbidden_words('Make sure you check the line-ups'), 'phrase anglaise ordinaire acceptée');

-- Documents légaux traduits, lisibles sans connexion.
set local role anon;
select is((select count(*)::int from public.legal_translations where language = 'en'), 3, 'trois traductions anglaises');
reset role;

-- Analyses : français par défaut.
select is((select column_default from information_schema.columns
           where table_name = 'match_analyses' and column_name = 'language'), '''fr''::text', 'analyse en français par défaut');

select * from finish();
rollback;
