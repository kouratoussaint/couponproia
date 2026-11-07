# Sélection des championnats (0.33.0)

Cahier des charges du Laboratoire (`claude/lot-25-selection-championnats.md`), validé le 03/11 et le 07/11.
Décisions du propriétaire :
- une compétition en observation est visible et utilisable à la main, jamais dans un coupon automatique ;
- la CAN est admise par un forçage du super administrateur ;
- l'écran Compétitions a été validé sur maquette le 07/11.

## Base de données (migration 52)
- `competitions.status` : `inactive`, `observation` ou `active`. `is_active` vaut « observation ou active » et reste tenu à jour par un déclencheur, si bien que les tâches existantes n'ont pas changé.
- Les champs `status_changed_at` / `_by`, `quality_override` / `_by` et `display_name` ont été ajoutés. `display_name` vaut « Nom (Pays) » quand deux compétitions suivies portent le même nom.
- `provider_leagues` : catalogue du fournisseur, lisible seulement par les fonctions de la console.
- Fonctions de la console : `admin_competitions`, `admin_search_league_catalog`, `admin_add_competition`, `admin_set_competition_status`, `admin_set_competition_priority` et `admin_set_competition_override`. Les cinq premières exigent la permission `sports.configure` ; le forçage exige `competitions.override` (super administrateur). Toutes sont tracées dans l'audit.
- Réglage `sports.max_tracked_competitions` (40). Tâche `sports-catalog` le lundi à 03:10.

## Synchronisation
- Tâche `catalog` : `GET /leagues` en une requête (1 251 compétitions au 07/11).
- `daily` ciblée (`competition_id`) : chargement immédiat d'une compétition ajoutée.
- `daily` rafraîchit aussi les matchs des coupons (plateforme et utilisateurs) et des paris non réglés qui ne sont pas terminés au-delà du suivi en direct, quel que soit l'état de leur compétition.

## Moteur et coupons
1. Qualité rangée par identifiant (`details.per_competition_ids`, clés « id:saison ») ; l'affichage garde `per_competition` sous le nom affiché.
2. Coupons automatiques : compétition active, avec un verdict positif ou un forçage. Pour une compétition sans verdict, le motif d'exclusion est « compétition sans verdict du moteur ».
3. Aucun candidat issu d'une compétition inactive ; une compétition en observation est exclue des coupons automatiques (motif « compétition en observation »).
4. Assistant : le pays départage les noms identiques (« Ligue 1 ivoirienne », « Premier League Égypte »). Pour un nom ambigu sans pays, l'assistant retient la compétition principale et propose les autres.

## Application
- Console → Données sportives → Compétitions : liste avec filtres, état, verdict du moteur, matchs à 14 jours, dernière synchronisation et ordre. La fiche d'une compétition sert à changer l'état (avec ses avertissements), l'ordre et le forçage. Le bouton « Ajouter » ouvre le catalogue, avec la couverture de chaque compétition. Écrans en français et en anglais.
- Les compétitions inactives sont masquées des listes de matchs et de la recherche. Les noms affichés s'appliquent partout ; la planification affichée dans la console est corrigée.

## Mise en production (07/11)
- Déploiement relancé après le renouvellement du jeton `SUPABASE_ACCESS_TOKEN`.
- Évaluation du moteur lancée tout de suite : 8 compétitions avec un verdict positif, la CAN sans verdict (22 matchs), donc forcée.
- Catalogue chargé une première fois.
- Les 9 compétitions sont actives.

## Vérifications
- SQL : `038_competition_selection` (26) ; 480 tests au total.
- Deno : catalogue, matchs des coupons non réglés, verdict exigé et forçage, observation exclue, qualité par identifiant, pays dans l'assistant ; 132 au total.
- Flutter : `lot25_test` (5), en français et en anglais ; 257 au total.
