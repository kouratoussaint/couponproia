# Lot 16 : simulateur de mise, carnet, alertes de cote, transparence (version 0.23.0)

Propositions validées le 01/11 : A (A1–A3), B1, B2, D1. Ensuite : lot 17 (C1, C3, C4, B3),
lot 18 (B6, D4, E1, E2), puis D2, B4, B5, D5, D6, C5. Non retenues : C2, D3.

## A. Simulateur de mise
Feuille commune (`features/simulator`) ouverte depuis le coupon, Mes coupons, le Laboratoire,
l'analyse (pronostic et lignes de marché) et les cotes d'un match. Calculs purs
(`stake_math.dart`) : retour, net, prélèvement, valeur moyenne estimée, cote actuelle, annulation.

## B1. Carnet de paris
Table `bet_journal`, RPC `journal_add` / `journal_update`, règlement dans `settle-coupons`
(`journalOutcome`), bilan par mois, budget mensuel et plafond par pari (Jeu responsable).

## B2. Alertes de cote
Table `coupon_watches`, RPC `set_coupon_watch`, tâche `notify-odds-moves` (10 min), seuil
`alerts.odds_move_percent`.

## D1. Transparence
`platform_performance` publie `settled` et `returned` (total et par catégorie) ; écran
Performances : résultat à mise fixe et graphique de calibration.
