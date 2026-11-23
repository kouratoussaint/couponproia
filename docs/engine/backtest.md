# Backtest poisson-1.1 contre poisson-2.0 (2026-11-23T14:44 UTC)

Matchs évalués : saison 2026 (réglage) 2578, saison 2027 (validation) 74. Avant chaque match, au moins 30 matchs de la même saison.

Plus bas = meilleur pour Brier et perte logarithmique (ll). Précision = issue la plus probable juste.

## Réglage (saison précédente) : toutes les variantes

| Modèle (saison 2026) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 2578 | 0,6123 | 1,0215 | 49,1 % | 0,6931 | 0,6938 |
| demi-vie 365 j · ρ 0 · k 5 | 2578 | 0,5964 | 0,9985 | 52,0 % | 0,6865 | 0,6889 |
| demi-vie 540 j · ρ 0 · k 5 | 2578 | 0,5965 | 0,9986 | 51,9 % | 0,6871 | 0,6892 |
| demi-vie 730 j · ρ 0 · k 5 | 2578 | 0,5966 | 0,9987 | 51,9 % | 0,6875 | 0,6895 |
| demi-vie 365 j · ρ -0.04 · k 5 | 2578 | 0,5968 | 0,9990 | 51,9 % | 0,6865 | 0,6883 |
| demi-vie 540 j · ρ -0.04 · k 5 | 2578 | 0,5969 | 0,9991 | 51,9 % | 0,6871 | 0,6887 |
| demi-vie 180 j · ρ 0 · k 5 | 2578 | 0,5968 | 0,9992 | 52,2 % | 0,6852 | 0,6882 |
| demi-vie 730 j · ρ -0.04 · k 5 | 2578 | 0,5970 | 0,9993 | 52,0 % | 0,6875 | 0,6889 |
| demi-vie 180 j · ρ -0.04 · k 5 | 2578 | 0,5972 | 0,9997 | 52,1 % | 0,6852 | 0,6878 |
| demi-vie 730 j · ρ 0 · k 8 | 2578 | 0,5976 | 1,0002 | 52,2 % | 0,6844 | 0,6877 |
| demi-vie 540 j · ρ 0 · k 8 | 2578 | 0,5975 | 1,0002 | 52,4 % | 0,6841 | 0,6875 |
| demi-vie 365 j · ρ 0 · k 8 | 2578 | 0,5977 | 1,0004 | 52,5 % | 0,6835 | 0,6871 |
| demi-vie 540 j · ρ -0.04 · k 8 | 2578 | 0,5980 | 1,0008 | 52,3 % | 0,6841 | 0,6871 |
| demi-vie 730 j · ρ -0.04 · k 8 | 2578 | 0,5980 | 1,0008 | 52,2 % | 0,6844 | 0,6873 |
| demi-vie 365 j · ρ -0.04 · k 8 | 2578 | 0,5981 | 1,0010 | 52,5 % | 0,6835 | 0,6868 |
| demi-vie 180 j · ρ 0 · k 8 | 2578 | 0,5987 | 1,0021 | 52,3 % | 0,6823 | 0,6865 |
| demi-vie 180 j · ρ -0.04 · k 8 | 2578 | 0,5991 | 1,0027 | 52,2 % | 0,6823 | 0,6862 |
| demi-vie 730 j · ρ 0 · k 12 | 2578 | 0,5996 | 1,0033 | 52,4 % | 0,6830 | 0,6868 |
| demi-vie 540 j · ρ 0 · k 12 | 2578 | 0,5997 | 1,0035 | 52,4 % | 0,6827 | 0,6866 |
| demi-vie 730 j · ρ -0.04 · k 12 | 2578 | 0,6001 | 1,0039 | 52,2 % | 0,6830 | 0,6865 |
| demi-vie 365 j · ρ 0 · k 12 | 2578 | 0,6001 | 1,0040 | 52,4 % | 0,6822 | 0,6863 |
| demi-vie 540 j · ρ -0.04 · k 12 | 2578 | 0,6002 | 1,0041 | 52,3 % | 0,6827 | 0,6863 |
| demi-vie 365 j · ρ -0.04 · k 12 | 2578 | 0,6006 | 1,0046 | 52,3 % | 0,6822 | 0,6860 |
| demi-vie 180 j · ρ 0 · k 12 | 2578 | 0,6018 | 1,0066 | 51,7 % | 0,6812 | 0,6857 |
| demi-vie 180 j · ρ -0.04 · k 12 | 2578 | 0,6023 | 1,0072 | 51,6 % | 0,6812 | 0,6855 |

