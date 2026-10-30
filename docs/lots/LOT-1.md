# LOT 1 — Identité visuelle et fondations

Statut au 30/10/2026 : **code écrit, base de données testée ; compilation de l'APK en attente du dépôt GitHub.**

## 1. Résumé

- Logo (ballon + circuits + arc d'analyse) et icône d'application générés en SVG et PNG.
- Charte appliquée : palette du LOT 0, Montserrat (titres) et Inter (texte), thèmes clair, sombre et système.
- Application Flutter : navigation à 5 onglets, inscription, confirmation d'email et
  réinitialisation du mot de passe par code à 6 chiffres, profil, choix du thème synchronisé,
  suppression de compte, mentions de responsabilité, mode maintenance, proposition de mise à jour.
- Backend Supabase : profils, préférences, rôles et permissions centralisés, feature flags,
  réglages publics, versions de l'app, journal d'audit ; RLS sur toutes les tables.
- CI GitHub : analyse + tests Flutter, tests SQL, vérification des Edge Functions, génération des
  plateformes, publication d'APK signés par tag.

## 2. Fichiers créés

| Domaine | Fichiers |
| --- | --- |
| Base de données | `supabase/migrations/20261030000001_core_foundations.sql`, `20261030000002_reference_data.sql` |
| Tests SQL | `supabase/tests/001_core_rls.test.sql`, `scripts/local-db/*` |
| Edge Function | `supabase/functions/delete-account/index.ts` |
| Auth | `supabase/config.toml`, `supabase/templates/confirmation.html`, `recovery.html` |
| App — socle | `app/lib/main.dart`, `app.dart`, `core/` (config, providers, thème, routeur, erreurs, validateurs, widgets) |
| App — écrans | `features/auth`, `home`, `matches`, `coupons`, `assistant`, `profile`, `shell`, `system` |
| App — tests | `app/test/core_logic_test.dart`, `coming_soon_view_test.dart` |
| Identité | `app/assets/brand/logo_mark.svg`, `app/assets/icon/*`, `scripts/brand/generate_logo.py` |
| CI | `.github/workflows/ci.yml`, `bootstrap-platforms.yml`, `release-apk.yml` |

## 3. Migrations

1. `core_foundations` : tables `roles`, `permissions`, `role_permissions`, `user_roles`, `profiles`,
   `user_preferences`, `feature_flags`, `app_settings`, `app_versions`, `audit_logs` ; fonction
   `app_private.has_permission` ; création automatique du profil à l'inscription ; RPC
   `my_permissions`, `admin_set_user_role`, `admin_set_user_suspended`, `admin_set_feature_flag`
   (toutes auditées) ; `app_private.bootstrap_super_admin` (SQL Editor uniquement).
2. `reference_data` : 7 rôles, 13 permissions, 13 feature flags (tous désactivés), réglages publics
   dont la grille tarifaire D6 et les mentions de responsabilité. Rejouable sans doublon.

## 4. Sécurité

- Le client ne peut modifier que `display_name`, `avatar_url`, `country_code`, `timezone` de son
  profil et ses préférences ; tout le reste passe par des fonctions qui vérifient les permissions.
- Un compte suspendu perd immédiatement toutes ses permissions.
- Seul un super administrateur peut nommer, retirer ou suspendre un administrateur.
- Aucune clé secrète dans l'app ; la suppression de compte s'exécute côté serveur.

## 5. Tests exécutés

| Suite | Résultat |
| --- | --- |
| Migrations + 30 tests RLS sur PostgreSQL 16 | **30/30 réussis** ; échec volontaire vérifié (le harnais détecte une erreur) |
| Rejeu des données de référence | OK, sans doublon |
| Tests Flutter (validateurs, redirections, thème, mises à jour, messages d'erreur, widget) | Écrits ; **pas encore exécutés** : le SDK Flutter n'est pas téléchargeable ici, ils tourneront dans la CI GitHub |
| Edge Function `delete-account` | Vérification de types prévue en CI (Deno indisponible ici) |

## 6. Limites connues

- Le code Dart n'a pas encore été compilé : la première CI peut révéler des écarts de version de
  paquets à corriger.
- Les polices sont téléchargées au premier lancement (google_fonts) puis mises en cache ; elles
  seront embarquées dans l'APK à un lot ultérieur pour un fonctionnement 100 % hors ligne.
- Photo de profil : la colonne existe, l'envoi d'image arrive avec le Storage (LOT 7 ou avant si besoin).
- Identifiant d'application proposé : `com.couponproia.coupon_pro_ia` (généré par `flutter create`) ;
  modifiable jusqu'à la première publication sur le Play Store, définitif ensuite.

## 7. Configurations restantes (propriétaire)

- [ ] Dépôt GitHub privé relié à la session Claude.
- [ ] Projets Supabase staging et prod ; modèles d'emails ; migrations ; Edge Function ; super admin (voir `docs/installation.md`).
- [ ] Secrets GitHub (signature + Supabase).

## 8. Prochaines étapes

1. Push, bootstrap des plateformes, réglage de la signature et des permissions Android.
2. CI verte, puis tag `v0.1.0` : premier APK signé (tests internes).
3. Validation du LOT 1 par le propriétaire, puis LOT 2 (données football).
