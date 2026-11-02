# Nouveaux marchés, recherche, rapport hebdomadaire (0.29.0)

## D2. Nouveaux marchés (migration 45)
- `DNB` remboursé si nul (1 ou 2 ; match nul → sélection annulée, cote 1,00) ;
  `TTH` / `TTA` buts de l'équipe à domicile / à l'extérieur (plus ou moins de 0,5, 1,5, 2,5).
- Cotes : « Home/Away » (ou « Draw No Bet »), « Total - Home », « Total - Away » d'API-Football
  (`normalizeBet`) ; marge retirée par paire (`impliedProbabilities`).
- Modèle : probabilités tirées de la même matrice de scores (DNB sachant qu'il n'y a pas nul,
  loi des buts de chaque équipe) ; version du moteur inchangée (poisson-2.0).
- Règlement (`settle.ts`) : DNB annulé sur un nul ; TTH/TTA sur le score à 90 minutes.
- Évaluation : familles `DNB` (matchs sans nul) et `TT` (domicile +1,5, extérieur +0,5) ajoutées
  à `engine-evaluate`. Tant qu'une famille n'est pas évaluée, elle n'apparaît pas dans
  `beats_baseline` : hors des coupons de la plateforme, mention « Marché récent : pas encore
  évalué » dans la fiche du match. Console → Moteur : « Lancer l'évaluation » pour la valider.
- Assistant (prompt v3, mots-clés « remboursé si nul »), laboratoire, carnet (`journal_add`),
  cohérence avec l'analyse IA (DNB dans la famille du résultat, SQL et app), libellés partout.

## B4. Recherche (`/recherche`)
- Loupe sur l'Accueil et dans Matchs. Équipes (avec « Suivre »), matchs des équipes trouvées
  (3 jours avant à 10 jours après), compétitions (classement), Coupons IA (hors coupons
  réservés) et Mes coupons. Casse et accents ignorés, 2 lettres minimum.

## C5. Rapport hebdomadaire par e-mail (migration 46, fonction `weekly-report`)
- Sur demande seulement : Notifications → « Rapport hebdomadaire par e-mail » (désactivé par
  défaut). Le lundi à 7 h 05 : Mes coupons décidés, carnet (mises, retour, bilan net) et coupons
  de la plateforme (réussite hors annulés, cote moyenne des gagnés), pertes comprises.
- `svc_weekly_report` (serveur seulement) : e-mail confirmé, un envoi par semaine au plus
  (`weekly_email_sent_at`). Console → Santé : « M'envoyer un aperçu du rapport hebdomadaire ».

## Vérifications
- SQL : test 033 (13), test 002 mis à jour ; Deno : `new_markets_test.ts` (6),
  `weekly_mail_test.ts` (2) ; Flutter : `lot21_test.dart` (5).
