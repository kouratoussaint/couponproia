# LOT 6 — Laboratoire IA et générateur manuel

Statut au 30/10/2026 : **livré et déployé (APK 0.6.0).**

## 1. Résumé

- **Générateur manuel** : dans la fiche d'un match, toucher une cote l'ajoute au coupon en
  construction (une sélection par match ; toucher une autre issue du même match la remplace ; toucher
  la même la retire). Une barre « Mon coupon » affiche le nombre de sélections et une cote
  **indicative**. « Vérifier et enregistrer » envoie la liste au serveur, qui relit chaque match
  (programmé, pas commencé), relit la cote actuelle de chaque issue, calcule les probabilités du modèle
  et **recalcule la cote totale** avant d'enregistrer le coupon dans « Mes coupons ».
- **Analyse** : sélections les plus fragiles, cotes qui ont bougé, matchs commencés ou reportés,
  concentration sur une compétition, marchés non validés par l'évaluation, fiabilité.
- **Optimisation** : pour les 2 sélections les plus fragiles, alternatives plus probables selon le
  modèle (autre issue du même match, ou autre match de cote voisine, fiabilité au moins moyenne, écart
  avec le marché ≤ 10 points), avec la cote et la probabilité du coupon après remplacement. Appliquer
  crée une nouvelle version vérifiée ; l'originale reste.
- **Simulation** (encadré « SIMULATION ») : loi exacte du nombre de sélections justes, 1 000 coupons
  tirés selon les probabilités du modèle (graine fixe, reproductible) avec la fourchette attendue, et
  le retour moyen estimé pour 1 misé. Texte : « ce n'est pas un résultat réel ni une prévision de gain ».
- **Comparaison** de 2 ou 3 coupons : sélections, cote totale, probabilités modèle et marché,
  compétitions, paires possiblement liées (même compétition, même jour), fiabilité faible, marchés non
  validés, sélection la plus fragile.
- Aucun appel à l'IA dans ces outils : **aucun crédit débité**.
- **Correctif du générateur** (retour de l'essai de l'assistant : « 3 matchs, cote proche de 4 »
  donnait 2,80) : la recherche n'explorait que les 40 issues les plus probables, presque toutes à des
  cotes basses ; elle inclut maintenant les issues proches de la cote idéale par sélection. Test de
  non-régression ajouté (il échoue avec l'ancienne recherche).

## 2. Livraison

- Migration 14 `ai_lab` : flag `ai_lab` activé.
- Edge Function `lab` (JWT obligatoire) : `build`, `analyze`, `optimize`, `compare`, `simulate`.
- Stockage des coupons de l'utilisateur mutualisé (assistant et générateur manuel).

## 3. Tests

| Suite | Résultat |
| --- | --- |
| SQL | **92/92** |
| Deno : 58 tests (dont loi du nombre de sélections justes, simulation reproductible et étiquetée, comparaison, alternatives, recherche vers la cote cible) | **58/58** |
| Flutter : analyse statique sans remarque + 41 tests (dont clé d'issue identique au serveur, coupon manuel une sélection par match) | **réussis** |

## 4. Limites connues

- La simulation suppose des matchs indépendants (signalé) ; les paires d'une même compétition le
  même jour sont seulement repérées, pas modélisées.
- Le coupon en construction est gardé en mémoire tant que l'app est ouverte.
