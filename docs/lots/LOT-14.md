# Demandes du 31/10, soir (version 0.20.0)

## LigdiCash, agrégateur prioritaire
- Payin avec redirection (`/pay/v01/redirect/checkout-invoice/create`), statut relu avec
  `confirm` et le jeton de facture conservé (`payments.provider_ref`, illisible par les
  utilisateurs). Notification : `payment-webhook?p=ligdicash` (JSON et formulaire acceptés).
- Ordre des agrégateurs réglable dans la console (`payments.providers`, LigdiCash puis CinetPay) ;
  relais automatique si la facture est refusée.

## Accueil
Analyse offerte du jour en tête, en carte « cadeau » dorée ; puis Coupon du jour, Matchs,
5 derniers coupons (gagné / perdu) avec « Tout voir » vers l'onglet Résultats, et les
raccourcis en dernier.

## Bouton « Analyser » sur chaque match
Listes des matchs et accueil. Actif avec un forfait payant ou des crédits (ou pour l'analyse
offerte du jour) ; sinon cadenas et accès aux forfaits. Contrôle identique côté serveur
(`analyze-match` répond `subscription_required`) ; les analyses déjà réalisées restent
consultables.

## Profil : tout modifier
Crayon → « Modifier le profil » : photo, pseudo, pays, fuseau horaire, niveau, compétitions et
équipes suivies, adresse e-mail (code à 6 chiffres envoyé à la nouvelle adresse, mot de passe
actuel demandé) et mot de passe (mot de passe actuel demandé).

## Console (design validé, version 0.21.0)
En-tête bleu nuit (période, utilisateurs actifs, coupons publiés, revenus) ; un bloc de couleur
par thème, chaque pastille avec son icône ; gestion en tuiles colorées rangées en Pilotage,
IA et données, Argent, Plateforme, avec un compteur rouge quand quelque chose attend (coupons à
valider, signalements, paiements en attente).

Console → Paiements → « Tester » : facture LigdiCash ou CinetPay de 100 FCFA créée pour vérifier
les clés, jamais présentée ni enregistrée comme paiement (journal : `payment.provider_test`).
