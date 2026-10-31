# LOT 12 — Finalisation et production

Statut au 31/10/2026 : **livré et déployé (APK 0.15.0).**

Avant l'ouverture commerciale, le propriétaire doit encore :
- compléter l'identité de l'éditeur ;
- faire relire les textes légaux ;
- accomplir les formalités de protection des données ;
- ajouter les clés CinetPay et Firebase.

## 1. Sécurité (migration 26)

### Audit
L'audit a combiné les conseils Supabase et une revue de toutes les fonctions appelables par
l'API.
- Aucune fonction publique n'est appelable sans connexion.
- Les 41 fonctions privilégiées ouvertes aux utilisateurs connectés vérifient toutes l'appelant
  (`auth.uid()`) et, pour l'administration, la permission correspondante.
- Les tables sans règle d'accès (`device_tokens`, `payment_events`, `promo_codes`,
  `promo_redemptions`) sont volontairement fermées : elles ne sont accessibles que par des
  fonctions serveur.

### Durcissement
- Fonctions internes sensibles (crédits, notifications, codes promo, création d'administrateur,
  déclencheurs) fermées aux rôles de l'API.
- Droits de table inutiles retirés.

### Tests structurels `017_security`
Ils échouent si l'une de ces règles est enfreinte :
- toute table publique a une RLS ;
- toute fonction privilégiée fixe son `search_path` ;
- aucune fonction n'est appelable sans connexion ;
- toute clé étrangère est indexée.

### Android
- Pas de sauvegarde automatique de la session dans le cloud ni vers un autre appareil.
- Trafic chiffré uniquement.

### Mots de passe divulgués
Le refus des mots de passe divulgués (HaveIBeenPwned) est demandé à chaque déploiement. Il est
disponible seulement avec l'offre Supabase Pro et sera actif dès le passage à cette offre.

## 2. Corrections d'anomalies

- **Tâche « matchday »** : le serveur refusait ce type de tâche, si bien que compositions et
  absents n'étaient jamais récupérés. C'est corrigé : 10 passages réussis, 2 compositions et
  346 absents enregistrés le 31/10.
- **Coupon du jour** : un seul par jour de match (`max_per_day` réglable par profil). Cela évite
  le doublon observé le 31/10 (une génération manuelle plus une génération du créneau).

## 3. Textes légaux (migration 27)

### Documents
- Trois documents versionnés côté serveur : **conditions générales d'utilisation**, **politique
  de confidentialité**, **règles de la communauté**.
- Lisibles sans connexion.
- Publiables depuis la console (Documents légaux), sans nouvelle version de l'app. Les anciennes
  versions sont conservées.

### Acceptation
- Case à cocher obligatoire à l'inscription.
- Écran bloquant à chaque nouvelle version des CGU ou de la politique de confidentialité.
- Acceptations enregistrées par utilisateur et par version.

### Identité de l'éditeur
- Réglage public `legal.editor` (nom, forme, adresse, pays, immatriculation), **à compléter**.
- Contact : `app.support_email`.

### Suppression de compte
Elle efface aussi la photo du profil Tipster.

### Avant l'ouverture
**Les textes sont des brouillons à faire relire par un juriste.**
Formalités à accomplir auprès des autorités de protection des données des pays visés :
- CIL au Burkina Faso ;
- ARTCI en Côte d'Ivoire ;
- CDP au Sénégal.

Voir `docs/exploitation.md`, §7.

## 4. Coûts de fonctionnement (migration 28)

Console → **Coûts** (7, 30 ou 90 jours). Cette section répond au §24 du cahier des charges.
- **Coût moyen par utilisateur actif** :
  - (IA + abonnements fixes répartis sur la période + commissions) ÷ utilisateurs actifs ;
  - avec, à côté, les revenus, l'excédent ou le déficit.
- **Mesuré par la plateforme** :
  - IA : coût estimé par requête et détail par usage ; au 31/10, environ 0,07 USD pour 49 appels ;
  - requêtes API-Football ;
  - notifications créées et envoyées ;
  - taille de la base et des fichiers ;
  - commissions de paiement.
