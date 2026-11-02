-- Correctif 0.32.0 : la table match_analyses donne ses droits de lecture colonne par colonne
-- (migration 32 : fournisseur, modèle et prompt réservés au super administrateur). La colonne
-- language ajoutée par la migration 49 n'était pas lisible : l'app, qui filtre sur la langue,
-- recevait un refus (« Le serveur a refusé la demande ») à l'ouverture d'un match.
grant select (language) on public.match_analyses to authenticated;
