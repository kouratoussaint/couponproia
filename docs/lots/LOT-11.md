# LOT 11 — Administration globale, notifications, jour de match

Statut au 31/10/2026 : **livré et déployé (APK 0.14.0).**
Restent à faire côté propriétaire :
- configurer Firebase pour les notifications sur le téléphone (voir §3) ;
- ajouter les clés CinetPay pour les vrais paiements.

## 1. Console d'administration (migration 22)

- Tableau de bord (7, 30 ou 90 jours) :
  - utilisateurs (total, nouveaux, actifs, suspendus) ;
  - abonnés par forfait ;
  - revenus et paiements ;
  - coupons publiés et réglés ;
  - usage de l'IA et des crédits ;
  - erreurs récentes ;
  - courbe quotidienne des inscriptions.
- Utilisateurs : recherche (e-mail, nom), fiche complète, avec ces actions (toutes journalisées) :
  - rôles ;
  - suspension ;
  - ajustement de crédits ;
  - abonnement offert.
- Modules : activer ou désactiver une fonction sans nouvelle version.
- Réglages et forfaits :
  - éditeur typé ;
  - grille des forfaits contrôlée par le serveur : FREE obligatoire, prix multiples de 5, codes uniques.
- Paiements : liste filtrable, code promo appliqué, remboursements.
- Journal d'audit : toutes les actions sensibles, filtrables.
- Chaque section n'apparaît qu'avec la permission correspondante, vérifiée par le serveur
  (`my_admin_rights`).

## 2. Gestion commerciale (migration 25)

### Codes promo
- Réduction de 1 à 90 %, sur tous les achats, les forfaits (tous ou certains) ou les crédits IA.
- Options : date de fin, nombre maximal d'utilisations, actif ou non.
- Création et modification : console → « Codes promo » (permission `billing.manage`, journalisée).
- L'utilisateur saisit le code dans « Abonnement et crédits » :
  - le serveur le vérifie ;
  - l'écran barre l'ancien prix et affiche le nouveau sur les offres concernées.
- **Le prix final est recalculé par le serveur au paiement.** La réduction est arrondie au
  multiple de 5 FCFA inférieur.
- Une seule utilisation par compte. L'utilisation est comptée quand le paiement est confirmé par
  l'opérateur, et non à la saisie du code.
- Limite connue : deux paiements confirmés en même temps peuvent dépasser d'une unité le nombre
  maximal d'utilisations.

### Remboursement enregistré
- L'argent est rendu depuis le tableau de bord **CinetPay**. L'application ne déclenche pas de
  remboursement chez l'opérateur.
- Ensuite, dans la console : Paiements → toucher le paiement confirmé → « Enregistrer un
  remboursement » (motif obligatoire). Effets :
  - **forfait** : la période payée s'arrête tout de suite (ou est supprimée si elle n'avait pas
    commencé) ; les crédits du forfait suivent le nouveau forfait ;
  - **pack de crédits** : les crédits encore disponibles sont retirés ; ceux déjà utilisés sont
    indiqués ;
  - le paiement passe au statut « Remboursé » ; l'opération est inscrite au journal d'audit et à
    l'historique du paiement.
- Un paiement ne peut être remboursé qu'une fois.

## 3. Notifications (migration 23)

### Boîte de réception
- Une cloche sur l'accueil, avec le nombre de notifications non lues.
- Écran « Notifications » : marquer comme lu, supprimer.

### Types (chacun désactivable dans Profil → Notifications)
- coupon de la plateforme publié ;
- résultat d'un de mes coupons ;
- rappel avant un match suivi (équipes suivies) ;
- publication d'un Tipster suivi ;
- crédits IA presque épuisés ;
- résumé du matin (07:30).

### Fonctionnement
- **Heures calmes** réglables : rien n'est envoyé sur le téléphone pendant ces heures ; les
  notifications restent dans la boîte de réception.
- Anti-doublons : clé unique par événement.
- Envoi sur le téléphone : fonction `push-dispatch`, toutes les 2 minutes, avec Firebase Cloud
  Messaging (HTTP v1) :
  - 3 tentatives au maximum ;
  - les appareils désinscrits sont supprimés ;
  - un lien de notification ne peut ouvrir qu'un écran interne de l'app.

### Configuration Firebase à faire
1. Créer un projet Firebase et y ajouter une application Android de package
   `com.couponproia.app`.
2. Télécharger `google-services.json` et coller tout son contenu dans le secret GitHub
   **GOOGLE_SERVICES_JSON**.
3. Dans Paramètres du projet → Comptes de service, générer une clé privée (fichier JSON) et la
   coller dans le secret GitHub **FCM_SERVICE_ACCOUNT**.
4. Relancer le déploiement Supabase, puis une nouvelle version de l'APK.

Sans ces secrets, tout fonctionne, mais uniquement dans la boîte de réception de l'application.

## 4. Jour de match (migration 24)

### Compositions
- Récupérées 20 à 40 minutes avant le coup d'envoi (API-Football) :
  - titulaires, schéma, remplaçants, entraîneur ;
  - affichées dans l'onglet Analyse de la fiche match ;
  - avant publication, l'heure attendue est indiquée.

### Absents
- Blessés, suspendus, incertains, avec le motif traduit.
- Vérifiés toutes les 3 heures le jour du match.

### Synchronisation et score
- Synchronisation « matchday » toutes les 10 minutes, seulement s'il y a un match dans les
  6 heures. Elle respecte le budget de requêtes (arrêt propre si le quota est atteint).
- Score en direct :
  - synchronisation « live » toutes les 5 minutes ;
  - l'accueil se rafraîchit chaque minute quand un match est en cours ;
  - les équipes suivies passent en premier.
- Aucune donnée inventée : sans composition ou sans liste d'absents publiées par la source,
  l'app le dit.

## 5. Aide et jeu responsable

Profil → « Jeu responsable » :
- rappels : estimations et non certitudes, aucun pari pris par l'app, interdit aux moins de 18 ans ;
- bonnes pratiques (budget, pauses, ne pas courir après ses pertes) et signes d'alerte, avec
  l'invitation à en parler à un proche ou à un professionnel de santé ;
- raccourci pour couper les notifications.

Profil → « Contacter le support » : e-mail défini dans le réglage `app.support_email`.

## 6. Tests

- SQL (pgTAP) : 16 fichiers, 250 tests, dont :
  - 013 console (14) ;
  - 014 notifications (13) ;
  - 015 jour de match (5) ;
  - 016 promotions et remboursements (20).
- Deno : 74 tests (fournisseur sportif, FCM, paiements dont arrondi des codes promo).
- Flutter : 123 tests, analyse sans remarque, textes vérifiés à ×1,6.
