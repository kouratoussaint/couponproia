# LOT 4 — Coupons générés par la plateforme

Statut au 30/10/2026 : **livré et déployé.** Le moteur tourne toutes les 15 minutes. Tant que
l'offre gratuite d'API-Football est utilisée (archive 2024/25, aucun match à venir, aucune cote),
chaque génération se termine par un **refus motivé** (« Aucun match programmé dans les 24 prochaines
heures »). Les premiers coupons réels paraîtront dès l'activation de l'offre Pro, sans nouvel APK.

## 1. Résumé

- **Correction des analyses (retour du test Lille – Lyon)** : une seule issue par marché (1X2 et
  double chance comptent pour un), justification obligatoirement appuyée sur la fiche (forme, bilan,
  buts attendus, classement, confrontations, cote) ; prompt v3 ; les analyses produites avec un ancien
  prompt ne sont plus servies.
- **Profils de génération** (6 par défaut, modifiables dans l'app) : catégorie, mode programmé ou
  continu, publication automatique ou validation humaine, heures de génération, délai de publication,
  critères (sélections, cotes par sélection et totale, marchés, probabilité minimale du modèle, écart
  minimal avec le marché, fiabilité minimale, fenêtre de matchs, délai avant coup d'envoi, âge maximal
  des cotes, plafond par compétition).
- **Générateur** (code déterministe, jamais l'IA) :
  1. candidats = chaque issue cotée d'un match programmé, avec probabilité du modèle, probabilité
     implicite (marge retirée), écart, fiabilité ;
  2. filtres du profil, et seulement les familles de marchés où le moteur bat la référence
     (aujourd'hui 1X2 et double chance) ;
  3. au plus une sélection par match ; parmi les combinaisons dont la cote totale est dans la
     fourchette, celle que le modèle juge **la plus probable** ; plusieurs coupons d'une même
     génération diffèrent d'au moins la moitié de leurs sélections ;
  4. risque estimé (prudent / équilibré / audacieux) selon la probabilité combinée.
- **Contrôle qualité (prompt §7.5)** avant enregistrement, puis à nouveau juste avant publication :
  match existant et programmé, coup d'envoi assez lointain, issue toujours cotée, cote récente, pas
  deux sélections d'un même match, pas de doublon en circulation, cote totale recalculée et dans la
  fourchette, données de calendrier fraîches, plafond quotidien. Sinon : refus motivé, consigné.
- **Modes de publication** :
  - A. programmé : créneaux en heure de Ouagadougou (par défaut génération 07:00, publication 08:00 ;
    prudent aussi à 13:00), un créneau ne tourne qu'une fois (rattrapage d'une heure si un passage
    est manqué) ;
  - B. continu : profil « Opportunités du moment » (désactivé par défaut, validation humaine) relancé
    seulement si de nouvelles cotes sont arrivées et au plus toutes les 3 h.
- **Publication et historique** : statuts à valider → prêt → publié (ou rejeté, expiré si un match
  commence avant publication, retiré) ; chaque changement est historisé avec son motif ; un coupon
  publié est **immuable** (garanti par la base) : cote initiale conservée, cote actuelle affichée à
  part, toute correction passe par un retrait motivé et visible.
- **Textes** : justification de chaque sélection calculée à partir des données (modèle contre marché,
  buts attendus, forme, classement) ; analyse générale rédigée par l'IA et vérifiée (chiffres présents
  dans la fiche, aucun mot de certitude), sinon texte calculé.
- **App** : onglet Coupons (catégories, en cours / précédents), fiche coupon (sélections, cotes,
  probabilités, fiabilité, justification, analyse, historique, source et version du moteur) ;
  administration « Générations de coupons » : profils (activation, réglages, « Générer maintenant »),
  coupons à valider ou programmés, journal des générations avec motifs de refus ; retrait d'un coupon.

## 2. Migrations

10. `prompt_v3` : consignes « une issue par marché » et « justification fondée ».
11. `platform_coupons` : `coupon_profiles`, `generation_runs` (créneau unique), `coupons` (empreinte
    unique en circulation, immuabilité par déclencheur), `coupon_selections` (un match par coupon),
    `coupon_status_history` (alimenté automatiquement), RLS (coupons publiés visibles par les
    connectés, le reste réservé à `generation.manage`), RPC auditées `admin_review_coupon`,
    `admin_withdraw_coupon`, `admin_update_coupon_profile`, 6 profils, flag `platform_coupons`,
    réglages `coupons.*`, prompt `coupon_summary`, tâche `coupon-engine-tick` (5, 20, 35, 50 de
    chaque heure).

Edge Function : `coupon-engine` (secret d'exploitation ou administrateur).

## 3. Tests

| Suite | Résultat |
| --- | --- |
| SQL : 30 + 16 + 11 + 17 (coupons : visibilité, doublons, un match par coupon, immuabilité, historique, validation humaine, réglages) | **74/74** |
| Deno : moteur, IA (dont une issue par marché, justification fondée), générateur (critères, motifs d'exclusion, combinaison la plus probable, coupons distincts, plafond par compétition, risque, contrôle qualité, textes, créneaux horaires et fuseaux) | **42/42** |
| Flutter : analyse statique + 36 tests (dont lecture des coupons et profils) | **réussis** (localement et en CI) |
| Bout en bout : génération à la demande via le secret → refus motivé enregistré | **vérifié** |

## 4. Limites connues

- Pas de coupons réels sans matchs à venir cotés : dépend de l'offre Pro d'API-Football.
- Marchés plus/moins et « les deux marquent » exclus tant que le moteur ne bat pas la référence.
- Visibilité des coupons selon le forfait : LOT 9. Règlement (gagné/perdu) et statistiques : LOT 8.
- Probabilité combinée = produit des probabilités (matchs supposés indépendants) : estimation.

## 5. Bascule vers l'offre Pro (faite le 30/10/2026 au soir)

- Réglages : fin de l'archive, 250 ms entre requêtes, budget 7 000 requêtes/jour, 150 matchs par relevé
  de cotes, saison 2025/26 chargée une fois comme historique (`sports.history_seasons`).
- Relevés de cotes à 6 h, 12 h et 18 h (avant les générations de 7 h et 13 h).
- Premier passage : 5 060 lignes, 35 requêtes ; cotes de 39 matchs des 48 h suivantes (39 requêtes).
- CLI Supabase épinglé (2.122.0) dans le déploiement : « latest » échouait sur une limite de l'API GitHub.

## 6. Moteur poisson-1.1 (correction après les premiers coupons réels)

Les 4 premiers coupons générés (30/10, 17 h 11) contenaient des sélections très éloignées du marché
(+17 à +27 points, ex. « Nul ou Espanyol » à Villarreal : 60 % contre 33 %). Cause : en début de
saison (≈ 9 journées), le moteur n'utilisait que la saison en cours et ramenait toutes les équipes vers
la moyenne, ce qui favorisait les outsiders. Ces coupons sont signalés au propriétaire pour retrait.

Corrections :
- la saison précédente de la compétition entre dans les forces des équipes avec un poids réduit ;
- poids choisi par mesure sur 2025/26 (a priori 2024/25), 1/N/2 :

| Poids de la saison précédente | 0 | 0,25 | **0,5** | 0,75 | 1 |
| --- | --- | --- | --- | --- | --- |
| Brier (référence 0,648) | 0,623 | 0,613 | **0,610** | 0,609 | 0,609 |

  0,5 est retenu (au plateau de l'optimum, plus prudent qu'un poids plein) ;
- nouveau critère `max_edge` (0,10) : une sélection dont le modèle s'écarte de plus de 10 points du
  marché est écartée (désaccord plus souvent dû à une lacune du modèle qu'à une vraie valeur) ;
- les compétitions où le moteur ne bat pas la référence sont exclues des coupons ;
- évaluation hebdomadaire sur la saison précédente et la saison en cours.

Évaluation officielle poisson-1.1 (2 763 matchs, 2025/26 et 2026/27) : Brier **0,607** contre 0,646 ;
issue la plus probable juste **50,5 %** contre 45,5 %. Plus/moins 2,5 (0,496 contre 0,495) et
« les deux marquent » (0,502 contre 0,495) : toujours pas mieux que la référence, toujours exclus.

Aperçu sans écriture après correction : écarts avec le marché de +3 à +10 points (au lieu de +27).
