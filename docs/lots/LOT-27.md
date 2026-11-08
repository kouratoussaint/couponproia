# LOT 27 — Navigation et retours (v0.35.0)

Validé le 08/11 (analyse de la navigation, recommandations R1 à R10 acceptées en bloc).

## Règle unique

Tout écran ouvert depuis un autre s'empile ; le bouton retour (Android ou flèche en haut)
revient exactement à l'écran précédent. La pile n'est remise à zéro qu'à la connexion, à la
déconnexion et à la fin de l'inscription.

## Mise en œuvre

- `core/router/navigation.dart` :
  - `openRoute` / `openLocation` : une adresse d'onglet change d'onglet dans la coque ; toute
    autre adresse s'empile. Les écrans plein écran ouverts avant un changement d'onglet sont
    mémorisés et rouverts au retour (ex. Aide → article → « Voir les coupons » → retour =
    l'article) ;
  - `normalizeLocation` : anciennes adresses redirigées (`/laboratoire`, `/mes-coupons`,
    `/competitions`, `/profil/mentions`) ;
  - `TabBackHistory` (onglet + écrans à rouvrir) et `SubTabBack`.
- `core/router/shell_back.dart` (`ShellBackScope`) : ordre du retour dans les onglets — menu
  latéral, sous-onglet, onglet précédent avec ses écrans, double appui pour quitter.
- `core/widgets/sub_tab_back.dart` : retour au premier sous-onglet (Matchs, Assistant IA,
  détail d'un match, Communauté, Performances).
- `core/widgets/unsaved_changes_guard.dart` : « Quitter sans enregistrer ? » seulement si la
  saisie a changé (modifier le profil, profil Tipster, modification d'un coupon, campagnes,
  documents légaux FR et EN). Le Studio n'a rien à enregistrer : pas de question.
- Notifications (toucher et bandeau « Voir »), liste des notifications, bandeau de
  renouvellement, alertes de la console : passent par `openRoute`.
- Menu : Mentions légales en plein écran (`/mentions`).
- Aide : articles liés empilés ; boutons d'action par `openRoute`.
- Connexion : écrans « Code de vérification » et « Nouveau mot de passe » empilés, avec flèche
  retour (affichée seulement s'il y a un écran précédent).
- Mes coupons et Laboratoire : une seule version, les sous-onglets de l'Assistant IA
  (`/assistant?onglet=laboratoire&coupon=<id>` pour ouvrir un coupon dans le Laboratoire).
- Correctif : déconnexion depuis le menu (et le Profil, et l'écran des documents à accepter)
  qui utilisait `ref` après la fermeture du menu → `signOutEverywhere` lit les services avant
  d'attendre (erreur « Cannot use ref after the widget was disposed » vue sur /accueil).

## Tests

`test/lot27_test.dart` : copie de la structure de l'app (coque, onglets, écrans plein écran)
avec les vrais composants ; le bouton retour d'Android est simulé pour chaque parcours.
Vérifié : les tests échouent si l'on revient à l'ancien comportement.
