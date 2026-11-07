# LOT 26 — Mise à jour téléchargée et installée par l'application (v0.34.0)

Validé le 07/11 (proposition, puis maquette).

## Objectif

Comme les grandes applications distribuées hors Play Store : l'app télécharge la nouvelle
version en arrière-plan, vérifie le fichier, puis l'installe en un toucher, sans passer par le
navigateur ni par le dossier Téléchargements.

## Serveur

- Migration `20261107000053_app_update_integrity.sql` : `app_versions.sha256` (64 caractères
  hexadécimaux) et `app_versions.size_bytes` (> 0). Les deux sont facultatifs : sans eux,
  l'app garde l'ancien parcours par le navigateur.
- Test SQL `039_app_update_integrity`.

## Android (natif)

- `AppUpdater.kt` :
  - téléchargement par le `DownloadManager` du système (continue si l'app est fermée,
    reprend après une coupure réseau, Wi-Fi seul si demandé) vers le dossier privé
    `updates/` de l'app ;
  - vérification de l'empreinte SHA-256 à la fin ; un fichier abîmé est supprimé ;
  - notification « Mise à jour X prête » ;
  - installation par une session `PackageInstaller` ; à partir d'Android 12, sans écran de
    confirmation supplémentaire quand c'est possible ; sinon, Android affiche sa
    confirmation habituelle ;
  - après l'installation, une notification « Mise à jour installée » permet de rouvrir l'app
    (Android ferme l'app pendant le remplacement).
- `MainActivity.kt` : canal `coupon_pro_ia/updater`.
- Manifeste : permissions `REQUEST_INSTALL_PACKAGES` et
  `UPDATE_PACKAGES_WITHOUT_USER_ACTION`, trois récepteurs (fin de téléchargement, résultat
  d'installation, app remplacée).
- La première fois, Android demande d'autoriser Coupon Pro IA à installer des applications ;
  l'app explique pourquoi puis ouvre le bon réglage, et reprend l'installation au retour.

## Application

- `app_updater.dart` : `UpdateController` (vérification, téléchargement, suivi, autorisation,
  installation) et réglage « Téléchargement automatique » : Wi-Fi (par défaut), Wi-Fi +
  mobile, Jamais.
- `update_widgets.dart` / `update_prompt.dart` :
  - proposition avec la taille du fichier et la barre de progression ;
  - bandeau « Mise à jour prête » sur l'accueil (Installer / Plus tard) ;
  - carte « Mises à jour » dans le Profil (version installée, état, réglage) ;
  - écran bloquant pour une version obligatoire, avec téléchargement et installation sur
    place ;
  - repli sur le navigateur si l'empreinte n'est pas publiée ou hors Android.
- Jamais de téléchargement automatique sur données mobiles sans accord, ni d'installation
  sans toucher de l'utilisateur.
- Tests : `test/lot26_test.dart`. Textes anglais dans `assets/i18n/en.json`.

## Publication

Voir `docs/exploitation.md` §5 : `build_number` = 2000 + build, plus `sha256` et
`size_bytes`. La version 0.34.0 s'installe encore une fois à la main (l'app installée ne
connaît pas ce parcours) ; la mise à jour suivante sera la première installée depuis l'app.
