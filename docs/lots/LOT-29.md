# LOT 29 — Profil réorganisé (v0.36.0)

Proposition et maquettes validées le 09/11, sauf les boutons « Supprimer mon compte » et
« Se déconnecter », laissés tels quels à la demande du propriétaire.

## Ordre des sections

1. En-tête (photo, nom, modifier) — inchangé.
2. **Mon abonnement** : Abonnement, Crédits IA (désormais cliquable → forfaits et crédits).
3. **Mon jeu** : Carnet de paris, Équipes suivies, Compétitions et niveau (ex-« Mes
   préférences »), Jeu responsable.
4. **Communauté** : Profil Tipster, Utilisateurs bloqués.
5. **Réglages de l'application** (`app_settings_section.dart`), une ligne par réglage avec sa
   valeur : Notifications ; Langue (panneau) ; Apparence « Système · texte normal » (panneau :
   thème et taille du texte) ; Mises à jour « Version · état · Wi-Fi » (panneau, contenu
   inchangé) ; Widget sur l'écran d'accueil ; Rapports d'erreurs (interrupteur).
6. **Administration** (équipe uniquement) : Console d'administration.
7. **Aide** : inchangée.
8. Boutons « Supprimer mon compte » puis « Se déconnecter » — inchangés.

Corrige : bloc « Apparence » sans titre de section et mêlant des réglages sans rapport ;
« Mises à jour » isolé entre Communauté et Aide ; « Mon compte » mêlant compte, réglage et
outil d'administration ; réglages répartis à trois endroits ; deux styles de titres.

## Tests

`test/profile_layout_test.dart` : ordre des sections, réglages sous leur titre, Crédits IA
cliquable, Administration réservée à l'équipe, panneau Apparence.
