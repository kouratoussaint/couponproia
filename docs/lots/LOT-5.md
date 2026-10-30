# LOT 5 — Mon Assistant IA et crédits

Statut au 30/10/2026 : **livré et déployé (APK 0.5.0, build 108).** Essai réel par le propriétaire en
cours ; le journal (crédits, requêtes IA) sera vérifié après ses premières demandes.

## 1. Résumé

- **Parcours (prompt §8.4)** :
  1. l'utilisateur écrit sa demande ;
  2. l'IA en extrait l'intention et les critères (JSON vérifié et borné côté serveur) ;
  3. le serveur charge les vrais matchs cotés de la période ;
  4. le moteur statistique (poisson-1.1) calcule les probabilités ;
  5. le générateur compose les sélections (au plus une par match, combinaison la plus probable dans la
     fourchette de cote) — l'IA ne choisit ni les matchs ni les cotes ;
  6. le serveur contrôle et calcule les cotes ;
  7. l'app affiche la proposition ;
  8. l'utilisateur enregistre, modifie ou redemande.
- **Intentions** : créer un coupon, proposer 3 variantes, modifier le coupon en cours (retirer,
  remplacer les plus fragiles, ajouter), analyser le coupon en cours (sélections fragiles, cotes qui ont
  bougé, matchs commencés, corrélations, qualité des données), repérer les rencontres intéressantes
  d'une période, répondre à une question.
- **Critères compris** : jour (aujourd'hui, demain, week-end, date), compétitions, équipes à inclure ou
  exclure, nombre de sélections, cote totale cible (± 15 %) ou bornes, cotes par sélection, marchés et
  issues précises (ex. « plus de 1,5 but »), niveau de risque. Si l'utilisateur demande des marchés où
  le moteur ne bat pas la référence (buts), c'est accepté, avec un avertissement explicite.
- **Sans résultat** : explication des obstacles (motifs d'exclusion), une seule tentative assouplie et
  signalée, sinon aucun crédit débité.
- **Crédits** : dotation mensuelle du forfait (FREE : 2, réglage `pricing.plans`), non cumulable ;
  crédits supplémentaires (ajustement admin aujourd'hui, packs au LOT 9) ; **débit uniquement après un
  résultat enregistré, une seule fois** (l'opération porte l'identifiant du message ; index unique en
  base) ; questions gratuites ; compte équipe illimité mais journalisé ; 60 messages par jour au plus.
- **App** : onglet Assistant (suggestions, conversation, cartes de proposition avec Enregistrer /
  Remplacer les plus fragiles / Analyser / Détail, opportunités, diagnostic), historique des
  conversations, Mes coupons (détail, copie pour partager, suppression), solde de crédits (barre de
  l'assistant et profil).

## 2. Migrations

13. `credits_assistant` : `credit_accounts`, `credit_ledger` (débit unique par opération),
    `my_credits()`, `svc_consume_credits` / `svc_credit_summary` (rôle service uniquement),
    `admin_adjust_credits` (billing.manage, audité), `assistant_conversations`, `assistant_messages`,
    `user_coupons`, `user_coupon_selections` (strictement privés, y compris vis-à-vis des admins),
    réglages `assistant.*` et `credits.staff_unlimited`, flag `assistant_ia` activé, prompt
    `assistant_intent`.

Edge Function : `assistant` (JWT obligatoire).

## 3. Tests

| Suite | Résultat |
| --- | --- |
| SQL : 30 + 16 + 11 + 17 + 18 (crédits : dotation, débit unique, refus sans débit partiel, exemption, expiration mensuelle, ajustement ; confidentialité des conversations et coupons) | **92/92** |
| Deno : 53 tests (dont intention, bornes, périodes et fuseaux, critères, noms, diagnostic, opportunités, sélections imposées) | **53/53** |
| Flutter : analyse statique sans remarque + 38 tests | **réussis** |

## 4. Limites connues

- Pas encore de comparaison détaillée de deux coupons ni de simulation : Laboratoire IA (LOT 6).
- Export visuel du coupon : Studio graphique (LOT 7). Partage : texte copié.
- Achat de crédits : LOT 9 (Mobile Money).
- Les noms d'équipes sont rapprochés par leur écriture (« PSG » peut ne pas être reconnu : l'assistant
  le signale).
