# LOT 9 — Forfaits, abonnements, crédits et paiements

Statut au 30/10/2026 : **serveur et app livrés et déployés (APK 0.9.0).** Les achats restent fermés
tant que les identifiants CinetPay ne sont pas dans les secrets GitHub ; l'app répond alors « Le
paiement n'est pas encore ouvert ». La version 1.0.0 sortira après un premier paiement réel vérifié.

## 1. Forfaits (réglages `pricing.*`, modifiables sans nouvelle version)

| Forfait | Prix mensuel | Crédits IA / mois | Coupons avant le coup d'envoi | Analyses de match / jour |
| --- | --- | --- | --- | --- |
| FREE | 0 | 2 | coupon du jour | 3 |
| STARTER | 2 000 FCFA | 10 | tous | 20 |
| PRO TIPSTER | 5 000 FCFA | 50 | tous | 50 |
| BUSINESS | 10 000 FCFA | 150 | tous | 100 |

- Annuel : 12 mois avec une remise de **15 %** (`pricing.annual_discount_percent`), arrondie à 100 FCFA
  (STARTER 20 400, PRO TIPSTER 51 000, BUSINESS 102 000).
- Pack de crédits : 10 crédits pour 500 FCFA, jusqu'à 5 packs par achat. Les crédits achetés ne
  s'effacent pas à la fin du mois ; ceux du forfait se renouvellent chaque mois.
- Le prix est **toujours recalculé par le serveur** ; l'app n'envoie que le forfait et la période.
- Après le coup d'envoi, tous les coupons sont publics (transparence des résultats).

## 2. Paiement (CinetPay, Mobile Money)

1. L'app demande `payments` → `checkout`. Le serveur calcule le montant, crée la ligne `payments`
   (en attente) et obtient le lien de paiement CinetPay (canal Mobile Money : Orange, Moov…).
2. L'utilisateur paie dans la page de l'opérateur.
3. Confirmation par trois voies, toutes passant par la même vérification :
   - notification CinetPay (`payment-webhook`) ;
   - retour dans l'app (bouton « Vérifier », vérification automatique au retour) ;
   - rattrapage planifié toutes les 30 min (`payments-reconcile`).
4. **Aucune notification n'est crue sur parole** : le serveur interroge toujours l'API de vérification
   CinetPay et contrôle le statut, le montant et la devise avant d'accorder quoi que ce soit.
   Le jeton HMAC de la notification est vérifié et journalisé.
5. `svc_fulfill_payment` (rôle serveur uniquement) accorde l'abonnement ou les crédits **une seule
   fois** par paiement, même si plusieurs confirmations arrivent. Le même forfait payé pendant un
   abonnement en cours le prolonge à la suite ; un autre forfait commence tout de suite.
6. Chaque événement est conservé (`payment_events`, lisible par le serveur seulement). L'utilisateur ne
   voit que ses propres paiements.

## 3. Accès aux coupons selon le forfait

- Les sélections d'un coupon réservé sont masquées par la politique RLS jusqu'au premier coup d'envoi.
- **Complément (migration 17)** : l'analyse générale et l'empreinte d'un coupon citent les matchs et les
  issues. Elles ne sont plus lisibles directement ; l'analyse passe par `coupon_analyses()`, qui
  applique la même règle. Sans cela, le contenu d'un coupon réservé restait lisible par l'API.
- L'app affiche « Coupon réservé » avec l'heure à laquelle il deviendra public et un accès aux forfaits.
- Conséquence : les APK antérieures (0.7.0 et avant) ne peuvent plus lire les coupons. La 0.9.0 est
  enregistrée comme version minimale.

## 4. App

- Écran **Abonnement et crédits** (menu latéral, profil) : forfait actuel et échéance, crédits, choix
  mensuel/annuel, forfaits, packs de crédits, historique des paiements.
- Mention sous l'écran : Coupon Pro IA vend un service d'analyse, ne prend aucun pari, aucun gain n'est
  garanti.

## 5. Tests

- SQL : 125 tests (dont 15 sur la facturation et 8 sur l'accès aux coupons) — tous réussis.
- Deno : 67 tests (calcul des prix, lecture des réponses CinetPay, vérification du jeton).
- Flutter : 46 tests, analyse sans remarque.

## 6. Reste à faire

- Ajouter `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY` dans les secrets GitHub, puis
  relancer le déploiement.
- Dans le tableau de bord CinetPay, l'URL de notification est envoyée à chaque paiement ; rien à saisir.
- Paiement réel de test (pack de 10 crédits, 500 FCFA) : vérifier la notification, l'attribution et
  l'historique, puis publier la 1.0.0.
