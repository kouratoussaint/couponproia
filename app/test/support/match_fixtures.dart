// Données de test reprises d'une vraie analyse (Lille – Lens, Ligue 1, 30/10/2026) et d'un extrait
// de statistiques au format de match_insights().
import 'package:coupon_pro_ia/features/analysis/data/analysis_models.dart';
import 'package:coupon_pro_ia/features/matches/data/insights_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';

MatchSummary lilleLens({String status = 'scheduled', int? hg, int? ag}) =>
    MatchSummary.fromJson({
      'id': 5988,
      'season': 2026,
      'kickoff_at': '2099-10-30T20:05:00+00:00',
      'status': status,
      'home_goals': hg,
      'away_goals': ag,
      'round': 'Regular Season - 9',
      'venue': 'Stade Pierre-Mauroy',
      'source_updated_at': '2026-10-30T18:00:00+00:00',
      'competition': {
        'id': 61,
        'name': 'Ligue 1',
        'country': 'France',
        'priority': 5
      },
      'home': {'id': 79, 'name': 'Lille'},
      'away': {'id': 116, 'name': 'Lens'},
    });

Map<String, dynamic> _line(
        String key, double odd, double model, double implied) =>
    {
      'key': key,
      'odd_median': odd,
      'odd_best': odd + 0.1,
      'bookmakers': 8,
      'model_probability': model,
      'implied_probability': implied,
      'edge': double.parse((model - implied).toStringAsFixed(3)),
    };

Map<String, dynamic> lilleLensAnalysisJson(
        {bool withAi = true, bool recommend = true}) =>
    {
      'id': 1,
      'match_id': 5988,
      'engine_version': 'poisson-1.1',
      'provider': withAi ? 'gemini' : null,
      'model': withAi ? 'gemini-3.5-flash-lite' : null,
      'status': withAi ? 'ok' : 'stats_only',
      'status_reason': withAi ? null : 'no_provider',
      'created_at': '2026-10-30T21:26:55Z',
      'source_updated_at': '2026-10-30T18:00:00Z',
      'stats': {
        'engine_version': 'poisson-1.1',
        'reliability': 'bonne',
        'model': {
          'expected_goals_home': 1.38,
          'expected_goals_away': 1.32,
          'probabilities': {
            '1X2.HOME': 0.385,
            '1X2.DRAW': 0.258,
            '1X2.AWAY': 0.357,
            'DC.1X': 0.643,
            'DC.X2': 0.615,
            'DC.12': 0.742,
            'OU.OVER.2.5': 0.506,
            'OU.UNDER.2.5': 0.494,
            'BTTS.YES': 0.548,
            'BTTS.NO': 0.452,
          },
          'top_scores': [
            {'score': '1-1', 'probability': 0.122},
            {'score': '1-0', 'probability': 0.093},
            {'score': '0-1', 'probability': 0.089},
          ],
        },
        'sample': {
          'competition_matches': 74,
          'home_team_home_matches': 12.5,
          'away_team_away_matches': 12.5
        },
        'teams': {
          'home': {'form': 'NDNDV'},
          'away': {'form': 'VDVDV'}
        },
        'market': {
          'captured_at': '2026-10-30T17:05:04Z',
          'lines': [
            _line('1X2.HOME', 2.7, 0.385, 0.352),
            _line('1X2.DRAW', 3.315, 0.258, 0.286),
            _line('1X2.AWAY', 2.625, 0.357, 0.362),
            _line('DC.1X', 1.5, 0.643, 0.628),
            _line('OU.OVER.2.5', 1.955, 0.506, 0.492),
            _line('BTTS.YES', 1.7, 0.548, 0.547),
          ],
        },
        'missing': [
          'Compositions, blessures et suspensions : non fournies par la source de données'
        ],
        'engine_quality': {
          'beats_baseline': {'1X2': true, 'OU': false, 'BTTS': false}
        },
      },
      'analysis': withAi
          ? {
              'resume':
                  'Lille accueille Lens dans une rencontre qui s’annonce équilibrée selon le modèle.',
              'forme':
                  'Lille est invaincu à domicile cette saison avec 2 victoires et 2 nuls en 4 rencontres.',
              'facteurs_domicile': ['Lille occupe la 3e place avec 15 points.'],
              'facteurs_exterieur': ['Lens est 8e avec 13 points.'],
              'tendances': [
                'La probabilité d’un match nul est estimée à 26 %.'
              ],
              'risques': [
                'La probabilité d’un match nul reste significative à 26 %.'
              ],
              'conclusion': 'Confrontation très ouverte. Restez prudents.',
              'informations_manquantes': [],
              'recommandation_possible': recommend,
              'marches_envisageables': [
                {
                  'cle': '1X2.HOME',
                  'probabilite_modele': 0.385,
                  'probabilite_implicite': 0.352,
                  'cote_mediane': 2.7,
                  'ecart': 0.033,
                  'justification':
                      'Lille est invaincu à domicile cette saison ; le modèle estime sa victoire à 38 %.',
                }
              ],
            }
          : null,
    };

MatchAnalysis lilleLensAnalysis({bool withAi = true, bool recommend = true}) =>
    MatchAnalysis.fromJson(
        lilleLensAnalysisJson(withAi: withAi, recommend: recommend));

Map<String, dynamic> _form(
        String date, String opp, bool home, int gf, int ga) =>
    {
      'kickoff_at': date,
      'opponent': opp,
      'at_home': home,
      'gf': gf,
      'ga': ga,
      'result': gf > ga ? 'W' : (gf == ga ? 'D' : 'L'),
      'competition': 'Ligue 1',
    };

