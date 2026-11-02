# Application en anglais — partie 2 : textes du serveur et de l'IA (0.32.0)

Suite de [LOT-23](LOT-23.md). Le serveur écrit désormais dans la langue du profil
(`profiles.locale`, « fr » ou « en »), alignée automatiquement sur celle de l'app.

## Langue du compte
- À l'inscription, l'app envoie sa langue (métadonnée `locale`) : le profil est créé dans
  cette langue (migration 49, `handle_new_user`).
- À chaque connexion et à chaque changement dans Profil → Langue : profil et métadonnées du
  compte mis à jour (`syncAccountLanguage`).

## Notifications
- `app_private.notify()` reçoit le texte français et, en option, l'anglais ; il choisit selon
  le profil. Toutes les notifications aux utilisateurs ont leur version anglaise : coupon
  publié, résultat (coupon, carnet), rappels (pari, match suivi), matin, cotes qui bougent,
  but en direct, analyse prête, crédits, budget, fin de forfait, Tipsters suivis.
- Outils SQL : `user_lang`, `odd_txt`, `fcfa(montant, langue)`, `at_txt`,
  `selection_label(…, langue)` (DNB et buts par équipe ajoutés), `title_en` (titres de coupons).
- Notifications ciblées (console) : titre et message anglais facultatifs ; sans eux, les
  anglophones reçoivent le français.
- Alertes d'exploitation à l'équipe : restent en français.

## E-mails
- Rapport hebdomadaire en anglais pour un profil English.
- Codes de connexion (inscription, mot de passe, nouvelle adresse) : modèles bilingues choisis
  par la métadonnée `locale` ; objet en deux langues (« Votre code Coupon Pro IA · Your
  Coupon Pro IA code »). Vérifié avec le moteur de modèles Go.
- Pages ouvertes dans le navigateur (lien partagé, retour de paiement, e-mail confirmé) :
  anglais si le navigateur est en anglais.

## IA et moteur
- Analyses de match : une analyse par langue (`match_analyses.language`). L'app demande sa
  langue ; un utilisateur anglophone qui a déjà accès au match obtient l'analyse anglaise sans
  nouveau débit (une génération IA de plus pour la plateforme). Fiche du moteur (informations
  manquantes, note) dans la même langue.
- Consigne de langue ajoutée au prompt actif (`_shared/ai/language.ts`) : mêmes clés JSON,
  forme V/N/D écrite win/draw/loss, mots interdits anglais (guaranteed, sure bet, certainty,
  risk-free, winnings, can't lose, 100 %). Garde-fous étendus à l'anglais (mots interdits,
  justification ancrée dans la fiche) ; les chiffres restent vérifiés contre la fiche.
- Coupons de la plateforme : résumé anglais (IA, sinon calcul) et justification anglaise de
  chaque sélection écrits à la création (`analysis.en`, `justification_en`) ; le coupon publié
  reste immuable. Les coupons déjà publiés gardent leur résumé français.
- Assistant IA : demandes en anglais comprises (nombres en lettres, odds, tomorrow, weekend,
  jours de la semaine, goals, draw, safe / bold…), réponses, avertissements, motifs d'échec et
  analyse de coupon en anglais.
- Laboratoire : erreurs, diagnostic, alternatives, comparaison et simulation en anglais.

## Documents légaux
- Table `legal_translations` : traduction anglaise d'information de chaque version (CGU,
  confidentialité, règles de la communauté, migration 50). La version française fait foi et
  reste celle qui est acceptée ; chaque traduction le rappelle en tête.
- Console → Documents légaux → « Traduction anglaise » pour la mettre à jour après une
  nouvelle version française. **Traduction à faire relire avec les textes français.**

## Messages du serveur dans l'app
- 100 messages de refus du serveur (validation, limites, droits) traduits dans le catalogue de
  l'app et affichés en anglais.

## Vérifications
- SQL : `036_server_language` (19) — langue à l'inscription, choix du texte, libellés, montants,
  titres, mots interdits anglais, traductions légales ; 452 tests au total.
- Deno : `english_test.ts` (5) et rapport hebdomadaire anglais ; 127 au total.
- Flutter : 252 tests (résumé et justification anglais d'un coupon, document légal traduit,
  lettres de forme W/D/L, titres datés).
