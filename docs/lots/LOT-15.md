# Demandes du 01/11 (version 0.22.0)

## « Voir l'analyse » au lieu de « Analyser »
Un match déjà analysé affiche « Voir l'analyse » (accueil, listes), accessible même sans crédit
ni forfait, quel que soit l'état du match. « Analyser » reste réservé aux matchs à venir.

## Publication anticipée (super administrateur)
« Publier maintenant » sur les coupons à valider ou programmés de l'historique, avec
confirmation. Contrôles en direct identiques à la publication programmée (job `publish_now` de
`coupon-engine`, refus `not_publishable` motivé).

## Choix de l'analyse offerte
Écran Console → Analyse offerte : aujourd'hui / demain, choix d'un match, heure du choix
automatique (`featured.auto_pick_hour`, 9 h par défaut). Colonne `featured_matches.chosen_by`.

## Copier un coupon pour son bookmaker
Format bookmaker (codes de pari usuels, cotes, 18+) et bouton facultatif « Ouvrir {site} »
piloté par `bookmaker.link`. Pas d'envoi direct possible : aucun bookmaker n'expose de moyen de
pré-remplir un ticket depuis une application tierce.

## Historique des coupons
Trié par action la plus récente, libellé et heure de la dernière action sur chaque coupon.

## Fournisseurs d'IA
Une IA sans clé (Claude aujourd'hui) passe automatiquement en « Désactivée » et ne bloque plus
l'enregistrement ; le serveur ignore un secours non configuré.

## Accueil
Logos des équipes sur les matchs et sur la carte de l'analyse offerte.

## Assistant IA
Mots-clés et nombres du message prioritaires (nombre de sélections et de coupons, cotes par
match et totale, jour, marchés, risque), rien d'inventé ; prompt `assistant_intent` v2 et
récapitulatif « Demande comprise » en tête de réponse.

## Retouches (version 0.22.1)
- Fiche coupon : historique du plus récent au plus ancien, une icône par étape, la dernière
  mise en couleur.
- Liste des coupons (À jouer, En cours, Résultats, accueil) : risque estimé toujours affiché et
  icône propre à chaque type de coupon (du jour, prudent, équilibré, audacieux, cote élevée,
  multi-compétitions, spécial compétition, spécial marché, opportunités), teintée selon le risque.
