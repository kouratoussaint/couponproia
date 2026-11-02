-- Langue de l'interface (D5, 02/11) : français ou anglais, choisie dans Profil → Apparence.
-- Enregistrée sur le profil pour que le serveur puisse ensuite écrire dans la bonne langue
-- (notifications, e-mails : deuxième partie de D5).
alter table public.profiles drop constraint if exists profiles_locale_check;
alter table public.profiles add constraint profiles_locale_check check (locale in ('fr', 'en'));
grant update (locale) on public.profiles to authenticated;
