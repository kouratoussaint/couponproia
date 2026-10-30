# Coupon Pro IA

> L'intelligence au service de vos pronostics.

Plateforme SaaS d'analyse de football : un moteur statistique calcule, l'IA interprète
et explique, le serveur valide. Application Android (Flutter) d'abord, iOS ensuite.

## Organisation du dépôt

| Dossier | Contenu |
| --- | --- |
| `app/` | Application mobile Flutter |
| `supabase/migrations/` | Schéma PostgreSQL versionné (tables, RLS, fonctions) |
| `supabase/tests/` | Tests SQL (pgTAP) : une politique RLS = au moins un test |
| `supabase/functions/` | Edge Functions (Deno / TypeScript) : logique serveur et clés secrètes |
| `supabase/templates/` | Modèles d'emails (codes de confirmation) |
| `scripts/` | Outils : tests de base de données en local, génération du logo |
| `docs/` | Rapports de lot, guide d'installation, décisions |
| `.github/workflows/` | CI, génération des plateformes, publication de l'APK |

## Commandes utiles

```bash
# Tests de la base (PostgreSQL 16 local, sans Docker)
bash scripts/local-db/test.sh

# App
cd app
flutter pub get
flutter test
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx

# Publier un APK signé (GitHub Actions)
git tag v0.1.0 && git push --tags
```

## Règles du projet

- Aucune clé secrète dans l'app : seules l'URL Supabase et la clé publique y entrent.
- Aucune donnée fictive présentée comme réelle ; un module non livré l'indique clairement.
- Cotes, statuts, crédits, rôles et paiements sont toujours validés côté serveur.
- Les pronostics sont des estimations ; aucun gain n'est garanti.

Voir `docs/installation.md` pour configurer Supabase et la signature Android, et
`docs/lots/` pour le détail de chaque lot livré.
