# Application en anglais — partie 1 : interface (0.31.0)

D5 en deux parties, validé le 02/11/2026 :
1. **Cette livraison** : toute l'interface de l'app en anglais, avec le choix de la langue.
2. **Livraison suivante** : textes écrits par le serveur et l'IA (notifications, e-mails,
   analyses, documents légaux) dans la langue du profil.

## Choix de la langue
- Profil → Apparence → « Langue » : Français / English. Au premier lancement, l'anglais si le
  téléphone est en anglais, sinon le français.
- Enregistrée sur le téléphone et sur le profil (`profiles.locale`, migration 48 : « fr » ou
  « en ») pour que le serveur écrive ensuite dans la bonne langue.
- Appliquée au redémarrage : une boîte propose de fermer l'app tout de suite ou plus tard.

## Fonctionnement
- Le français reste la langue source. Chaque texte affiché passe par `tr('texte français')` ou
  `trf('texte avec {0}', [valeur])` (`lib/core/i18n/tr.dart`) ; l'anglais est lu dans
  `assets/i18n/en.json` (clé = texte français). Un texte sans traduction s'affiche en français.
- Nombres : « 1,95 » / « 1.95 », « 12 500 FCFA » / « 12,500 FCFA », « 62 % » / « 62% ».
- Titres de coupons venus du serveur (« Prudent · 02/11 », « Coupon manuel · 3 sélections ») :
  les parties connues sont traduites à l'affichage (`trTitle`), les noms choisis restent tels quels.
- Mêmes règles qu'en français : estimations, jamais de promesse (« guaranteed », « sure »,
  « winnings » exclus, vérifié par un test).
- Nouveau texte : `python3 scripts/i18n/check_en.py` liste ce qui manque dans `en.json`
  (`--add` l'ajoute pour traduction) ; le test `i18n_test.dart` échoue tant qu'il manque un texte.

## Restent en français jusqu'à la partie 2
Notifications, e-mails, analyses et lectures de l'IA, réponses de l'assistant, documents légaux,
noms de profils de coupons créés dans la console.

## Vérifications
- Flutter : `i18n_test.dart` (10) — traduction et repli, séparateurs, titres, couverture complète
  du catalogue (≈ 2 080 textes), cohérence des valeurs {n}, mots interdits ; 249 tests au total.
- SQL : `035_profile_language` (4).
- Aperçus en anglais : menu, Coupons, Mes coupons, aide.
