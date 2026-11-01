# Lot 18 : partage, renouvellement, conversion, notifications ciblées (0.25.0)

## B6. Liens de partage
Fonction publique `share` (redirection « intent » Android vers `couponproia://open/...`, repli vers
le téléchargement), filtre d'intention Android, lien ajouté aux partages de coupons et de matchs,
ouvertures comptées. L'APK doit être rendu public (voir exploitation 6 sexies).

## D4. Renouvellement facilité
`my_renewal`, `notify_renewals` (J-3, J-1, J+1), bandeau d'accueil, renouvellement en un geste.

## E1. Conversion et rétention
`user_activity_days` (+ reprise de l'historique), `touch_activity`, `admin_growth`, écran console.

## E2. Notifications ciblées
`push_campaigns`, segments, `admin_campaign_audience`, `admin_send_campaign`, préférence
`notify_news`, écran console.

## Urgence du 01/11 : coupons et analyse IA
Constat : le Coupon équilibré proposait « Lecce ou nul » alors que l'IA retenait « Victoire Genoa » ;
le coupon avait été publié à 08 h 05, avant toute analyse du match. Corrections :
- Coupon du jour généré uniquement à partir de matchs analysés par l'IA, sélections cohérentes ;
- règle de cohérence appliquée à tous les coupons dès qu'une analyse existe
  (`_shared/coupons/ai_consistency.ts`, `app_private.ai_contradiction`) ;
- dernier contrôle avant publication, alerte d'exploitation ;
- modification des coupons générés et duplication d'un coupon retiré (super administrateur).
