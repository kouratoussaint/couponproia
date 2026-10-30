import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _selection(int position, int matchId, String kickoff) => {
      'position': position,
      'selection_key': '1X2.HOME',
      'odd': 1.8,
      'odd_best': 1.92,
      'bookmakers': 9,
      'odds_captured_at': '2026-11-02T06:00:00Z',
      'model_probability': 0.6,
      'implied_probability': 0.53,
      'edge': 0.07,
      'reliability': 'bonne',
      'justification': 'Modèle : 60 % contre 53 % pour le marché.',
      'result': null,
      'match': {
        'id': matchId,
        'kickoff_at': kickoff,
        'status': 'scheduled',
        'home_goals': null,
        'away_goals': null,
        'home': {'name': 'Alpha', 'logo_url': null},
        'away': {'name': 'Beta', 'logo_url': null},
        'competition': {'name': 'Premier League'},
      },
    };

void main() {
  final json = <String, dynamic>{
    'id': 'c1',
    'category': 'du_jour',
    'title': 'Coupon du jour · lundi 2 novembre',
    'description': 'Les sélections les plus solides.',
    'risk_level': 'equilibre',
    'total_odd': 3.24,
    'combined_probability': 0.36,
    'implied_probability': 0.28,
    'status': 'published',
    'status_note': 'Publié automatiquement',
    'publish_at': '2026-11-02T08:00:00Z',
    'published_at': '2026-11-02T08:05:00Z',
    'first_kickoff_at': '2026-11-02T15:00:00Z',
    'last_kickoff_at': '2026-11-02T19:00:00Z',
    'engine_version': 'poisson-1.0',
    'data_source': 'API-Football',
    'analysis': {
      'analyse_generale': 'Deux sélections.',
      'points_de_vigilance': ['Estimation.'],
      'source': 'ia',
      'ai_model': 'gemini-3.5-flash-lite',
    },
    'result': null,
    'created_at': '2026-11-02T07:00:00Z',
    'coupon_selections': [_selection(2, 20, '2026-11-02T19:00:00Z'), _selection(1, 10, '2026-11-02T15:00:00Z')],
    'coupon_status_history': [
      {'from_status': 'ready', 'to_status': 'published', 'reason': 'Publié', 'created_at': '2026-11-02T08:05:00Z'},
      {'from_status': null, 'to_status': 'ready', 'reason': 'Généré', 'created_at': '2026-11-02T07:00:00Z'},
    ],
  };

  test('coupon lu avec ses sélections ordonnées et son historique', () {
    final c = Coupon.fromJson(json);
    expect(c.selections.map((s) => s.match.id), [10, 20]);
    expect(c.history.first.toStatus, 'ready');
    expect(c.summaryFromAi, isTrue);
    expect(c.totalOdd, 3.24);
    expect(c.selections.first.edge, 0.07);
    expect(categoryLabels[c.category], 'Coupon du jour');
  });

  test('un coupon reste « en cours » jusqu’à 3 h après le dernier coup d’envoi', () {
    final c = Coupon.fromJson(json);
    expect(c.isOpen(DateTime.parse('2026-11-02T21:00:00Z')), isTrue);
    expect(c.isOpen(DateTime.parse('2026-11-02T22:30:00Z')), isFalse);
  });

  test('profil : critères numériques lisibles', () {
    final p = CouponProfile.fromJson({
      'id': 1,
      'key': 'du_jour',
      'name': 'Coupon du jour',
      'category': 'du_jour',
      'description': null,
      'is_active': true,
      'mode': 'scheduled',
      'publish_mode': 'auto',
      'generate_times': ['07:00'],
      'publish_delay_minutes': 60,
      'criteria': {'min_total_odd': 2.5, 'markets': ['1X2']},
    });
    expect(p.num('min_total_odd'), 2.5);
    expect(p.num('markets'), isNull);
  });
}
