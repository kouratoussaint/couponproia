# Widget Android et aide intégrée (0.30.0)

## B5. Widget de l'écran d'accueil
- Android natif (`CouponWidgetProvider.kt`, `res/layout/coupon_widget.xml`) avec `home_widget`.
- Contenu préparé par l'app (`features/widget/home_widget_sync.dart`) : Coupon du jour (cote,
  « 2 sélections · 1er match 18:00 », réservé au FREE avant la fin des matchs, en cours,
  gagné / perdu / annulé), « 12 matchs aujourd'hui · 3 en direct », heure de mise à jour.
  Mis à jour à l'ouverture puis à chaque changement (coupons, direct). Un toucher ouvre le
  coupon (`couponproia://open/coupon/<id>`).
- Ajout : Profil → Apparence → « Widget sur l'écran d'accueil » (demande d'épinglage Android 8+),
  sinon appui long sur l'écran d'accueil → Widgets.

## D6. Aide intégrée
- Centre d'aide `/aide` : 22 articles en 8 thèmes (démarrer, coupons, analyses et crédits,
  assistant / laboratoire / Mes coupons, suivi des paris, forfaits, notifications / direct /
  widget, compte), recherche sans accents, contact du support. Coûts en crédits lus dans les
  réglages (jamais écrits en dur).
- Accès : menu → Aide, Profil → Aide, boutons « ? » sur Coupons, Assistant IA (selon l'onglet),
  Laboratoire, Abonnement, Carnet, et lien depuis « Analyse réservée ».

## Vérifications
- Flutter : `lot22_test.dart` (8) ; aperçus de l'aide ; compilation Android par la release.