Meilleure variante sur la saison 2026 : **demi-vie 365 j · ρ 0 · k 5**.

## Validation (saison en cours, jamais vue pendant le réglage)

| Modèle (saison 2027) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 74 | 0,6320 | 1,0506 | 47,3 % | 0,6938 | 0,6740 |
| demi-vie 365 j · ρ 0 · k 5 | 74 | 0,6144 | 1,0242 | 51,4 % | 0,7031 | 0,6803 |

## Calibration 1X2 (saison en cours)

| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |
|---|---|---|
| 10–20 % | 17,7 % → 16,7 % (6) | 16,7 % → 7,7 % (13) |
| 20–30 % | 26,2 % → 27,4 % (113) | 25,5 % → 25,0 % (104) |
| 30–40 % | 33,7 % → 24,3 % (37) | 35,2 % → 30,6 % (49) |
| 40–50 % | 44,6 % → 46,2 % (52) | 46,0 % → 50,0 % (38) |
| 50–60 % | 53,1 % → 72,7 % (11) | 55,2 % → 72,7 % (11) |
| 60–70 % | 61,5 % → 33,3 % (3) | 64,8 % → 71,4 % (7) |

## Par compétition (saisons évaluées, Brier 1X2)

| Compétition | Matchs | v1.1 | v2.0 |
|---|---|---|---|
| 2. Bundesliga | 76 | 0,6375 | 0,5985 |
| Africa Cup of Nations - Qualification | 74 | 0,6320 | 0,6144 |
| Bundesliga | 58 | 0,5975 | 0,5849 |
| CAF Champions League | 59 | 0,5878 | 0,5335 |
| Canadian Premier League | 87 | 0,5996 | 0,5907 |
| Challenger Pro League | 47 | 0,5984 | 0,6070 |
| Cup | 91 | 0,7091 | 0,6855 |
| Division 1 | 65 | 0,6114 | 0,5803 |
| First League | 137 | 0,6295 | 0,6182 |
| La Liga | 98 | 0,5776 | 0,5699 |
| Ligue 1 | 114 | 0,6000 | 0,5849 |
| Ligue 2 | 83 | 0,6502 | 0,6359 |
| Premier League | 292 | 0,6193 | 0,6102 |
| Primera División | 469 | 0,6134 | 0,6073 |
| Pro League | 75 | 0,5552 | 0,5610 |
| Serie A | 89 | 0,5454 | 0,5427 |
| Super Liga | 81 | 0,5304 | 0,5145 |
| UEFA Champions League | 130 | 0,5891 | 0,5608 |
| UEFA Europa Conference League | 280 | 0,6369 | 0,6105 |
| UEFA Europa League | 122 | 0,6352 | 0,6232 |
| UEFA Nations League | 125 | 0,6145 | 0,5726 |

## Comparaison au marché (matchs avec cotes avant le coup d'envoi : 359)

| Source | Brier 1X2 | ll 1X2 |
|---|---|---|
| Marché (cotes médianes, marge retirée) | 0,5485 | 0,9276 |
| poisson-1.1 | 0,6051 | 1,0109 |
| demi-vie 365 j · ρ 0 · k 5 | 0,5823 | 0,9789 |
| 30 % v1.1 + 70 % marché | 0,5563 | 0,9409 |
| 30 % v2.0 + 70 % marché | 0,5531 | 0,9358 |

Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.
