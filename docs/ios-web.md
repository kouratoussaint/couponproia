# Préparation iOS, web et autres langues

État au LOT 12 : l'application est **prête à être compilée** pour iPhone et pour le navigateur.
Ni l'une ni l'autre n'est publiée. Le même serveur Supabase sert toutes les plateformes ; aucune
logique métier n'est dans l'app.

## iOS

### Déjà fait
- Identifiant de l'app : `com.couponproia.app` (identique à Android), nom affiché
  « Coupon Pro IA », iOS 15 minimum.
- Autorisations décrites en français : photothèque (logo, couverture) et ajout à la galerie
  (visuels du studio).
- Schémas déclarés (`https`, `mailto`) pour les liens de paiement et le contact du support.
- Chiffrement : uniquement le HTTPS standard (`ITSAppUsesNonExemptEncryption = false`).
- Mises à jour par APK désactivées hors Android.
- Workflow manuel **« Compilation iOS (sans signature) »** : il vérifie la compilation sur
  macOS et fournit un `Runner.app` non signé (artefact de 7 jours).

### À faire pour publier sur l'App Store
1. Compte Apple Developer (99 USD par an).
2. Certificat de distribution et profil de provisionnement pour `com.couponproia.app`.
3. Signature dans le workflow (secrets GitHub), puis envoi vers TestFlight.
4. Notifications : ajouter l'app iOS au projet Firebase, une clé APNs, le fichier
   `GoogleService-Info.plist`, la capacité « Push Notifications » et le mode d'arrière-plan
   « remote-notification ». Le service de notifications de l'app est aujourd'hui limité à
   Android ; il faudra l'ouvrir à iOS.
5. Paiement : les forfaits numériques vendus dans une app iOS doivent en principe passer par
   l'achat intégré d'Apple. Choix à trancher avant toute publication iOS (achat intégré, ou app
   iOS sans vente).
6. Fiche App Store : captures, politique de confidentialité (URL publique), classification
   d'âge 17+ (contenus liés aux paris).

## Web

### Déjà fait
- Plateforme web générée (`app/web`) : titre, langue française, couleurs et icônes Coupon Pro IA.
- La CI compile la version web à chaque envoi (job « Web (compilation) ») : toute régression
  est détectée.
- Vérifié dans un navigateur sans interface : l'écran de connexion s'affiche, sans erreur.
- Fonctions propres au téléphone neutralisées sur le web :
  - enregistrement dans la galerie : remplacé par « Partager », qui télécharge le fichier ;
  - notifications sur l'appareil : désactivées ;
  - proposition de mise à jour par APK : désactivée.

### À faire pour ouvrir l'interface web
1. Hébergement statique du dossier `app/build/web` (Cloudflare Pages, Netlify, GitHub Pages…),
   avec un nom de domaine.
2. Supabase → Authentication → URL Configuration : ajouter le domaine du site.
3. Retour de paiement CinetPay : prévoir une page de retour web (aujourd'hui, l'app reprend
   la main après l'ouverture de la page de paiement sur le téléphone).
4. Mise en page large : les écrans sont pensés pour le téléphone. Une version bureau demandera
   une mise en page adaptée (colonnes, menu latéral fixe).
5. Notifications web (facultatif) : Firebase Cloud Messaging pour le web, avec un service
   worker.

## Autres langues et devises

- La langue (`fr`) est déclarée au même endroit pour toute l'app (`app/lib/app.dart`), avec les
  traductions Material et un fuseau horaire réglable (`app.timezone`).
- Devise : réglage `app.currency` (code ISO et libellé). Les prix sont stockés en FCFA entiers.
- Documents légaux : versionnés côté serveur, un document par code. Une traduction pourra être
  publiée sous de nouveaux codes sans toucher à l'app.
- Pour ajouter l'anglais :
  1. activer `flutter gen-l10n` (fichier `l10n.yaml` et `lib/l10n/app_fr.arb`) ;
  2. déplacer les textes écran par écran dans les fichiers ARB, en commençant par les
     écrans d'inscription, d'accueil et de coupons ;
  3. ajouter `app_en.arb`, puis `Locale('en')` dans `supportedLocales` ;
  4. côté serveur, les textes générés par l'IA prennent la langue en paramètre (prompts à
     dupliquer), et les messages d'erreur des fonctions SQL sont à traduire dans l'app à partir
     de leur code.
