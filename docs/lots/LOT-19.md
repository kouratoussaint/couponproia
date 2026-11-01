# Dates, bouton Analyser, crédits affichés, laboratoire et menus (0.27.0)

## Dates et heures
- À jouer (et En cours) : « Publié le jj/mm/aaaa à hh:mm » sur chaque ligne de coupon.
- Résultats : « Payé le … » (gagné) ou « Terminé le … » (perdu, annulé), d'après `settled_at`.
- Carnet de paris : date avec l'année et l'heure (`dateTimeLabel`).

## Bouton « Analyser »
- Sans droit d'analyse : rouge plein avec cadenas (ouvre l'explication et les forfaits).
- Analyse possible (forfait payant actif ou crédits suffisants) : vert plein.
- Analyse déjà obtenue : orange plein « Voir l'analyse ».
- Couleurs communes : `core/theme/solid_buttons.dart` (contraste vérifié en clair et sombre).

## Crédits affichés sur les boutons
- Analyse au forfait FREE : « Analyser · 1 crédit » (`analysis.credit_cost`).
- Assistant : suggestions payantes, « Remplacer les plus fragiles » et « Analyser » portent le coût
  (`assistant.cost_per_action`) ; mention « Questions gratuites » au-dessus de la saisie.
- Laboratoire au forfait FREE : « Analyser / Optimiser / Simuler / Comparer · 1 crédit ».
- Console → Réglages : section « Coûts en crédits » (analyse, laboratoire, assistant).

## Laboratoire (migration 43)
- Reste visible ; la composition manuelle (build) reste gratuite.
- Forfait FREE : chaque calcul (analyze, optimize, compare, simulate) coûte `lab.credit_cost`
  crédits (1 par défaut, entier de 0 à 50) ; forfaits payants et équipe : gratuit.
- `lab` : refus 402 `credits_required` avant calcul sans assez de crédits ; débit
  (`svc_consume_credits`, type `lab:<action>`) seulement quand le calcul aboutit.
- `admin_set_setting` borne les trois coûts (assistant : au moins 1).

## Menus
- Matchs : onglets « Calendrier » et « Compétitions et classements ».
- Coupons → Résultats : lien « Performances » en tête.
- Assistant IA : onglets « Assistant », « Mes coupons », « Laboratoire »
  (`/assistant?onglet=coupons|laboratoire`) ; les écrans autonomes restent pour les liens directs.
- Profil : groupes Mon jeu, Mon compte (avec l'apparence), Communauté, Aide (support, conditions),
  puis « Supprimer mon compte » (orange plein) et « Se déconnecter » (rouge plein).
- Menu latéral : inchangé (en attente des indications).

## Vérifications
- SQL : test 031 (7) ; Deno : `_shared/lab/pricing_test.ts` (5) ; Flutter : `lot19_test.dart` (8).
