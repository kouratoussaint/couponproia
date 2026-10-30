import 'package:coupon_pro_ia/features/analysis/data/analysis_format.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_models.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({Map<String, dynamic>? analysis, String status = 'ok'}) => {
      'id': 7,
      'match_id': 42,
      'engine_version': 'poisson-1.0',
      'provider': status == 'ok' ? 'gemini' : null,
      'model': status == 'ok' ? 'gemini-3.5-flash-lite' : null,
      'status': status,
      'status_reason': status == 'ok' ? null : 'no_provider',
      'created_at': '2026-10-30T10:00:00Z',
      'cached': false,
      'stats': {
        'engine_version': 'poisson-1.0',
        'reliability': 'moyenne',
        'sample': {'competition_matches': 120, 'home_team_home_matches': 6, 'away_team_away_matches': 7},
        'model': {
          'expected_goals_home': 1.62,
          'expected_goals_away': 1.05,
          'probabilities': {'1X2.HOME': 0.532, '1X2.DRAW': 0.241, '1X2.AWAY': 0.227, 'OU.OVER.2.5': 0.51},
          'top_scores': [
            {'score': '1-0', 'probability': 0.112},
          ],
        },
        'teams': {
          'home': {'form': 'VVNDV'},
          'away': {'form': 'DNV'},
        },
        'market': {
          'available': true,
          'lines': [
            {
              'key': '1X2.HOME',
              'odd_median': 1.95,
              'odd_best': 2.05,
              'bookmakers': 8,
              'implied_probability': 0.49,
              'model_probability': 0.532,
              'edge': 0.042,
            },
            {
              'key': 'BTTS.YES',
              'odd_median': 1.8,
              'odd_best': 1.9,
              'bookmakers': 8,
              'implied_probability': null,
              'model_probability': null,
              'edge': null,
            },
          ],
        },
        'engine_quality': {
          'evaluated_matches': 2210,
          'beats_baseline': {'1X2': true, 'OU': false, 'BTTS': false},
        },
        'missing': ['Compositions, blessures et suspensions : non fournies par la source de données'],
      },
      'analysis': analysis,
    };

void main() {
  test('analyse complète : fiche et texte IA lus', () {
    final a = MatchAnalysis.fromJson(_row(analysis: {
      'resume': 'Alpha favori.',
      'forme': 'Bonne forme.',
      'facteurs_domicile': ['A'],
      'facteurs_exterieur': ['B'],
      'tendances': [],
      'marches_envisageables': [
        {'cle': '1X2.HOME', 'probabilite_modele': 0.532, 'justification': 'J', 'cote_mediane': 1.95, 'ecart': 0.042},
      ],
      'risques': ['R'],
      'informations_manquantes': ['compositions, blessures et suspensions : non fournies par la source de données'],
      'conclusion': 'C',
      'recommandation_possible': true,
    }));
    expect(a.hasAi, isTrue);
    expect(a.cached, isFalse);
    expect(a.fiche.reliability, Reliability.moyenne);
    expect(a.fiche.p('1X2.HOME'), 0.532);
    expect(a.fiche.topScores.single.score, '1-0');
    expect(a.fiche.comparableLines.map((l) => l.key), ['1X2.HOME']);
    expect(a.fiche.weakGroups, ['OU', 'BTTS']);
    expect(a.ai!.picks.single.edge, 0.042);
    // Doublon fiche / IA (casse différente) fusionné.
    expect(mergedMissing(a.fiche, a.ai), hasLength(1));
  });

  test('fiche seule : pas de texte IA, raison expliquée', () {
    final a = MatchAnalysis.fromJson(_row(status: 'stats_only'));
    expect(a.hasAi, isFalse);
    expect(statsOnlyReason(a.statusReason), contains('pas encore activée'));
  });

  test('libellés des issues avec les noms des équipes', () {
    expect(outcomeKeyLabel('1X2.HOME', 'Alpha', 'Beta'), 'Victoire Alpha');
    expect(outcomeKeyLabel('1X2.DRAW', 'Alpha', 'Beta'), 'Match nul');
    expect(outcomeKeyLabel('DC.X2', 'Alpha', 'Beta'), 'Nul ou Beta');
    expect(outcomeKeyLabel('OU.OVER.2.5', 'Alpha', 'Beta'), 'Plus de 2,5 buts');
    expect(outcomeKeyLabel('BTTS.NO', 'Alpha', 'Beta'), 'Au moins une équipe ne marque pas');
  });

  test('pourcentages, écarts et résultat réel', () {
    expect(pct(0.532), '53 %');
    expect(edgePoints(0.042), '+4 pts');
    expect(edgePoints(-0.021), '−2 pts');
    expect(edgePoints(0.001), '0 pt');
    expect(actualOneXTwoKey(2, 2), '1X2.DRAW');
    expect(actualOneXTwoKey(null, 1), isNull);
  });

  test('erreurs de la fonction traduites pour l’utilisateur', () {
    expect(analysisErrorMessage(429, {'error': 'daily_limit', 'limit': 20}), contains('20 nouvelles analyses'));
    expect(analysisErrorMessage(500, 'oops'), contains('Réessayez'));
  });
}
