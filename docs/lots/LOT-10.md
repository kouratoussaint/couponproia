# LOT 10 — Tipsters et communauté

Statut au 31/10/2026 : **livré et déployé (APK 0.13.0).** Pas de parrainage (décision du
propriétaire). Les notifications aux abonnés arriveront avec le LOT 11 (Firebase).

Cette version contient aussi les corrections demandées le 31/10 :
- barre de navigation redessinée ;
- 12 px entre les cartes partout ;
- bouton Retour (onglet précédent, puis Accueil, puis double appui pour quitter) ;
- réglage « Taille du texte ».

## 1. Profils Tipsters

- Identifiant (@), nom affiché, présentation et photo (stockage public, 1 Mo maximum, dans le
  dossier de l'utilisateur).
- Création réservée aux forfaits **PRO TIPSTER** et **BUSINESS** (`features.tipster_publish`,
  modifiable) ou au rôle Tipster. Tout le monde peut suivre, réagir, commenter et signaler.
- Mots interdits refusés (« sûr », « garanti », « gain », « 100 % »…) dans le nom, la présentation,
  les publications et les commentaires : dans l'app et dans la base.

## 2. Coupons publiés : immuables, pertes comprises

- Un Tipster publie un de ses coupons (assistant, laboratoire, coupon composé) depuis « Mon
  coupon » → « Publier sur mon profil Tipster », avec un commentaire facultatif.
- Publication **au plus tard 5 minutes avant le premier coup d'envoi** (réglable).
- Une fois publié, le coupon ne peut plus être modifié, archivé ni supprimé, ses sélections non
  plus. Seul son résultat évolue, réglé automatiquement par le serveur (LOT 8). Seule la
  suppression du compte l'efface.
- La publication d'un coupon ne se supprime pas non plus ; une publication texte, si.
- Limites : 10 coupons et 10 publications texte par jour, 30 commentaires par heure (réglables).

## 3. Statistiques vérifiées

- Calculées uniquement par la plateforme, sur les coupons publiés avant le coup d'envoi et réglés :
  - publiés, gagnés, perdus, annulés, en cours ;
  - taux de réussite, cote moyenne ;
  - rendement pour une **mise théorique de 1 unité** ;
  - 10 derniers résultats ;
  - sur 30 jours et depuis le début.
- Le taux de réussite n'apparaît qu'à partir de **10 coupons réglés** (réglable), pour éviter les
  chiffres trompeurs sur de petits échantillons.
- L'annuaire des Tipsters est classé par nombre de coupons réglés sur 30 jours, et non par taux
  de réussite.

## 4. Communauté

- Écran « Communauté » (menu latéral) avec 3 onglets :
  - **Abonnements** : fil des Tipsters suivis ;
  - **Découvrir** : toutes les publications ;
  - **Tipsters** : annuaire avec recherche.
- Profil public d'un Tipster : présentation, bouton Suivre, statistiques vérifiées, publications.
- Publication : réaction « J'aime », commentaires, signalement, blocage de l'auteur.
- **Blocage** : on ne voit plus les publications, coupons et commentaires de la personne bloquée,
  et elle ne peut plus commenter ni suivre. Les blocages se gèrent dans Profil → « Utilisateurs
  bloqués ».
- **Équipes suivies** : une étoile à côté de chaque équipe dans la fiche match. Leurs matchs
  passent en tête de l'accueil, devant les compétitions suivies. Liste dans Profil → « Équipes
  suivies ».

## 5. Modération

- Signalement avec un motif : spam, arnaque ou promesse de gain, insulte, résultats trompeurs,
  autre. Un seul signalement ouvert par personne et par contenu.
- File de modération (rôles modérateur et administrateur, vérifiés par le serveur), avec actions :
  - rejeter le signalement ;
  - masquer une publication ou un commentaire ;
  - suspendre ou réactiver un Tipster.
- Chaque action est inscrite au journal d'audit. Traiter un contenu clôt les autres signalements
  ouverts sur lui.
- Un contenu masqué reste visible par son auteur, avec la mention « masqué par la modération ».

## 6. Serveur (migration 21)

- **Tables** : `tipster_profiles`, `posts`, `post_reactions`, `comments`, `tipster_followers`,
  `reports`, `user_blocks`, `user_favorites`.
- **Colonnes ajoutées** à `user_coupons` : `published_at`, `publish_comment`.
- **Fonctions** :
  - `publish_user_coupon`, `create_text_post` ;
  - `tipster_stats`, `community_feed`, `post_detail`, `tipsters_directory` ;
  - `my_community`, `my_blocks` ;
  - `moderate`, `moderation_queue`.
- **Garde-fous** :
  - déclencheurs d'immuabilité sur les coupons publiés et leurs sélections ;
  - règles d'accès : contenu visible seulement si le Tipster est actif et qu'aucun blocage
    n'existe.
- **Correction liée** : « Mes coupons » filtre désormais par utilisateur, puisque les coupons
  publiés des Tipsters sont lisibles par tous.

## 7. Vérifications

- SQL : 32 nouveaux tests sur la communauté — 198 au total, tous réussis.
- Flutter : 8 nouveaux tests sur la communauté et 3 sur le retour et la taille du texte ;
  accueil et fiche match vérifiés sans débordement en très grand texte — 111 au total. Analyse
  sans remarque.
- Aperçus réels vérifiés à l'œil : barre de navigation (clair et sombre), carte de publication,
  statistiques vérifiées, parcours de premier lancement.
