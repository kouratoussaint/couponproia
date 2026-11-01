# Lot 17 : hors connexion, plantages, alertes d'exploitation, alertes personnalisées (0.24.0)

## C1. Mode hors connexion
`core/offline` : client HTTP de Supabase qui enregistre les lectures réussies (par compte) et les
resservit sans réseau ; bandeau en bas de l'écran ; cache effacé à la déconnexion.

## C3. Plantages et lenteurs
Choix d'un suivi intégré plutôt que Firebase Crashlytics : Crashlytics exige son extension Gradle
(et le fichier google-services, non utilisé par ce projet), au risque d'empêcher l'app de démarrer
si elle manque ; le suivi intégré ne dépend d'aucun service tiers ni secret. Erreurs Flutter et Dart,
requêtes lentes ; table `client_errors`, RPC `report_client_error` ; écran Santé de l'application.
Limite : les plantages natifs Android (hors Dart) ne sont pas remontés.

## C4. Alertes d'exploitation
`app_private.ops_issues`, `public.ops_run_scan`, table `ops_alerts`, fonction `ops-monitor`
(toutes les 15 min), envoi SMTP par le port 465 (`_shared/email/smtp.ts`).

## B3. Alertes personnalisées
Préférences `coupon_categories`, `notify_analyses`, `notify_bet_reminders`, `notify_live` ;
déclencheurs sur les analyses et les buts, tâche `notify-bet-reminders`.
