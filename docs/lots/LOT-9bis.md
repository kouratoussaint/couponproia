# LOT 9 bis — Expérience match et transparence

Statut au 31/10/2026 : **livré et déployé (APK 0.12.0).** Lot ajouté à la demande du propriétaire
après l'étude d'une application concurrente : on reprend l'organisation des écrans, pas leur
apparence (couleurs, logo, polices et textes restent ceux de Coupon Pro IA).

Décisions du propriétaire : LOT 9 bis avant le LOT 10 ; une analyse offerte par jour pour le forfait
FREE ; pas de parrainage ; notifications via Firebase (à faire au LOT 11).

## 1. Fiche match en 4 onglets

- **En-tête** : logos, noms, forme des 5 derniers matchs (V/N/D), horaire ou score, stade, badge
  « Analyse offerte du jour ».
- **Pronostic** : pronostic de l'IA (ou, à défaut, « issue la plus probable selon le modèle », signalée
  comme telle), avec 3 cases : estimation du modèle, **cote juste** (1 ÷ estimation), cote du marché et
  écart. Résultat 1/N/2, buts attendus, 3 scores exacts. Avant l'analyse : répartition **selon les
  cotes**, clairement distinguée de l'estimation du modèle.
- **Analyse** : « En une phrase », **faits vérifiés** avec une étiquette « source · date heure »
  (classement API-Football, résultats enregistrés, modèle Coupon Pro IA, cotes médianes), lecture de
  l'IA (forme, atouts, tendances, pourquoi ces marchés, ce qui peut tout changer, conclusion),
  encadré **« Si ça ne passe pas »** (issue contraire chiffrée), informations manquantes, heure de
  rédaction et des données.
- **Marchés** : par famille (résultat, double chance, buts, les deux marquent) : estimation, cote
  juste, cote, écart ; avertissement sur les familles où le moteur ne bat pas la référence ; scores
  exacts ; toutes les cotes (touchables pour composer un coupon).
- **Stats** : 3 tuiles (classement, forme, face-à-face), forme (tous les matchs ou domicile /
  extérieur), classement avec zones (qualification, relégation), comparatif de saison en barres face
  à face, séries en cours (« au moins » quand la série couvre tout l'historique enregistré),
  confrontations directes.
- Toutes les probabilités sont aussi dites en langage courant (« environ 2 fois sur 5 »).

## 2. Accueil

Coupon du jour → analyse offerte du jour → matchs du jour (5, compétitions prioritaires d'abord) →
matchs de demain → derniers résultats (5 coupons réglés, **pertes comprises**, lien vers Performances)
→ raccourcis (assistant, laboratoire, studio, mes coupons). Solde de crédits dans la barre du haut.
Chaque section vide affiche un message clair, jamais de contenu fictif.

## 3. Listes et historiques

- Barre 1/N/2 **selon les cotes** (marge retirée) sous chaque match à venir, avec légende.
- Historiques filtrables (coupons de la plateforme et mes coupons) : tout / gagnés / perdus / en
  cours, et 7 j / 30 j / tout. Les pertes restent visibles par défaut.

## 4. Analyse offerte du jour

- Choisie chaque matin (à partir de 5 h, heure de Ouagadougou) par le moteur de coupons : match du
  jour non commencé (plus d'1 h avant), compétition active, cotes relevées ; priorité de la
  compétition, puis nombre de bookmakers, puis horaire. Choix stable pour la journée.
- Son analyse est préparée par le serveur pour être prête à l'ouverture.
- Elle ne compte pas dans le quota d'analyses du jour.

## 5. Premier lancement

- Proposé une seule fois après la connexion (feuille en 3 étapes avec barre de progression) :
  pseudo, compétitions suivies (grille avec logos, facultatif), niveau (débutant, intermédiaire,
  expert). « Plus tard » le ferme définitivement ; tout reste modifiable dans Profil → « Mes
  préférences ».
- Les compétitions suivies passent en tête des matchs du jour et de demain sur l'accueil.
- Le niveau règle seulement les explications : une carte « Comprendre ces chiffres » (estimation du
  modèle, cote juste, écart, fiabilité) dans l'onglet Pronostic, masquée pour un expert. Les chiffres
  sont les mêmes pour tout le monde.
- Serveur (migration 20) : colonnes `favorite_competitions`, `level`, `onboarded_at` ajoutées à
  `user_preferences` (ligne personnelle, compétitions existantes uniquement, sans doublon).

## 6. Serveur (migration 19)

- Vue `match_1x2_market` (probabilités implicites, marge retirée).
- Table `featured_matches`, `svc_pick_featured_match` (serveur uniquement), `featured_match_today()`.
- `match_insights(match)` : classement, forme, comparatif de saison, séries, confrontations —
  calculés uniquement sur les résultats enregistrés.
- Génération d'analyse partagée entre `analyze-match` et le moteur de coupons
  (`_shared/analysis/generate.ts`).

## 7. Vérifications

- SQL : 18 nouveaux tests (barre du marché, match offert, stats) et 6 sur les préférences — 166 au
  total, tous réussis.
- Flutter : 22 nouveaux tests, dont le rendu de chaque onglet et de l'accueil sans débordement et le
  parcours de premier lancement complet — 95 au total. Analyse sans remarque.
- Captures avec les vraies polices vérifiées à l'œil ; corrigés au passage : badge « Équilibré » et
  « En cours » illisibles en mode sombre, pastilles « N » trop pâles, date de l'en-tête en double.
- Base réelle : 40 matchs avec barre 1/N/2 ; Lille – Lens : comparatif identique à la fiche du moteur
  (11 buts pour / 6 contre ; 16 / 12), 4 confrontations, séries calculées.
