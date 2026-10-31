# Propositions du 31/10 (version 0.19.0)

Validées par le porteur du projet le 31/10 (« on garde le vous partout, je valide tout le reste »).

## 1. Corrections et coquilles
- Vouvoiement partout (application, notifications du serveur, messages de l'assistant).
- Profil : « Console d'administration » ouvre la console (l'ancienne ligne renvoyait à un lot).
- Matchs désactivés : « Matchs momentanément indisponibles », sans numéro de lot ; l'écran
  « bientôt disponible » est supprimé.
- Notifications : l'avis « arrivent bientôt » n'apparaît que si l'appareil ne peut pas les
  recevoir ou si elles sont bloquées dans les réglages du téléphone.
- Menu latéral : « Mentions légales et documents » (même nom que l'écran) ; un seul lien vers la
  console ; noms identiques entre menu, console et écrans (« Coupons et générations », « Moteur et IA »).
- « e-mail » partout (« adresse e-mail » dans les formulaires).
- Jeu responsable : « Contact indisponible pour le moment » si l'e-mail du support manque.
- Assistant : les packs de crédits sont disponibles (le message disait qu'ils « arriveraient »).

## 2. Marché conservé, modèle d'IA masqué
- Onglet Pronostic après analyse : carte « Modèle et marché » (deux barres par issue, écart en
  points, nombre de bookmakers et heure des cotes).
- Coupons : « Estimation » (probabilité retenue) et « Marché » pour chaque sélection.
- Fournisseur et modèle d'IA réservés au super administrateur, côté serveur (migration 032).

## 3. Coupons : diversification et mélange modèle / marché
- Probabilité retenue = 30 % modèle + 70 % marché (`coupons.market_weight`).
- Écart du modèle seul plafonné à 6 points (au lieu de 10).
- Un match dans 2 coupons au plus ; Coupon du jour et Coupon prudent sans match commun.

## 4. Console → Fournisseurs d'IA
Fonction `ai-providers` (status, models, test, save), permission `ai.providers` (super
administrateur), quotas enregistrés à chaque appel (`ai_requests.quota`).

## 5. Nouvel accueil
Trois chiffres du jour, Coupon du jour en carte principale, quatre raccourcis, analyse offerte,
un seul bloc Matchs (Aujourd'hui / Demain, marché 1 · N · 2), bilan des 7 derniers jours.

## Tests
SQL : 022 (visibilité IA, vouvoiement), 023 (réglages IA, diversification). Deno : mélange,
diversification, rôles, quotas. Flutter : écran Fournisseurs d'IA, carte Modèle et marché, accueil.
