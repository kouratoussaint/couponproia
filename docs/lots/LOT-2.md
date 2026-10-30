# LOT 2 — Données football (+ menu latéral et balayage)

Statut au 30/10/2026 : **livré et déployé ; en attente de la clé API-Football pour les premières données réelles.**

## 1. Résumé

- **Navigation (demande du propriétaire)** : menu latéral sur tous les onglets (bouton ☰ ou glissement
  depuis le bord gauche) ; passage d'un onglet à l'autre en balayant l'écran vers la gauche ou la droite,
  chaque onglet gardant son état.
- **Base football** : compétitions, équipes, matchs, classements, cotes résumées, journal des synchronisations.
- **Synchronisation** : Edge Function `sports-sync` derrière l'interface `SportsDataProvider`
  (adaptateur API-Football), planifiée par `pg_cron` ; budget journalier de requêtes respecté.
- **App** : calendrier des matchs (hier à J+6), recherche, filtre par compétition, scores en direct ;
  fiche match (cotes, forme, confrontations, classement, source) ; compétitions et classements ;
  écran d'administration des synchronisations.

## 2. Données et sources

| Donnée | Origine | Fréquence | Requêtes (offre gratuite) |
| --- | --- | --- | --- |
| Saison en cours, calendrier complet, résultats | `/leagues`, `/fixtures?league&season` | 4 h chaque jour | 3 par compétition (27 pour 9) |
| Classements (et groupes) | `/standings` | 4 h chaque jour | incluses ci-dessus |
| Cotes 1X2, double chance, plus/moins 0,5 à 3,5, les deux marquent | `/odds?fixture` | 7 h et 15 h, matchs des 48 h | 12 max par passage |
| Scores en direct | `/fixtures?ids` (20 par requête) | toutes les 15 min | 0 s'il n'y a pas de match en cours |

Les cotes ne sont pas stockées bookmaker par bookmaker : pour chaque issue, on garde la **médiane**, la
**meilleure cote** et le **nombre de bookmakers** (économie de stockage, lecture plus honnête).
Forme récente et confrontations sont calculées sur les matchs déjà synchronisés (saison en cours) et
l'app l'indique.

## 3. Migrations

3. `football_data` : tables, vue `latest_odds` (sécurité de l'appelant), RLS, 9 compétitions de départ
   (identifiants API-Football, nom et saison vérifiés à la première synchronisation), 4 marchés,
   flag `matches`, 4 réglages privés `sports.*`.
4. `sports_schedule` : `app_private.invoke_sports_sync` (lit l'URL et le secret dans Vault) et 3 tâches
   `pg_cron`. Ignorée proprement là où `pg_cron` n'existe pas (tests locaux).

## 4. Tests

| Suite | Résultat |
| --- | --- |
| SQL (PostgreSQL 16) : 30 tests LOT 1 + 16 tests LOT 2 | **46/46** |
| Deno : statuts, marchés, résumé des cotes, lecture des réponses, erreurs du fournisseur, quota | **réussis** en CI |
| Flutter : analyse + tests (dont formats, forme, recherche, regroupements, cotes) | **réussis** en CI |
| Déploiement : 4 migrations, 3 fonctions, 3 tâches planifiées actives, contrôles RLS publics | **réussi** |
| Chaîne pg_cron → pg_net → sports-sync (secret partagé) | **vérifiée** : appel authentifié, journalisé « ignoré : clé absente » |

## 5. Limites connues

- Sans clé API-Football, aucune donnée : l'app affiche « Aucun match synchronisé ».
- L'offre gratuite d'API-Football a pu limiter l'accès aux saisons récentes ; si c'est le cas, l'erreur
  du fournisseur apparaît dans l'écran d'administration et l'offre Pro (19 $/mois) devient nécessaire.
- Cotes : bookmakers internationaux du fournisseur, qui peuvent différer des opérateurs locaux.
- Pas encore de mode hors ligne complet : les logos sont mis en cache, les listes non.
- Statistiques détaillées de match (tirs, corners, cartons) : prévues avec le moteur d'analyse (LOT 3).

## 6. Configuration restante (propriétaire)

- [ ] Clé API-Football dans le secret GitHub `API_FOOTBALL_KEY`, puis redéploiement avec `sync = daily`.

## 7. Prochaine étape

LOT 3 : moteur statistique (Poisson, probabilités implicites), couche IA et bouton « Analyser avec l'IA ».