- **À renseigner** (réglages, contrôlés par le serveur) :
  - `costs.fixed_monthly_xof` : abonnements Supabase, API-Football, domaine…, en FCFA par mois ;
  - `costs.payment_fee_percent` : commission CinetPay, de 0 à 20 % ;
  - `costs.usd_to_xof` : taux de conversion (600 par défaut, à ajuster).
- Tant que les abonnements fixes ne sont pas renseignés, l'écran l'indique en rouge.
- La bande passante n'est pas lisible depuis la base : voir Supabase → Usage.

## 5. Optimisation

- Index sur toutes les clés étrangères (suppression de compte, jointures).
- Conseils de performance Supabase relus :
  - les 45 index « jamais utilisés » sont normaux sur une base de quelques jours ;
  - les 3 tables ayant deux règles de lecture (`design_templates`, `user_coupons`,
    `user_coupon_selections`) ne posent problème qu'à forte volumétrie. À fusionner si ces
    tables dépassent quelques dizaines de milliers de lignes.

## 6. iOS, web, autres langues

Le détail est dans `docs/ios-web.md`.

### iOS
- Identifiant `com.couponproia.app`, langue française, nom « Coupon Pro IA ».
- Autorisations décrites.
- Workflow manuel « Compilation iOS (sans signature) ».
- Restent à faire :
  - compte Apple Developer ;
  - signature ;
  - notifications APNs ;
  - choix du mode de paiement (achat intégré Apple).

### Web
- Plateforme générée : titre, langue, couleurs et icônes Coupon Pro IA.
- **La CI compile la version web à chaque envoi.**
- Vérifiée dans un navigateur : l'écran de connexion s'affiche sans erreur.
- Galerie, notifications sur l'appareil et mises à jour par APK sont neutralisées sur le web.

### Autres langues
La procédure pour ajouter l'anglais (ARB, `gen-l10n`) est documentée.

## 7. Documentation

- `docs/exploitation.md` (nouveau) :
  - architecture ;
  - tâches planifiées ;
  - surveillance quotidienne ;
  - incidents fréquents ;
  - mises en production ;
  - gestion commerciale et coûts ;
  - documents légaux ;
  - sécurité ;
  - sauvegardes.
- `docs/ios-web.md` (nouveau).
- Rapports de lots : `docs/lots/LOT-1.md` à `LOT-12.md`.

## 8. Tests

| Suite | Résultat |
| --- | --- |
| SQL (pgTAP, 19 fichiers, dont 017 sécurité, 018 textes légaux, 019 coûts) | 277 réussis |
| Deno (fonctions serveur) | 75 réussis |
| Flutter (app) | 131 réussis, analyse sans remarque |
| Compilation web | réussie, démarrage vérifié dans Chromium |

## 9. Fichiers

### Migrations
- `20261031000026_security_hardening.sql`
- `20261031000027_legal_documents.sql`
- `20261031000028_cost_dashboard.sql`

### App
- `features/legal/` (dépôt, écrans de lecture et d'acceptation)
- `admin/presentation/legal_admin_screen.dart`
- `admin/presentation/costs_admin_screen.dart`
- `MetricGroup` partagé par les tableaux de bord
- inscription avec acceptation
- `app/web/`
- configuration iOS

### CI
- job « Web (compilation) »
- workflow `build-ios.yml`
- étape « Mots de passe compromis refusés »

## 10. Configurations restantes (propriétaire)

1. `legal.editor` et `app.support_email` (console → Réglages).
2. Relecture juridique des textes et formalités auprès des autorités de protection des données.
3. Montants de `costs.fixed_monthly_xof` et `costs.payment_fee_percent`.
4. Secrets CinetPay, puis un paiement réel de test, puis la version **1.0.0**.
5. Firebase : secrets `GOOGLE_SERVICES_JSON` et `FCM_SERVICE_ACCOUNT`.
6. SMTP pour les e-mails d'inscription. Sans SMTP, Supabase n'envoie qu'aux membres de l'équipe.
7. Passage à l'offre Supabase Pro avant l'ouverture : sauvegardes quotidiennes et refus des mots
   de passe divulgués.
