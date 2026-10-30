# Installation et configuration

## 1. Supabase (une fois par environnement : staging puis prod)

1. Créer le projet sur supabase.com (région Europe ouest, la plus proche de l'Afrique de l'Ouest).
2. **Authentication > Providers > Email** : activer « Confirm email ».
   Longueur minimale du mot de passe : 8.
3. **Authentication > Email Templates** :
   - « Confirm signup » : coller `supabase/templates/confirmation.html`.
   - « Reset Password » : coller `supabase/templates/recovery.html`.
   Ces modèles affichent un code à 6 chiffres (`{{ .Token }}`) que l'app demande.
4. **Base de données** : exécuter dans l'ordre les fichiers de `supabase/migrations/`
   (SQL Editor, ou `supabase db push` avec la CLI liée au projet).
5. **Edge Function** : `supabase functions deploy delete-account`.
6. **Premier super administrateur** : créer son compte depuis l'app, confirmer l'email,
   puis exécuter dans le SQL Editor :
   ```sql
   select app_private.bootstrap_super_admin('ton-email@exemple.com');
   ```
7. Noter l'URL du projet et la clé publique (Settings > API) pour la compilation de l'app.

## 2. Signature Android

La clé de signature (`upload-keystore.jks`) est créée une seule fois. **La perdre empêche
toute mise à jour de l'app déjà installée** : la conserver dans deux endroits hors ligne.

Secrets GitHub (Settings > Secrets and variables > Actions) :

| Secret | Contenu |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore (le même protège la clé `upload`) |
| `SUPABASE_URL` | URL du projet de production |
| `SUPABASE_ANON_KEY` | clé publique du projet de production |

## 3. Premier build

1. Actions > « Bootstrap plateformes » > Run workflow (génère `app/android` et `app/ios`).
2. Configurer la signature dans `app/android/app/build.gradle.kts` (fait par Claude au LOT 1).
3. `git tag v0.1.0 && git push --tags` : l'APK signé apparaît dans l'onglet Releases.

## 4. Publier une mise à jour dans l'app

Après chaque release, insérer la version pour que l'app la propose :

```sql
insert into public.app_versions (platform, version_name, build_number, min_supported_build, download_url, release_notes)
values ('android', '0.1.0', 101, 101, 'https://…/coupon-pro-ia-0.1.0-arm64-v8a.apk', 'Première version de test.');
```
