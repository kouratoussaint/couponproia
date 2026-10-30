# LOT 7 — Studio graphique

Statut au 30/10/2026 : **livré et déployé (APK 0.10.0).**

## 1. Ce que fait le studio

Transformer un coupon en visuel prêt pour WhatsApp, Facebook, Instagram ou TikTok.

- **Modèles** : Classique (sombre), Clair, Ticket (façon ticket, police à chasse fixe), Stade
  (dégradé et lignes de terrain), Prestige (couverture, logo et signature du Tipster).
- **Formats** : carré 1080×1080, portrait 1080×1350, story 1080×1920, paysage 1920×1080.
- **Export** : PNG, JPG ou PDF (une page au format du visuel) ; partage direct ou enregistrement
  dans la galerie (album « Coupon Pro IA »).
- **Contenu** : nom du Tipster, logo, date, sélections (compétition, horaire, équipes, logos des
  équipes, issue, cote), cote totale, probabilité estimée par le modèle (désactivable), résultat
  si le coupon est réglé (« Gagné · cote 3,76 »), texte personnalisé, signature.
- Accès : menu latéral « Studio graphique », bouton « Créer un visuel » sur la fiche d'un coupon de
  la plateforme et sur « Mon coupon ».

## 2. Données vérifiées uniquement

- Le visuel est construit **exclusivement** à partir d'un coupon existant : rien n'est saisi à la
  main sauf un texte libre et une signature.
- Texte libre, nom affiché et signature : les mots interdits (« sûr », « garanti », « assuré »,
  « gain », « 100 % », « sans risque »…) sont refusés, dans l'app et dans la base.
- Avertissement présent sur **tous** les visuels, sur une seule ligne et jamais tronqué :
  « Estimations, aucun gain garanti. Interdit aux moins de 18 ans. Pariez de façon responsable. »
- Pas de visuel d'un coupon réservé avant le coup d'envoi, ni du coupon d'un autre utilisateur
  (vérifié par le serveur).
- Au-delà de la place disponible, les sélections restantes sont signalées (« + 4 autres sélections ») ;
  la cote totale reste celle du coupon complet. Maximum affiché : carré 4, portrait 6,
  paysage 7, story 12.

## 3. Forfaits (réglages `pricing.plans` → `features.studio`, modifiables)

| Forfait | Modèles | Personnalisation | Mention « Réalisé avec Coupon Pro IA » | Visuels / jour |
| --- | --- | --- | --- | --- |
| FREE | Classique, Clair | aucune | oui | 3 |
| STARTER | + Ticket, Stade | nom et couleurs | oui | 20 |
| PRO TIPSTER | + Prestige | nom, couleurs, logo, couverture, signature | non | 100 |
| BUSINESS | tous | complète | non | 300 |

Le modèle minimal de chaque gabarit est dans `design_templates.min_plan` (modifiable).

## 4. Serveur

- Tables `design_templates`, `user_branding`, `generated_assets` (journal des exports).
- `my_studio()` : modèles disponibles, niveau de personnalisation, mention, quota et usage du jour.
- `studio_export(...)` : vérifie modèle, forfait, coupon et quota (verrou par utilisateur), puis
  journalise. L'app ne produit le fichier qu'après cet accord.
- Stockage `branding` privé : chaque utilisateur n'accède qu'à son dossier ; PNG, JPG ou WebP ; 2 Mo
  maximum. Les images inutilisées sont supprimées à l'enregistrement ; la suppression du compte
  efface le dossier.
- Limite connue : le dessin se fait sur le téléphone. Le serveur contrôle et compte chaque export,
  mais une app modifiée pourrait produire une image sans passer par lui.

## 5. Tests

- SQL : 17 tests (modèles par forfait, quota, coupon réservé, coupon d'un autre, mots interdits,
  personnalisation par forfait) — total 142, tous réussis.
- Flutter : 27 tests du studio, dont un rendu de **chaque modèle dans chaque format avec 1, 5 et
  15 sélections** sans aucun débordement — total 73.
- Aperçus réels générés avec les vraies polices et vérifiés visuellement.
- Correction faite en cours de route : les graisses de police sont demandées explicitement
  (sinon le gras aurait été simulé).