MatchInsights lilleLensInsights() => MatchInsights.fromJson({
      'match_id': 5988,
      'computed_at': '2026-10-30T21:30:00Z',
      'standings': {
        'updated_at': '2026-10-30T03:00:00Z',
        'rows': [
          for (final (i, (id, name, pts, gd, descr)) in [
            (
              85,
              'Paris Saint Germain',
              20,
              12,
              'Promotion - Champions League (League phase)'
            ),
            (
              81,
              'Marseille',
              17,
              9,
              'Promotion - Champions League (League phase)'
            ),
            (
              79,
              'Lille',
              15,
              5,
              'Promotion - Champions League (Qualification)'
            ),
            (91, 'Monaco', 14, 4, 'Promotion - Europa League (League phase)'),
            (80, 'Lyon', 14, 3, null),
            (94, 'Rennes', 13, 2, null),
            (95, 'Strasbourg', 13, 1, null),
            (116, 'Lens', 13, 4, null),
            (84, 'Nice', 11, 0, null),
            (93, 'Reims', 9, -2, null),
            (97, 'Lorient', 6, -8, 'Relegation Play-off'),
            (98, 'Metz', 4, -10, 'Relegation'),
            (99, 'Le Havre', 3, -12, 'Relegation'),
          ].indexed)
            {
              'rank': i + 1,
              'team_id': id,
              'name': name,
              'played': 8,
              'goal_diff': gd,
              'points': pts,
              'description': descr,
            }
        ],
      },
      'form': {
        'home': [
          _form('2026-10-25T19:00:00Z', 'Nice', true, 2, 1),
          _form('2026-10-18T15:00:00Z', 'Lyon', false, 1, 2),
          _form('2026-10-04T15:00:00Z', 'Rennes', true, 1, 1),
          _form('2026-09-27T15:00:00Z', 'Monaco', false, 0, 1),
          _form('2026-09-20T15:00:00Z', 'Reims', true, 1, 1),
        ],
        'away': [
          _form('2026-10-25T15:00:00Z', 'Metz', true, 3, 0),
          _form('2026-10-18T15:00:00Z', 'Marseille', false, 1, 3),
          _form('2026-10-04T15:00:00Z', 'Lorient', true, 2, 0),
          _form('2026-09-27T15:00:00Z', 'Strasbourg', false, 1, 2),
          _form('2026-09-20T15:00:00Z', 'Le Havre', true, 4, 1),
        ],
        'home_at_home': [
          _form('2026-10-25T19:00:00Z', 'Nice', true, 2, 1),
          _form('2026-10-04T15:00:00Z', 'Rennes', true, 1, 1),
          _form('2026-09-20T15:00:00Z', 'Reims', true, 1, 1),
          _form('2026-09-06T15:00:00Z', 'Lorient', true, 2, 0),
        ],
        'away_away': [
          _form('2026-10-18T15:00:00Z', 'Marseille', false, 1, 3),
          _form('2026-09-27T15:00:00Z', 'Strasbourg', false, 1, 2),
          _form('2026-09-13T15:00:00Z', 'Nantes', false, 2, 2),
          _form('2026-08-23T15:00:00Z', 'Brest', false, 3, 0),
        ],
      },
      'season': {
        'home': {
          'played': 8,
          'goals_for': 11,
          'goals_against': 6,
          'clean_sheets': 3,
          'three_plus': 2,
          'btts': 4
        },
        'away': {
          'played': 8,
          'goals_for': 16,
          'goals_against': 12,
          'clean_sheets': 2,
          'three_plus': 5,
          'btts': 5
        },
      },
      'streaks': {
        'home': [],
        'away': [
          {
            'key': 'scored',
            'length': 9,
            'at_least': false,
            'from': '2026-08-16T15:00:00Z',
            'to': '2026-10-25T15:00:00Z'
          },
        ],
        'home_at_home': [
          {
            'key': 'unbeaten',
            'length': 4,
            'at_least': true,
            'from': '2026-09-06T15:00:00Z',
            'to': '2026-10-25T19:00:00Z'
          },
        ],
        'away_away': [],
      },
      'h2h': {
        'count': 4,
        'home_wins': 3,
        'draws': 0,
        'away_wins': 1,
        'avg_goals': 2.25,
        'first': '2024-10-26T15:00:00Z',
        'last': '2026-04-04T15:00:00Z',
        'matches': [
          {
            'kickoff_at': '2026-04-04T15:00:00Z',
            'home': 'Lille',
            'away': 'Lens',
            'home_goals': 3,
            'away_goals': 0,
            'competition': 'Ligue 1',
            'home_is_match_home': true
          },
          {
            'kickoff_at': '2025-09-20T15:00:00Z',
            'home': 'Lens',
            'away': 'Lille',
            'home_goals': 3,
            'away_goals': 0,
            'competition': 'Ligue 1',
            'home_is_match_home': false
          },
          {
            'kickoff_at': '2025-03-30T15:00:00Z',
            'home': 'Lille',
            'away': 'Lens',
            'home_goals': 1,
            'away_goals': 0,
            'competition': 'Ligue 1',
            'home_is_match_home': true
          },
          {
            'kickoff_at': '2024-10-26T15:00:00Z',
            'home': 'Lens',
            'away': 'Lille',
            'home_goals': 0,
            'away_goals': 2,
            'competition': 'Ligue 1',
            'home_is_match_home': false
          },
        ],
      },
    });
