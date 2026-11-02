# Backtest poisson-1.1 contre poisson-2.0 (2026-11-02T12:29 UTC)

Matchs évalués : saison 2025 (réglage) 2239, saison 2026 (validation) 567. Avant chaque match, au moins 30 matchs de la même saison.

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
| poisson-1.1 | 567 | 0,5947 | 0,9964 | 52,9 % | 0,6811 | 0,6897 |
| demi-vie 730 j · ρ 0 · k 5 | 567 | 0,5767 | 0,9704 | 55,4 % | 0,6836 | 0,6862 |

## Calibration 1X2 (saison en cours)

| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |
|---|---|---|
| 0–10 % | 8,5 % → 10,0 % (10) | 8,0 % → 8,3 % (24) |
| 10–20 % | 16,8 % → 14,0 % (179) | 16,1 % → 12,9 % (201) |
| 20–30 % | 25,0 % → 23,8 % (745) | 24,9 % → 22,9 % (677) |
| 30–40 % | 34,5 % → 33,5 % (260) | 34,3 % → 33,1 % (308) |
| 40–50 % | 45,1 % → 48,0 % (279) | 44,6 % → 50,8 % (248) |
| 50–60 % | 54,3 % → 57,9 % (140) | 54,4 % → 55,5 % (128) |
| 60–70 % | 64,3 % → 65,7 % (70) | 64,4 % → 69,5 % (82) |
| 70–80 % | 73,6 % → 86,7 % (15) | 74,8 % → 80,8 % (26) |
| 80–90 % | 80,5 % → 100,0 % (3) | 82,6 % → 100,0 % (7) |

## Par compétition (saisons évaluées, Brier 1X2)

| Compétition | Matchs | v1.1 | v2.0 |
|---|---|---|---|
| Africa Cup of Nations | 22 | 0,6156 | 0,5537 |
| Bundesliga | 316 | 0,6011 | 0,5968 |
| CAF Champions League | 183 | 0,5697 | 0,5332 |
| La Liga | 428 | 0,5864 | 0,5830 |
| Ligue 1 | 325 | 0,6170 | 0,6035 |
| Premier League | 409 | 0,6294 | 0,6240 |
| Serie A | 418 | 0,5980 | 0,5841 |
| UEFA Champions League | 362 | 0,6133 | 0,5756 |
| UEFA Europa League | 343 | 0,6236 | 0,6079 |

## Comparaison au marché (matchs avec cotes avant le coup d'envoi : 43)

| Source | Brier 1X2 | ll 1X2 |
|---|---|---|
| Marché (cotes médianes, marge retirée) | 0,5159 | 0,8852 |
| poisson-1.1 | 0,5657 | 0,9495 |
| demi-vie 730 j · ρ 0 · k 5 | 0,5281 | 0,9007 |
| 30 % v1.1 + 70 % marché | 0,5262 | 0,8990 |
| 30 % v2.0 + 70 % marché | 0,5170 | 0,8867 |

Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.
