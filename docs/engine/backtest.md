# Backtest poisson-1.1 contre poisson-2.0 (2026-11-09T12:55 UTC)

Matchs évalués : saison 2025 (réglage) 3241, saison 2026 (validation) 1204. Avant chaque match, au moins 30 matchs de la même saison.

Plus bas = meilleur pour Brier et perte logarithmique (ll). Précision = issue la plus probable juste.

## Réglage (saison précédente) : toutes les variantes

| Modèle (saison 2025) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 3241 | 0,6083 | 1,0165 | 50,0 % | 0,6918 | 0,6971 |
| demi-vie 730 j · ρ 0 · k 5 | 3241 | 0,5950 | 0,9975 | 51,2 % | 0,6903 | 0,6916 |
| demi-vie 540 j · ρ 0 · k 5 | 3241 | 0,5951 | 0,9976 | 51,6 % | 0,6900 | 0,6915 |
| demi-vie 730 j · ρ -0.04 · k 5 | 3241 | 0,5952 | 0,9976 | 51,3 % | 0,6903 | 0,6912 |
| demi-vie 540 j · ρ -0.04 · k 5 | 3241 | 0,5953 | 0,9977 | 51,5 % | 0,6900 | 0,6911 |
| demi-vie 365 j · ρ 0 · k 5 | 3241 | 0,5953 | 0,9979 | 51,4 % | 0,6896 | 0,6914 |
| demi-vie 365 j · ρ -0.04 · k 5 | 3241 | 0,5955 | 0,9981 | 51,5 % | 0,6896 | 0,6910 |
| demi-vie 730 j · ρ 0 · k 8 | 3241 | 0,5958 | 0,9987 | 51,2 % | 0,6861 | 0,6889 |
| demi-vie 730 j · ρ -0.04 · k 8 | 3241 | 0,5961 | 0,9988 | 51,2 % | 0,6861 | 0,6886 |
| demi-vie 540 j · ρ 0 · k 8 | 3241 | 0,5960 | 0,9989 | 51,2 % | 0,6858 | 0,6887 |
| demi-vie 540 j · ρ -0.04 · k 8 | 3241 | 0,5962 | 0,9991 | 51,3 % | 0,6858 | 0,6885 |
| demi-vie 365 j · ρ 0 · k 8 | 3241 | 0,5964 | 0,9995 | 51,2 % | 0,6854 | 0,6886 |
| demi-vie 365 j · ρ -0.04 · k 8 | 3241 | 0,5966 | 0,9997 | 51,4 % | 0,6854 | 0,6884 |
| demi-vie 180 j · ρ 0 · k 5 | 3241 | 0,5967 | 1,0000 | 51,4 % | 0,6890 | 0,6912 |
| demi-vie 180 j · ρ -0.04 · k 5 | 3241 | 0,5970 | 1,0001 | 51,4 % | 0,6890 | 0,6909 |
| demi-vie 730 j · ρ 0 · k 12 | 3241 | 0,5977 | 1,0015 | 51,1 % | 0,6832 | 0,6869 |
| demi-vie 730 j · ρ -0.04 · k 12 | 3241 | 0,5979 | 1,0016 | 51,2 % | 0,6832 | 0,6868 |
| demi-vie 540 j · ρ 0 · k 12 | 3241 | 0,5980 | 1,0019 | 51,2 % | 0,6829 | 0,6868 |
| demi-vie 540 j · ρ -0.04 · k 12 | 3241 | 0,5982 | 1,0020 | 51,4 % | 0,6829 | 0,6867 |
| demi-vie 180 j · ρ 0 · k 8 | 3241 | 0,5983 | 1,0022 | 51,2 % | 0,6848 | 0,6882 |
| demi-vie 180 j · ρ -0.04 · k 8 | 3241 | 0,5985 | 1,0025 | 51,3 % | 0,6848 | 0,6880 |
| demi-vie 365 j · ρ 0 · k 12 | 3241 | 0,5986 | 1,0028 | 51,2 % | 0,6826 | 0,6866 |
| demi-vie 365 j · ρ -0.04 · k 12 | 3241 | 0,5988 | 1,0029 | 51,3 % | 0,6826 | 0,6865 |
| demi-vie 180 j · ρ 0 · k 12 | 3241 | 0,6010 | 1,0063 | 51,1 % | 0,6820 | 0,6862 |
| demi-vie 180 j · ρ -0.04 · k 12 | 3241 | 0,6013 | 1,0065 | 51,1 % | 0,6820 | 0,6861 |

Meilleure variante sur la saison 2025 : **demi-vie 730 j · ρ 0 · k 5**.

## Validation (saison en cours, jamais vue pendant le réglage)

| Modèle (saison 2026) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |
|---|---|---|---|---|---|---|
| poisson-1.1 | 1204 | 0,6018 | 1,0072 | 50,7 % | 0,6858 | 0,6955 |
| demi-vie 730 j · ρ 0 · k 5 | 1204 | 0,5884 | 0,9875 | 53,2 % | 0,6853 | 0,6913 |

## Calibration 1X2 (saison en cours)

| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |
|---|---|---|
| 0–10 % | 8,4 % → 15,4 % (26) | 8,3 % → 14,9 % (47) |
| 10–20 % | 16,4 % → 15,0 % (421) | 16,1 % → 14,1 % (441) |
| 20–30 % | 25,0 % → 24,4 % (1508) | 25,1 % → 23,6 % (1465) |
| 30–40 % | 34,5 % → 35,5 % (619) | 34,5 % → 34,9 % (631) |
| 40–50 % | 44,8 % → 44,7 % (512) | 44,6 % → 48,2 % (488) |
| 50–60 % | 54,4 % → 56,2 % (297) | 54,5 % → 55,2 % (288) |
| 60–70 % | 64,5 % → 62,4 % (181) | 64,3 % → 66,1 % (177) |
| 70–80 % | 74,0 % → 82,2 % (45) | 74,1 % → 74,6 % (67) |
| 80–90 % | 80,5 % → 100,0 % (3) | 82,5 % → 100,0 % (8) |

## Par compétition (saisons évaluées, Brier 1X2)

| Compétition | Matchs | v1.1 | v2.0 |
|---|---|---|---|
| Africa Cup of Nations | 22 | 0,6156 | 0,5537 |
| Bundesliga | 325 | 0,5936 | 0,5893 |
| CAF Champions League | 183 | 0,5697 | 0,5332 |
| Division 1 | 343 | 0,5727 | 0,5610 |
| La Liga | 439 | 0,5862 | 0,5829 |
| Ligue 1 | 577 | 0,6350 | 0,6232 |
| Premier League | 420 | 0,6283 | 0,6231 |
| Primera División | 965 | 0,6066 | 0,5974 |
| Serie A | 430 | 0,5993 | 0,5863 |
| UEFA Champions League | 380 | 0,6108 | 0,5723 |
| UEFA Europa League | 361 | 0,6262 | 0,6094 |

## Comparaison au marché (matchs avec cotes avant le coup d'envoi : 136)

| Source | Brier 1X2 | ll 1X2 |
|---|---|---|
| Marché (cotes médianes, marge retirée) | 0,5232 | 0,8987 |
| poisson-1.1 | 0,5809 | 0,9746 |
| demi-vie 730 j · ρ 0 · k 5 | 0,5527 | 0,9391 |
| 30 % v1.1 + 70 % marché | 0,5340 | 0,9121 |
| 30 % v2.0 + 70 % marché | 0,5281 | 0,9046 |

Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.
