# LOT 28 — Moteur statistique poisson-3.0

Validé le 08/11 après l'expérience « Moteur 3.0 » du Laboratoire (journal du projet). Choix du
propriétaire : « Plus de 2,5 buts » revient dans les coupons automatiques puisque poisson-3.0
fait mieux que la référence naïve sur ce marché.

## Ce qui change

- **Compétitions reliées** : les forces d'une équipe viennent de tous ses matchs connus
  (championnat, coupes d'Europe et d'Afrique…), chaque match avec la moyenne de buts de sa
  compétition.
- **Niveau des championnats** : estimé sur les matchs entre championnats différents
  (coupes continentales). Un club dominant d'un championnat faible n'est plus surestimé en coupe.
  Dernier calcul : Premier League 1,77 ; Bundesliga 1,36 ; Liga 1,34 ; Serie A 1,31 ;
  Ligue 1 France 1,25 ; Ligue 1 Burkina 0,51 (1 = équipes sans championnat suivi).
- Une équipe qui ne joue qu'une compétition retrouve exactement poisson-2.0 (test).
- Calcul jusqu'au point fixe (0,01 %), attaque puis défense, repris de la veille dans
  l'évaluation.

## Mesure officielle (évaluation du 08/11, 3 480 matchs)

| | poisson-2.0 | poisson-3.0 |
|---|---|---|
| 1X2 log loss (réf. naïve 1,0647) | 0,9938 | **0,9839** |
| 1X2 bon résultat | 51,6 % | **52,6 %** |
| Remboursé si nul, log loss | 0,5888 | **0,5793** |
| Plus de 2,5 buts, Brier (réf. 0,4886) | 0,4908 | **0,4869** |
| Les deux équipes marquent, Brier (réf. 0,4907) | 0,4934 | 0,4922 (toujours exclu) |

## Mise en œuvre

- `_shared/engine/poisson3.ts` : `LeagueModel` (incrémental), `strengthsAt`, `runModel3`,
  photo `toSnapshot` / `fromSnapshot`. Tests `poisson3_test.ts`.
- `_shared/engine/evaluate.ts` : `evaluate3` (même notation et mêmes matchs que poisson-2.0).
- `_shared/engine/strengths_store.ts` : calcul sur tous les matchs terminés ; photo horaire dans
  `engine_strengths` (migration 56, réservée au serveur, deux jours d'historique) ; un match à
  venir lit la photo (moins de 3 h), un match passé est recalculé au coup d'envoi.
- `engine-evaluate` : tâche `{"job":"strengths"}` (planifiée chaque heure) et paramètre
  `engine` ; l'évaluation hebdomadaire évalue désormais poisson-3.0.
- Fiche : `strengths` fourni → poisson-3.0 et note « toutes compétitions et niveau des
  championnats » ; sinon poisson-2.0, indiqué dans `engine_version`.
- Analyses et coupons : `ENGINE_VERSION` = `poisson-3.0`. Les analyses enregistrées avec
  poisson-2.0 sont recalculées à la prochaine ouverture.
- Bascule en deux étapes : évaluation officielle poisson-3.0 enregistrée d'abord (verdicts par
  compétition disponibles), puis bascule des analyses et des coupons.

## Limites connues

- Temps de calcul de l'évaluation hebdomadaire : environ 0,6 s aujourd'hui, environ 1,5 s
  estimées avec 30 compétitions (limite d'un appel serveur : environ 2 s). Au-delà, découper
  l'évaluation en plusieurs appels.
- Mélange moteur / marché des coupons (70 % marché) inchangé ; à remesurer vers 500 matchs
  avec cotes relevées.
