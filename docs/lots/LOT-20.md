# Menu latéral et Mes coupons (0.28.0)

## Menu latéral (`features/shell/app_drawer.dart`)
- En-tête : logo, « Espace utilisateur », nom, forfait réel (« Forfait FREE / STARTER / PRO… »,
  « Compte équipe »), « Crédits IA disponibles » (ou « Illimités »). Au forfait FREE : bouton
  « Voir les forfaits ». Un toucher ouvre Abonnement et crédits.
- Mon espace et compte : Mes coupons, Mon carnet de paris, Abonnement et crédits, Mon profil.
- Découvrir : Accueil, Matchs, Compétitions et classements, Coupons IA, Performances (publique,
  sans cadenas), Communauté et Tipsters.
- Outils : Assistant IA, Laboratoire IA, Studio graphique.
- Aide : Jeu responsable, Contacter le support, Mentions légales et documents.
- Administration : seulement pour l'équipe (aucune entrée verrouillée montrée aux utilisateurs).
- Se déconnecter (rouge) et numéro de version.
- Pas d'écran en double : Mes coupons → `/assistant?onglet=coupons`, Laboratoire →
  `/assistant?onglet=laboratoire`, Compétitions → `/matchs?onglet=competitions`.

## Mes coupons (C1 à C8)
- C1 : deux matchs au plus puis « +N matchs » ; la ligne de dates reste toujours visible.
- C2 : titre selon l'origine (« Coupon de l'assistant », « Coupon manuel », « Version optimisée »)
  et le nombre de sélections ; les anciens titres automatiques sont convertis à l'affichage.
  Renommer : 1 à 80 caractères, sans promesse de résultat (déclencheur, migration 44) ; un coupon
  publié reste immuable.
- C3 : pastille ✓ / ✗ / – / horloge ; cote en vert seulement si gagné.
- C4 : « Créé le 01/11/2026 à 14:32 · Payé le … / Terminé le … » (`settled_at`).
- C5 : bandeau « Mon bilan » (coupons, gagnés, perdus, réussite hors annulés, cote moyenne),
  pertes comprises.
- C6 : « En cours » d'abord, puis les coupons terminés groupés par jour avec leur bilan.
- C7 : appui long ou ⋮ : laboratoire (coût affiché au FREE), simuler une mise, noter dans mon
  carnet, partager, renommer, supprimer (ni renommer ni supprimer un coupon publié).
- C8 : bouton « Créer un coupon » (assistant ou laboratoire), aussi quand la liste est vide.
- Serveur : `lab` (build) accepte `variant_of` (votre coupon d'origine) ; titres par défaut
  « Coupon manuel · N sélections », « Version optimisée · N sélections »,
  « Coupon de l'assistant · N sélections ».

## Vérifications
- SQL : test 032 (5) ; Flutter : `lot20_test.dart` (11, dont texte ×1,6 sans débordement) ;
  aperçus du menu en clair et sombre vérifiés.
