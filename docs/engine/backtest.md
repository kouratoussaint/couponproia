# Backtest poisson-1.1 contre poisson-2.0 (2026-10-31T21:38 UTC)

Matchs évalués : saison 2025 (réglage) 2239, saison 2026 (validation) 547. Avant chaque match, au moins 30 matchs de la même saison.

Plus bas = meilleur pour Brier et perte logarithmique (ll). Précision = issue la plus probable juste.

## Réglage (saison précédente) : toutes les variantes

| Modèle (saison 2025) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 2239 | 0,6098 | 1,0183 | 50,2 % | 0,6918 | 0,6968 |
| demi-vie 730 j · ρ 0 · k 5 | 2239 | 0,5955 | 0,9985 | 51,4 % | 0,6906 | 0,6900 |
| demi-vie 730 j · ρ -0.04 · k 5 | 2239 | 0,5956 | 0,9985 | 51,4 % | 0,6906 | 0,6898 |
| demi-vie 540 j · ρ 0 · k 5 | 2239 | 0,5955 | 0,9986 | 51,9 % | 0,6903 | 0,6900 |
| demi-vie 540 j · ρ -0.04 · k 5 | 2239 | 0,5956 | 0,9986 | 51,9 % | 0,6903 | 0,6898 |
| demi-vie 365 j · ρ 0 · k 5 | 2239 | 0,5958 | 0,9990 | 51,7 % | 0,6899 | 0,6901 |
| demi-vie 365 j · ρ -0.04 · k 5 | 2239 | 0,5959 | 0,9991 | 51,8 % | 0,6899 | 0,6899 |
| demi-vie 730 j · ρ 0 · k 8 | 2239 | 0,5964 | 0,9997 | 51,4 % | 0,6872 | 0,6885 |
| demi-vie 730 j · ρ -0.04 · k 8 | 2239 | 0,5965 | 0,9998 | 51,4 % | 0,6872 | 0,6885 |
| demi-vie 540 j · ρ 0 · k 8 | 2239 | 0,5966 | 1,0000 | 51,4 % | 0,6869 | 0,6885 |
| demi-vie 540 j · ρ -0.04 · k 8 | 2239 | 0,5967 | 1,0000 | 51,5 % | 0,6869 | 0,6884 |
| demi-vie 365 j · ρ 0 · k 8 | 2239 | 0,5970 | 1,0007 | 51,6 % | 0,6865 | 0,6885 |
| demi-vie 365 j · ρ -0.04 · k 8 | 2239 | 0,5972 | 1,0007 | 51,7 % | 0,6865 | 0,6885 |
| demi-vie 180 j · ρ 0 · k 5 | 2239 | 0,5975 | 1,0014 | 51,9 % | 0,6898 | 0,6906 |
| demi-vie 180 j · ρ -0.04 · k 5 | 2239 | 0,5977 | 1,0015 | 51,9 % | 0,6898 | 0,6904 |
| demi-vie 730 j · ρ -0.04 · k 12 | 2239 | 0,5982 | 1,0022 | 51,5 % | 0,6847 | 0,6876 |
| demi-vie 730 j · ρ 0 · k 12 | 2239 | 0,5981 | 1,0022 | 51,5 % | 0,6847 | 0,6875 |
| demi-vie 540 j · ρ -0.04 · k 12 | 2239 | 0,5985 | 1,0026 | 51,8 % | 0,6844 | 0,6876 |
| demi-vie 540 j · ρ 0 · k 12 | 2239 | 0,5984 | 1,0026 | 51,7 % | 0,6844 | 0,6875 |
| demi-vie 365 j · ρ 0 · k 12 | 2239 | 0,5990 | 1,0036 | 51,7 % | 0,6841 | 0,6874 |
| demi-vie 365 j · ρ -0.04 · k 12 | 2239 | 0,5992 | 1,0036 | 51,7 % | 0,6841 | 0,6875 |
| demi-vie 180 j · ρ 0 · k 8 | 2239 | 0,5992 | 1,0038 | 51,5 % | 0,6862 | 0,6886 |
| demi-vie 180 j · ρ -0.04 · k 8 | 2239 | 0,5994 | 1,0039 | 51,5 % | 0,6862 | 0,6886 |
| demi-vie 180 j · ρ 0 · k 12 | 2239 | 0,6018 | 1,0076 | 51,4 % | 0,6839 | 0,6875 |
| demi-vie 180 j · ρ -0.04 · k 12 | 2239 | 0,6021 | 1,0076 | 51,5 % | 0,6839 | 0,6876 |

Meilleure variante sur la saison 2025 : **demi-vie 730 j · ρ 0 · k 5**.

## Validation (saison en cours, jamais vue pendant le réglage)

| Modèle (saison 2026) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 547 | 0,5989 | 1,0025 | 52,1 % | 0,6802 | 0,6884 |
| demi-vie 730 j · ρ 0 · k 5 | 547 | 0,5734 | 0,9656 | 55,9 % | 0,6762 | 0,6836 |

## Calibration 1X2 (saison en cours)

| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |
|---|---|---|
| 0–10 % | 8,6 % → 11,1 % (9) | 7,8 % → 0,0 % (27) |
| 10–20 % | 16,8 % → 14,5 % (173) | 16,2 % → 15,4 % (188) |
| 20–30 % | 25,0 % → 24,1 % (718) | 24,8 % → 22,3 % (650) |
| 30–40 % | 34,6 % → 33,9 % (254) | 34,7 % → 32,0 % (316) |
| 40–50 % | 45,2 % → 47,0 % (268) | 44,5 % → 53,2 % (218) |
| 50–60 % | 54,3 % → 57,8 % (135) | 54,4 % → 57,6 % (132) |
| 60–70 % | 64,2 % → 64,2 % (67) | 64,3 % → 64,9 % (77) |
| 70–80 % | 73,2 % → 85,7 % (14) | 74,0 % → 88,0 % (25) |
| 80–90 % | 80,5 % → 100,0 % (3) | 83,8 % → 100,0 % (8) |

## Par compétition (saisons évaluées, Brier 1X2)

| Compétition | Matchs | v1.1 | v2.0 |
|---|---|---|---|
| Africa Cup of Nations | 22 | 0,6156 | 0,5537 |
| Bundesliga | 314 | 0,6010 | 0,5968 |
| CAF Champions League | 183 | 0,5697 | 0,5299 |
| La Liga | 423 | 0,5881 | 0,5839 |
| Ligue 1 | 320 | 0,6196 | 0,6026 |
| Premier League | 407 | 0,6292 | 0,6241 |
| Serie A | 412 | 0,6004 | 0,5856 |
| UEFA Champions League | 362 | 0,6133 | 0,5719 |
| UEFA Europa League | 343 | 0,6236 | 0,6071 |

## Comparaison au marché (matchs avec cotes avant le coup d'envoi : 23)

| Source | Brier 1X2 | ll 1X2 |
|---|---|---|
| Marché (cotes médianes, marge retirée) | 0,5768 | 0,9717 |
| poisson-1.1 | 0,6405 | 1,0528 |
| demi-vie 730 j · ρ 0 · k 5 | 0,5745 | 0,9627 |
| 30 % v1.1 + 70 % marché | 0,5913 | 0,9896 |
| 30 % v2.0 + 70 % marché | 0,5737 | 0,9668 |

Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.
