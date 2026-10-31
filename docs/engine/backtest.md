# Backtest poisson-1.1 contre poisson-2.0 (2026-10-31T21:29 UTC)

Matchs évalués : saison 2025 (réglage) 2239, saison 2026 (validation) 547. Avant chaque match, au moins 30 matchs de la même saison.

Plus bas = meilleur pour Brier et perte logarithmique (ll). Précision = issue la plus probable juste.

## Réglage (saison précédente) : toutes les variantes

| Modèle (saison 2025) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 2239 | 0,6098 | 1,0183 | 50,2 % | 0,6918 | 0,6968 |
| demi-vie 365 j · ρ 0 · k 5 | 2239 | 0,5958 | 0,9990 | 51,7 % | 0,6899 | 0,6901 |
| demi-vie 365 j · ρ -0.08 · k 5 | 2239 | 0,5963 | 0,9995 | 51,7 % | 0,6899 | 0,6898 |
| demi-vie 365 j · ρ 0 · k 2 | 2239 | 0,5963 | 1,0005 | 51,9 % | 0,6985 | 0,6948 |
| demi-vie 365 j · ρ -0.08 · k 2 | 2239 | 0,5967 | 1,0014 | 52,0 % | 0,6985 | 0,6940 |
| demi-vie 180 j · ρ 0 · k 5 | 2239 | 0,5975 | 1,0014 | 51,9 % | 0,6898 | 0,6906 |
| demi-vie 180 j · ρ -0.08 · k 5 | 2239 | 0,5981 | 1,0021 | 51,9 % | 0,6898 | 0,6903 |
| demi-vie 180 j · ρ 0 · k 2 | 2239 | 0,5976 | 1,0022 | 51,4 % | 0,6988 | 0,6959 |
| demi-vie 180 j · ρ -0.08 · k 2 | 2239 | 0,5981 | 1,0031 | 51,5 % | 0,6988 | 0,6951 |
| demi-vie 90 j · ρ 0 · k 5 | 2239 | 0,6023 | 1,0081 | 50,8 % | 0,6916 | 0,6919 |
| demi-vie 90 j · ρ 0 · k 2 | 2239 | 0,6023 | 1,0088 | 50,8 % | 0,7025 | 0,6992 |
| demi-vie 90 j · ρ -0.08 · k 5 | 2239 | 0,6030 | 1,0089 | 50,6 % | 0,6916 | 0,6917 |
| demi-vie 90 j · ρ -0.08 · k 2 | 2239 | 0,6029 | 1,0099 | 50,7 % | 0,7025 | 0,6983 |

Meilleure variante sur la saison 2025 : **demi-vie 365 j · ρ 0 · k 5**.

## Validation (saison en cours, jamais vue pendant le réglage)

| Modèle (saison 2026) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 547 | 0,5989 | 1,0025 | 52,1 % | 0,6802 | 0,6884 |
| demi-vie 365 j · ρ 0 · k 5 | 547 | 0,5786 | 0,9731 | 55,0 % | 0,6761 | 0,6847 |

## Calibration 1X2 (saison en cours)

| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |
|---|---|---|
| 0–10 % | 8,6 % → 11,1 % (9) | 8,2 % → 0,0 % (20) |
| 10–20 % | 16,8 % → 14,5 % (173) | 16,2 % → 12,3 % (179) |
| 20–30 % | 25,0 % → 24,1 % (718) | 24,7 % → 23,6 % (660) |
| 30–40 % | 34,6 % → 33,9 % (254) | 34,7 % → 30,8 % (325) |
| 40–50 % | 45,2 % → 47,0 % (268) | 44,7 % → 52,0 % (225) |
| 50–60 % | 54,3 % → 57,8 % (135) | 54,7 % → 55,9 % (127) |
| 60–70 % | 64,2 % → 64,2 % (67) | 63,8 % → 73,7 % (76) |
| 70–80 % | 73,2 % → 85,7 % (14) | 74,1 % → 83,3 % (24) |
| 80–90 % | 80,5 % → 100,0 % (3) | 83,4 % → 100,0 % (5) |

## Par compétition (saisons évaluées, Brier 1X2)

| Compétition | Matchs | v1.1 | v2.0 |
|---|---|---|---|
| Africa Cup of Nations | 22 | 0,6156 | 0,5540 |
| Bundesliga | 314 | 0,6010 | 0,5956 |
| CAF Champions League | 183 | 0,5697 | 0,5363 |
| La Liga | 423 | 0,5881 | 0,5852 |
| Ligue 1 | 320 | 0,6196 | 0,6038 |
| Premier League | 407 | 0,6292 | 0,6235 |
| Serie A | 412 | 0,6004 | 0,5853 |
| UEFA Champions League | 362 | 0,6133 | 0,5779 |
| UEFA Europa League | 343 | 0,6236 | 0,6073 |

## Comparaison au marché (matchs avec cotes avant le coup d'envoi : 23)

| Source | Brier 1X2 | ll 1X2 |
|---|---|---|
| Marché (cotes médianes, marge retirée) | 0,5768 | 0,9717 |
| poisson-1.1 | 0,6405 | 1,0528 |
| demi-vie 365 j · ρ 0 · k 5 | 0,5788 | 0,9689 |
| 30 % v1.1 + 70 % marché | 0,5913 | 0,9896 |
| 30 % v2.0 + 70 % marché | 0,5748 | 0,9681 |

Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.
