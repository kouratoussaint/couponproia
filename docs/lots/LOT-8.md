# LOT 8 — Résultats, règlement et performances

Statut au 30/10/2026 : **livré et déployé (APK 0.7.0).** Règlement planifié toutes les 30 minutes ;
premier passage réel effectué (aucun coupon dont un match était déjà joué ; 2 coupons enregistrés en
attente). Les premiers règlements réels interviendront avec les matchs du 30 et du 31 octobre.

## 1. Règles de règlement (centralisées, `_shared/settlement/settle.ts`)

| Situation | Sélection |
| --- | --- |
| Match terminé | gagnée ou perdue selon le **score à 90 minutes** (temps additionnel compris, sans prolongation ni tirs au but) |
| Prolongation sans score à 90 min connu | en attente (jamais réglée sur un score incertain) |
| Match annulé, abandonné, attribué sur tapis vert | annulée (void, cote 1,00) |
| Match reporté ou interrompu | en attente, puis annulée s'il n'est pas joué 48 h après l'horaire initial |
| Marché inconnu | annulée |

Coupon : **perdu dès qu'une sélection est perdue** ; gagné si toutes les sélections restantes sont
gagnées, la cote réglée tenant compte des annulations (1,00) ; annulé si toutes sont annulées ; en
attente sinon.

Marchés : 1X2, double chance, plus/moins (0,5 à 3,5), les deux marquent.

## 2. Suivi automatique

- Le score à 90 minutes est désormais lu chez le fournisseur et stocké (`ft_home_goals`,
  `ft_away_goals`) à chaque synchronisation.
- Fonction `settle-coupons` (toutes les 30 min, ou par un administrateur) : coupons de la plateforme
  publiés ou retirés, et coupons enregistrés des utilisateurs ; n'écrit que ce qui change.
- **Historique** (`settlement_history`) : chaque règlement est conservé ; si un résultat change ensuite
  (score corrigé par le fournisseur), le nouveau règlement est marqué « correction », l'ancien reste.
  Les coupons réglés sont revérifiés pendant 3 jours.
- Le contenu d'un coupon publié reste immuable : seuls son résultat et ceux de ses sélections
  s'ajoutent.

## 3. Statistiques

- `platform_performance(jours)` : uniquement les coupons **publiés avant le coup d'envoi** (les retirés
  sont comptés à part) ; coupons, gagnés, perdus, annulés, en cours, taux de réussite, cote moyenne,
  **rendement pour une mise théorique explicite de 1 unité par coupon**, par catégorie, par
  compétition et par marché (sélections), évolution par semaine, et **calibration réelle** (probabilité
  annoncée par le modèle contre taux constaté).
- `my_performance()` : les coupons enregistrés de l'utilisateur (aucun pari réel).
- App : écran **Performances** (menu latéral), onglets Plateforme (périodes Tout / 30 j / 7 j) et Mes
  coupons ; pastilles Gagné / Perdu / Annulé / En cours sur les cartes, les sélections et les fiches.
- Mentions : performances passées sans garantie, aucun gain garanti, Coupon Pro IA n'est pas un
  bookmaker et n'enregistre aucun pari réel.

## 4. Migrations et tests

- Migration 15 `settlement_performance` : colonnes de score à 90 min et de règlement, historique (RLS),
  fonctions de statistiques (sécurité de l'appelant), flag `results_tracking`, tâche `coupon-settle`.

| Suite | Résultat |
| --- | --- |
| SQL : 92 + 10 (règlement d'un coupon publié autorisé, contenu protégé, statistiques publiés seulement, retraits à part, rendement théorique, statistiques personnelles, historique) | **102/102** |
| Deno : 62 tests (dont marchés, score à 90 min, reports, annulations, coupon) | **62/62** |
| Flutter : analyse statique sans remarque + 41 tests | **réussis** |

## 5. Limites connues

- L'évaluation du moteur utilise encore le score final (prolongations comprises) pour les quelques
  matchs de coupe allés en prolongation ; à aligner sur le score à 90 min au LOT 12.
- Statistiques Tipsters : LOT 10.
